import AppKit
import Testing
@testable import qrgo

@MainActor
struct MenuBarDeviceSelectionTests {
    private let ios = TargetOption(displayName: "iPhone", systemSymbolName: "iphone", action: .ios(udid: "sim-1"))
    private let android = TargetOption(
        displayName: "Pixel", systemSymbolName: "candybarphone", action: .android(deviceId: "emulator-5554")
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

    @Test func `menu lists device destinations and allows selecting and clearing a preference`() async {
        _ = NSApplication.shared
        var preference: String?
        let controller = MenuBarDeviceMenu(
            loadTargets: { AvailableTargetOptions(options: [ios, android, local, copy, skip], footerWarning: nil) },
            readPreference: { preference },
            writePreference: { preference = $0 }
        )
        await controller.refreshDevices()

        #expect(controller.menu.items.map(\.title) == ["None", "", "iPhone", "Pixel", "This computer"])
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
            "None", "", "Selected device unavailable", "No devices available"
        ])
        #expect(controller.menu.items[2].state == .on)
        #expect(!controller.menu.items[2].isEnabled)
        controller.menu.performActionForItem(at: 0)
        #expect(preference == nil)
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
