import Foundation
import Combine

/// A saved hub profile that can be switched between.
struct HubProfile: Identifiable, Codable, Equatable {
    var id: String { path }
    var name: String
    var path: String

    init(name: String, path: String) {
        self.name = name
        self.path = (path as NSString).expandingTildeInPath
    }
}
