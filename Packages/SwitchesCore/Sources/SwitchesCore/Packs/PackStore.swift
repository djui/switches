import Foundation

/// Lists and loads converted themes; each subdirectory with a `theme.json` is one theme.
public struct PackStore: Sendable {
    public static let themesFolderName = "Themes"

    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    /// The `Themes/` folder reference copied into the app bundle's resources.
    public static func bundled(_ bundle: Bundle = .main) -> PackStore {
        PackStore(directory: bundle.url(forResource: themesFolderName, withExtension: nil))
    }

    /// Theme display names (folder names), sorted alphabetically.
    public func themeNames() -> [String] {
        guard let directory else { return [] }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { fm.fileExists(atPath: $0.appendingPathComponent(ThemePackLoader.manifestFileName).path) }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func loadTheme(named name: String) throws -> ThemePack {
        guard let directory else { throw ThemePackError.missingManifest(URL(fileURLWithPath: name)) }
        return try ThemePackLoader.load(from: directory.appendingPathComponent(name, isDirectory: true))
    }
}
