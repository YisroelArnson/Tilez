import AppKit
import SwiftUI

/// Focus and the insertion point move together. SwiftUI TextField selects its
/// prefilled text on focus, which can erase the first type-to-search character.
struct GridSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    var fontSize: CGFloat = 14
    /// Optional ↑/↓ and Escape handling for fields that aren't under the grid's key monitor.
    var onMove: ((Int) -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchTextField {
        let field = SearchTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.delegate = context.coordinator
        field.onFocus = { [weak field, weak coordinator = context.coordinator] in
            guard let field, let coordinator, let window = field.window else { return }
            field.stringValue = coordinator.parent.text
            window.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        }
        return field
    }

    func updateNSView(_ field: SearchTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text { field.stringValue = text }
        field.setAccessibilityLabel(placeholder)
    }

    final class SearchTextField: NSTextField {
        var onFocus: (() -> Void)?
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { placeInsertionPointAtEnd() }
            return accepted
        }
        override func selectText(_ sender: Any?) {
            super.selectText(sender)
            // NSPopover can select the initial responder again after presenting.
            // Explicit Command–A still goes directly to the field editor.
            placeInsertionPointAtEnd()
        }
        private func placeInsertionPointAtEnd() {
            currentEditor()?.selectedRange = NSRange(location: stringValue.utf16.count, length: 0)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                DispatchQueue.main.async { [weak self] in self?.onFocus?() }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: GridSearchField
        init(_ parent: GridSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.moveUp(_:)) where parent.onMove != nil: parent.onMove?(-1)
            case #selector(NSResponder.moveDown(_:)) where parent.onMove != nil: parent.onMove?(1)
            case #selector(NSResponder.cancelOperation(_:)) where parent.onCancel != nil: parent.onCancel?()
            default: return false
            }
            return true
        }
    }
}
