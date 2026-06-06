import SwiftUI
import AppKit

struct ShortcutRecorder: View {
    @Binding var keyCombo: KeyCombo
    @State private var isRecording = false
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                isRecording.toggle()
            }) {
                Text(isRecording ? "Press Keys..." : (keyCombo.keyCode == 0 ? "Record Shortcut" : keyCombo.displayString))
                    .font(.system(size: 13, weight: isRecording ? .semibold : .medium, design: .monospaced))
                    .foregroundColor(isRecording ? .accentColor : (keyCombo.keyCode == 0 ? .secondary : .primary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1.2)
                            .background(isRecording ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
            .background(
                ShortcutRecorderHelper(isRecording: $isRecording, keyCombo: $keyCombo)
                    .frame(width: 0, height: 0)
            )
            
            if !isRecording && keyCombo.keyCode != 0 {
                Button(action: {
                    keyCombo = KeyCombo(keyCode: 0, modifiers: 0)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
    }
}

private struct ShortcutRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCombo: KeyCombo
    
    func makeNSView(context: Context) -> NSView {
        let view = ResponderNSView()
        view.onEvent = { keyCode, modifiers in
            keyCombo = KeyCombo(keyCode: keyCode, modifiers: modifiers.rawValue)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                }
            }
        } else {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder === nsView {
                    nsView.window?.makeFirstResponder(nil)
                }
            }
        }
    }
}

private class ResponderNSView: NSView {
    var onEvent: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        if keyCode == 53 { // Escape
            onCancel?()
            return
        }
        
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Enforce that at least one modifier key (Cmd, Shift, Opt, Ctrl) is pressed to prevent hijacks of standard typing keys
        guard !modifiers.isEmpty else {
            return
        }
        
        onEvent?(keyCode, modifiers)
    }
    
    override func resignFirstResponder() -> Bool {
        return true
    }
}
