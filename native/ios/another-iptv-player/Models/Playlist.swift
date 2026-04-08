import Foundation
import GRDB

struct Playlist: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable {
    var id: UUID
    var name: String
    var serverURL: String
    var username: String
    var password: String
    var createdAt: Date = Date()
    var filterAdultContent: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, serverURL, username, password, createdAt, filterAdultContent
    }

    init(id: UUID = UUID(), name: String, serverURL: String, username: String, password: String, filterAdultContent: Bool = false) {
        self.id = id
        self.name = name
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.filterAdultContent = filterAdultContent
    }
}

// MARK: - Persistence
extension Playlist {
    static let databaseTableName = "playlist"
}
