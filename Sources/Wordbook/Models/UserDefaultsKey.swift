import Foundation

enum UserDefaultsKey: String {
    case clipboardAutoCaptureEnabled
    case defaultClipboardSource
    case defaultClipboardTags
    case appearanceMode
    case autoTranslationEnabled
    case dictionaryEnhancementEnabled
    case preferCachedDefinitions
    case reviewReminderEnabled
    case reviewReminderHour
    case reviewReminderMinute
    case dailyReviewGoal
    case myMemoryContactEmail
    case dictionaryAPIBaseURL
    case myMemoryAPIBaseURL
    case lingvaAPIBaseURL
    case libreTranslateBaseURL
    case libreTranslateAPIKey
}

extension UserDefaults {
    func string(forKey key: UserDefaultsKey) -> String? {
        string(forKey: key.rawValue)
    }

    func object(forKey key: UserDefaultsKey) -> Any? {
        object(forKey: key.rawValue)
    }

    func bool(forKey key: UserDefaultsKey) -> Bool {
        bool(forKey: key.rawValue)
    }

    func set(_ value: Any?, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }

    func register(defaults registration: [UserDefaultsKey: Any]) {
        let converted = Dictionary(uniqueKeysWithValues: registration.map { ($0.key.rawValue, $0.value) })
        register(defaults: converted)
    }
}

extension UserDefaults {
    subscript(key key: UserDefaultsKey) -> Any? {
        get { object(forKey: key.rawValue) }
        set { set(newValue, forKey: key.rawValue) }
    }
}
