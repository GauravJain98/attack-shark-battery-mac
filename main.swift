import AppKit
import IOKit.hid
import ServiceManagement
import UserNotifications

// The 1d57:fa60 receiver exposes no standard battery field. Its vendor interface
// pushes `03 xx 40 <state> <level>` every ~2s; `03 xx 01 00 00` frames appear when
// the link blinks and must not be read as 0%.
private let vendorID = 0x1D57
private let productID = 0xFA60
private let batteryReportID: UInt8 = 0x03
private let batteryFrameMarker: UInt8 = 0x40
private let chargingState: UInt8 = 0x03

private let thresholdChoices = [10, 15, 20, 25, 30]
private let defaultThreshold = 20
// Re-arm only after a clear recovery so jitter around the threshold doesn't notify repeatedly.
private let rearmMargin = 5
private let staleAfter: TimeInterval = 30

private enum DefaultsKey {
    static let threshold = "lowBatteryThreshold"
    static let loginItemConfigured = "loginItemConfigured"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let thresholdMenu = NSMenu()
    private let loginItemToggle = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
    private var hidManager: IOHIDManager?
    private var level: Int?
    private var charging = false
    private var lastFrameAt = Date.distantPast
    private var lowBatteryNotified = false
    private var receiverOpenFailed = false

    private var hasFreshReading: Bool {
        Date().timeIntervalSince(lastFrameAt) <= staleAfter
    }

    private var threshold: Int {
        get { UserDefaults.standard.object(forKey: DefaultsKey.threshold) as? Int ?? defaultThreshold }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.threshold) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mouse battery")
        statusItem.button?.imagePosition = .imageLeading
        buildMenu()
        enableLoginItemOnFirstLaunch()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startListening()
        // Common modes keep the status line live while the menu is open.
        let displayTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refreshDisplay() }
        RunLoop.main.add(displayTimer, forMode: .common)
        refreshDisplay()
    }

    private func buildMenu() {
        for choice in thresholdChoices {
            let item = NSMenuItem(title: "\(choice)%", action: #selector(selectThreshold(_:)), keyEquivalent: "")
            item.tag = choice
            item.target = self
            thresholdMenu.addItem(item)
        }
        let thresholdItem = NSMenuItem(title: "Notify Below", action: nil, keyEquivalent: "")
        thresholdItem.submenu = thresholdMenu
        loginItemToggle.target = self

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(thresholdItem)
        menu.addItem(loginItemToggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        refreshMenuState()
    }

    // Login-item approval can change in System Settings while the app runs.
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func refreshMenuState() {
        for item in thresholdMenu.items {
            item.state = item.tag == threshold ? .on : .off
        }
        loginItemToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func selectThreshold(_ sender: NSMenuItem) {
        threshold = sender.tag
        lowBatteryNotified = false
        refreshMenuState()
        checkLowBattery()
    }

    private func enableLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.loginItemConfigured) else { return }
        if (try? SMAppService.mainApp.register()) != nil {
            UserDefaults.standard.set(true, forKey: DefaultsKey.loginItemConfigured)
        }
        refreshMenuState()
    }

    @objc private func toggleLoginItem() {
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refreshMenuState()
    }

    private func startListening() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_SystemControl,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, _, _, reportID, report, reportLength in
            guard let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().handleReport(id: UInt8(reportID), bytes: bytes)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        receiverOpenFailed = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) != kIOReturnSuccess
        hidManager = manager
    }

    private func handleReport(id reportID: UInt8, bytes: [UInt8]) {
        guard reportID == batteryReportID, bytes.count >= 5,
              bytes[0] == batteryReportID, bytes[2] == batteryFrameMarker,
              bytes[4] <= 100 else { return }
        level = Int(bytes[4])
        charging = bytes[3] == chargingState
        lastFrameAt = Date()
        checkLowBattery()
        refreshDisplay()
    }

    private func checkLowBattery() {
        guard let level, hasFreshReading else { return }
        if charging || level >= threshold + rearmMargin {
            lowBatteryNotified = false
        } else if level <= threshold && !lowBatteryNotified {
            lowBatteryNotified = true
            let content = UNMutableNotificationContent()
            content.title = "Mouse battery low"
            content.body = "Attack Shark mouse is at \(level)%. Time to charge it."
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
        }
    }

    private func refreshDisplay() {
        guard let level, hasFreshReading else {
            statusItem.button?.title = " –"
            statusLine.title = receiverOpenFailed ? "Can't access the receiver" : "Mouse asleep or disconnected"
            return
        }
        statusItem.button?.title = " \(level)%\(charging ? "⚡" : "")"
        statusLine.title = "Battery \(level)% · \(charging ? "Charging" : "On battery")"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
