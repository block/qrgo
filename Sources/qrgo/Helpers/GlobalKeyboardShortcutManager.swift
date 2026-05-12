import Carbon.HIToolbox
import Foundation

/// Registers a Carbon global hotkey and dispatches matching hotkey events back onto the main actor.
final class GlobalKeyboardShortcutManager {
    private let action: @MainActor () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    @MainActor
    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @MainActor
    func register(shortcut: KeyboardShortcut) -> OSStatus {
        unregister()

        let handlerStatus = installEventHandlerIfNeeded()
        guard handlerStatus == noErr else {
            return handlerStatus
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyID
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            self.hotKeyRef = hotKeyRef
        }
        return status
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandler == nil else {
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        return InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventType,
            // Carbon keeps this pointer until `eventHandler` is removed, so this manager owns both lifetimes.
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func handleHotKeyPressed() {
        Task { @MainActor [action] in
            action()
        }
    }

    private static let hotKeySignature = OSType(0x5152474F)
    private static let hotKeyID: UInt32 = 1

    private static let handleHotKeyEvent: EventHandlerUPP = { _, event, userData in
        guard let event = event,
              let userData = userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return status
        }
        guard hotKeyID.signature == GlobalKeyboardShortcutManager.hotKeySignature,
              hotKeyID.id == GlobalKeyboardShortcutManager.hotKeyID else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<GlobalKeyboardShortcutManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        manager.handleHotKeyPressed()
        return noErr
    }
}
