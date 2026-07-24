import Foundation
import SwiftData

@Model
final class SearchHistory {
    var id: UUID
    var keyword: String
    var searchType: String
    var searchedAt: Date

    init(keyword: String, searchType: String = "subject") {
        self.id = UUID()
        self.keyword = keyword
        self.searchType = searchType
        self.searchedAt = Date()
    }
}
