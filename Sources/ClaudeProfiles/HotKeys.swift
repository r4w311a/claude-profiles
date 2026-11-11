import Carbon.HIToolbox

final class HotKeys {
    struct Binding {
        let keyCode: UInt32
        let action: () -> Void
    }

    static let digitKeyCodes: [UInt32] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ].map(UInt32.init)
    static let previousKeyCode = UInt32(kVK_ANSI_Grave)
    static let modifiers = UInt32(controlKey | optionKey)
    static let symbol = "⌃⌥"

    private var references: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            hotKeys.actions[hotKeyID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func bind(_ bindings: [Binding]) {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        actions.removeAll()

        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode, Self.modifiers,
                                             EventHotKeyID(signature: OSType(0x434C_5052), id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { continue }
            references.append(reference)
            actions[id] = binding.action
        }
    }
}
