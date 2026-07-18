import AppKit
import SwiftUI

/// A minimal AppKit bridge that removes NSTextView's hidden padding so its
/// insertion point shares the exact origin used by the SwiftUI placeholder.
struct AlignedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.minSize = NSSize(width: 0, height: scrollView.contentView.bounds.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text { textView.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
