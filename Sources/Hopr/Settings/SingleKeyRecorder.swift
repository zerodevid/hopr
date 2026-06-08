import SwiftUI
import AppKit

struct SingleKeyRecorder: View {
    @Binding var keyCode: Int
    @State private var isRecording = false
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                isRecording.toggle()
            }) {
                Text(isRecording ? "Press Key..." : KeyCombo.keyName(keyCode: UInt16(keyCode)))
                    .font(.system(size: 13, weight: isRecording ? .semibold : .medium, design: .monospaced))
                    .foregroundColor(isRecording ? .accentColor : .primary)
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
                SingleKeyRecorderHelper(isRecording: $isRecording, keyCode: $keyCode)
                    .frame(width: 0, height: 0)
            )
            
            if isRecording {
                Button(action: {
                    isRecording = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Cancel recording")
            }
        }
    }
}

private struct SingleKeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    
    func makeNSView(context: Context) -> NSView {
        let view = SingleKeyResponderNSView()
        view.onEvent = { code in
            keyCode = Int(code)
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

private class SingleKeyResponderNSView: NSView {
    var onEvent: ((UInt16) -> Void)?
    var onCancel: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let code = event.keyCode
        if code == 53 { // Escape
            onCancel?()
            return
        }
        onEvent?(code)
    }
    
    override func resignFirstResponder() -> Bool {
        return true
    }
}
