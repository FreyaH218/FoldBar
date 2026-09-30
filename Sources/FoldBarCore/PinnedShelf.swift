import Foundation

/// Prefer the accessibility identifier. Names are a conservative fallback for apps without one.
/// Neither process IDs nor AX object hashes survive a restart.
public struct MenuItemReference: Codable, Equatable, Identifiable {
    public let identifier: String
    public let title: String
    public let occurrence: Int
    public let wasOnlyItem: Bool

    public var id: String {
        identifier.isEmpty ? "title:\(title):\(occurrence)" : "identifier:\(identifier):\(occurrence)"
    }

    /// A live menu keeps its icon when AX proxies or hosted windows are recreated.
    /// Keep processes separate, and ignore a changing title only for a sole item.
    public func runtimeID(processID: Int32) -> String {
        let menu = identifier.isEmpty && wasOnlyItem ? "single" : id
        return "process:\(processID)/menu:\(menu)"
    }

    public init(identifier: String, title: String, occurrence: Int, wasOnlyItem: Bool) {
        self.identifier = identifier
        self.title = title
        self.occurrence = max(0, occurrence)
        self.wasOnlyItem = wasOnlyItem
    }

    public func resolve(in candidates: [MenuItemReference]) -> Int? {
        if let exact = candidates.firstIndex(where: { $0.id == id }) { return exact }
        // A changing title is safe to ignore only when both snapshots have exactly one unnamed item.
        if identifier.isEmpty, wasOnlyItem, candidates.count == 1,
           candidates[0].identifier.isEmpty { return 0 }
        return nil
    }
}

/// A saved application reference deliberately contains no process identifier.
/// A process can exit or restart while its place in the shelf remains unchanged.
public struct PinnedApplication: Codable, Equatable, Identifiable {
    public let name: String
    public let bundleID: String
    public let bundlePath: String?
    public let menuItem: MenuItemReference?

    public var applicationID: String {
        bundleID.isEmpty ? "path:\(bundlePath ?? "")" : "bundle:\(bundleID)"
    }
    public var id: String { applicationID + (menuItem.map { "/menu:\($0.id)" } ?? "") }

    public init?(name: String, bundleID: String, bundlePath: String?, menuItem: MenuItemReference? = nil) {
        let identifier = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = bundlePath.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0).standardizedFileURL.path : nil }
        guard !identifier.isEmpty || path != nil else { return nil }
        self.name = name
        self.bundleID = identifier
        self.bundlePath = path
        self.menuItem = menuItem
    }
}

public struct PinnedShelf: Codable, Equatable {
    public private(set) var applications: [PinnedApplication]

    public init(applications: [PinnedApplication] = []) {
        var seen = Set<String>()
        self.applications = applications.compactMap {
            guard let normalized = PinnedApplication(name: $0.name, bundleID: $0.bundleID, bundlePath: $0.bundlePath, menuItem: $0.menuItem),
                  seen.insert(normalized.id).inserted else { return nil }
            return normalized
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(applications: try values.decode([PinnedApplication].self, forKey: .applications))
    }

    /// Dropping onto a tile inserts before it. Dropping on the empty area appends.
    /// Removing the source before looking up the target handles moves in both directions.
    public mutating func insert(_ app: PinnedApplication, before targetID: String? = nil, moveExisting: Bool = true) {
        guard app.id != targetID else { return }
        if !moveExisting && applications.contains(where: { $0.id == app.id }) { return }
        applications.removeAll { $0.id == app.id }
        let index = targetID.flatMap { target in applications.firstIndex { $0.id == target } } ?? applications.endIndex
        applications.insert(app, at: index)
    }

    public mutating func remove(id: String) {
        applications.removeAll { $0.id == id }
    }

    public mutating func move(id: String, offset: Int) {
        guard let source = applications.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(source + offset, 0), applications.count - 1)
        guard source != destination else { return }
        applications.insert(applications.remove(at: source), at: destination)
    }
}
