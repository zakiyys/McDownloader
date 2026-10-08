import Foundation

/// Loads and saves `AppConfig`. Kept deliberately small: read once at launch,
/// write on every change, so a crash never loses a setting.
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { save() }
    }

    init() {
        if let data = try? Data(contentsOf: AppPaths.configFile),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = .default()
        }
    }

    func save() {
        do {
            try AppPaths.ensureDirectories()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: AppPaths.configFile, options: .atomic)
        } catch {
            Log.error("failed to save config: \(error.localizedDescription)")
        }
    }
}
