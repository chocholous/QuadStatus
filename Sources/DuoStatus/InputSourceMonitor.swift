import AppKit
import Carbon

struct InputSource: Equatable {
    var id: String
    var name: String
    /// One letter for the menu bar: the layout's primary language ("cs" → C,
    /// "en" → E), falling back to the first letter of its name.
    var letter: String
    /// Primary language code ("cs", "en"), picks the roundel if there is one.
    var language: String
}

/// The active keyboard layout. Text Input Sources posts a distributed
/// notification on every switch, so there is nothing to poll.
final class InputSourceMonitor {
    private(set) var current: InputSource?
    var onChange: (() -> Void)?

    /// The layout you normally type in shows nothing in the menu bar; only a
    /// switch away from it does. Override with
    /// `defaults write io.github.zhenweiding-dev.duostatus defaultKeyboardLanguage -string en`
    static var defaultLanguage: String {
        UserDefaults.standard.string(forKey: "defaultKeyboardLanguage") ?? "cs"
    }

    /// The current layout, or nil while it is the default one.
    var shown: InputSource? {
        current.flatMap { $0.language == Self.defaultLanguage ? nil : $0 }
    }

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        let new = Self.describe(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
        guard new != current else { return }
        current = new
        onChange?()
    }

    /// Layouts the user has enabled and can switch to, in system order.
    var selectable: [InputSource] {
        Self.list().map { Self.describe($0) }
    }

    func select(id: String) {
        guard let source = Self.list().first(where: { Self.string($0, kTISPropertyInputSourceID) == id })
        else { return }
        TISSelectInputSource(source)
    }

    private static func list() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource,
            kTISPropertyInputSourceIsSelectCapable: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
        else { return [] }
        return list as? [TISInputSource] ?? []
    }

    private static func describe(_ source: TISInputSource) -> InputSource {
        let id = string(source, kTISPropertyInputSourceID) ?? ""
        let name = string(source, kTISPropertyLocalizedName) ?? id
        let languages = property(source, kTISPropertyInputSourceLanguages) as? [String] ?? []
        let letter = (languages.first ?? name).prefix(1).uppercased()
        return InputSource(id: id, name: name, letter: letter, language: languages.first ?? "")
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        property(source, key) as? String
    }
}
