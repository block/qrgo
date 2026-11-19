import AppKit
import Testing
@testable import qrgo

@MainActor
struct MenuBarDeviceSelectionTests {
    private let ios = TargetOption(displayName: "iPhone", systemSymbolName: "iphone", action: .ios(udid: "sim-1"))
    private let android = TargetOption(
        displayName: "Pixel", systemSymbolName: "candybarphone", action: .android(deviceId: "phone-1"),
        androidPreferenceKey: "android:phone-1"
    )
    private let local = TargetOption(displayName: "This computer", systemSymbolName: "desktopcomputer", action: .local)
    private let copy = TargetOption(displayName: "Copy", systemSymbolName: "doc.on.doc", action: .copy)
    private let skip = TargetOption(displayName: "Skip", systemSymbolName: "xmark", action: .skip)

    @Test func `no preference presents chooser and preserves its result`() async {
        let fallback = RecordingTargetSelector(result: .copy)
        let selector = PreferredDeviceTargetSelector(fallback: fallback, preferredDeviceKey: { nil })

        let action = await selector.selectTarget(for: "cashme://test", from: [ios, copy], footerWarning: "ADB warning")

        #expect(action == .copy)
        #expect(fallback.urls == ["cashme://test"])
        #expect(fallback.options.map(\.action) == [ios.action, .copy])
        #expect(fallback.warning == "ADB warning")
    }

    @Test func `available preferred destinations bypass chooser`() async {
        for option in [ios, android, local] {
            let fallback = RecordingTargetSelector(result: .skip)
            let selector = PreferredDeviceTargetSelector(
                fallback: fallback, preferredDeviceKey: { option.action.key }
            )

            let action = await selector.selectTarget(
                for: "cashme://test", from: [ios, android, local, copy, skip], footerWarning: nil
            )

            #expect(action == option.action)
            #expect(fallback.urls.isEmpty)
        }
    }

    @Test func `disconnected preference falls back and resumes after reconnection`() async {
        let fallback = RecordingTargetSelector(result: nil)
        let selector = PreferredDeviceTargetSelector(fallback: fallback, preferredDeviceKey: { ios.action.key })

        let disconnected = await selector.selectTarget(
            for: "cashme://first", from: [android, local], footerWarning: "ADB warning"
        )
        #expect(disconnected == nil)
        #expect(fallback.warning == "The selected device is unavailable. Choose another destination.\nADB warning")

        let reconnected = await selector.selectTarget(for: "cashme://second", from: [ios, local], footerWarning: nil)
        #expect(reconnected == ios.action)
        #expect(fallback.urls == ["cashme://first"])
    }

    @Test func `copy and skip cannot become automatic device destinations`() async {
        for option in [copy, skip] {
            let fallback = RecordingTargetSelector(result: nil)
            let selector = PreferredDeviceTargetSelector(fallback: fallback, preferredDeviceKey: { option.action.key })
            let result = await selector.selectTarget(for: "cashme://test", from: [copy, skip], footerWarning: nil)
            #expect(result == nil)
            #expect(fallback.urls == ["cashme://test"])
        }
    }

    @Test func `emulator preference follows the AVD across ports and ignores the original port`() async {
        let replacement = emulator(named: "Other_Pixel", serial: "emulator-5554", transportID: 7)
        let preferred = emulator(named: "Pixel_8", serial: "emulator-5556", transportID: 8)
        let fallback = RecordingTargetSelector(result: .skip)
        let selector = PreferredDeviceTargetSelector(fallback: fallback, preferredDeviceKey: { "android-avd:Pixel_8" })

        let missing = await selector.selectTarget(for: "cashme://first", from: [replacement], footerWarning: nil)
        #expect(missing == .skip)
        #expect(fallback.warning == "The selected device is unavailable. Choose another destination.")

        let available = await selector.selectTarget(
            for: "cashme://second", from: [replacement, preferred], footerWarning: nil
        )
        #expect(available == .android(deviceId: "emulator-5556", transportID: 8))
        #expect(fallback.urls == ["cashme://first"])
    }

    @Test func `legacy port keys and ambiguous or unverified AVDs use the chooser`() async {
        let first = emulator(named: "Pixel_8", serial: "emulator-5554", transportID: 7)
        let duplicate = emulator(named: "Pixel_8", serial: "emulator-5556", transportID: 8)
        let noTransport = emulator(named: "Pixel_8", serial: "emulator-5558", transportID: nil)
        let noName = emulator(named: "", serial: "emulator-5560", transportID: 9)
        let cases = [
            ("android:emulator-5554", [first]),
            ("android-avd:Pixel_8", [first, duplicate]),
            ("android-avd:Pixel_8", [noTransport, noName])
        ]
        for (key, options) in cases {
            let fallback = RecordingTargetSelector(result: .skip)
            let selector = PreferredDeviceTargetSelector(fallback: fallback, preferredDeviceKey: { key })
            let result = await selector.selectTarget(for: "cashme://test", from: options, footerWarning: nil)
            #expect(result == .skip)
        }
    }

    @Test func `menu lists device destinations and allows selecting and clearing a preference`() async {
        _ = NSApplication.shared
        var preference: String?
        let controller = MenuBarDeviceMenu(
            loadTargets: { AvailableTargetOptions(options: [ios, android, local, copy, skip], footerWarning: nil) },
            readPreference: { preference },
            writePreference: { preference = $0 }
        )
        await controller.refreshDevices()

        #expect(controller.menu.title == "Default Device")
        #expect(controller.menu.items.map(\.title) == ["No default", "", "iPhone", "Pixel", "This computer"])
        #expect(controller.menu.items[0].state == .on)
        controller.menu.performActionForItem(at: 3)
        #expect(preference == android.action.key)
        #expect(controller.menu.items[3].state == .on)
        #expect(controller.menu.items[0].state == .off)

        controller.menu.performActionForItem(at: 0)
        #expect(preference == nil)
        #expect(controller.menu.items[0].state == .on)
    }

    @Test func `menu refresh removes disconnected devices and keeps unavailable preference clearable`() async {
        _ = NSApplication.shared
        var options = [ios, android]
        var preference: String? = ios.action.key
        let controller = MenuBarDeviceMenu(
            loadTargets: { AvailableTargetOptions(options: options, footerWarning: nil) },
            readPreference: { preference },
            writePreference: { preference = $0 }
        )
        await controller.refreshDevices()
        options = []
        await controller.refreshDevices()

        #expect(controller.menu.items.map(\.title) == [
            "No default", "", "Unavailable: ios:sim-1", "No devices available"
        ])
        #expect(controller.menu.items[2].state == .on)
        #expect(!controller.menu.items[2].isEnabled)
        controller.menu.performActionForItem(at: 0)
        #expect(preference == nil)
    }

    @Test func `refresh preserves the selected row while loading and when devices are unchanged`() async throws {
        _ = NSApplication.shared
        var willLoad: () -> Void = {}
        let controller = MenuBarDeviceMenu(
            loadTargets: {
                willLoad()
                return AvailableTargetOptions(options: [ios, android], footerWarning: nil)
            },
            readPreference: { android.action.key }
        )
        #expect(controller.menu.items.map(\.title) == ["No default", "", "Loading devices…"])
        await controller.refreshDevices()
        let selectedItem = try #require(controller.menu.items.last)
        willLoad = {
            #expect(controller.menu.items.last === selectedItem)
            #expect(selectedItem.state == .on)
            #expect(selectedItem.isEnabled)
        }

        await controller.refreshDevices()

        #expect(controller.menu.items.last === selectedItem)
    }

    private func emulator(named name: String, serial: String, transportID: UInt64?) -> TargetOption {
        let device = AndroidDeviceConnection(id: serial, transportID: transportID)
        let details = AndroidEmulatorHelper.deviceDetails(for: device, properties: ["ro.boot.qemu.avd_name": name])
        return TargetOption(
            displayName: details.displayName,
            systemSymbolName: "candybarphone",
            action: .android(deviceId: serial, transportID: transportID),
            androidPreferenceKey: details.preferenceKey
        )
    }
}

@MainActor
private final class RecordingTargetSelector: QRGoTargetSelecting {
    let result: TargetAction?
    var urls: [String] = []
    var options: [TargetOption] = []
    var warning: String?

    init(result: TargetAction?) {
        self.result = result
    }

    func selectTarget(
        for urlString: String, from options: [TargetOption], footerWarning: String?
    ) async -> TargetAction? {
        urls.append(urlString)
        self.options = options
        warning = footerWarning
        return result
    }
}
