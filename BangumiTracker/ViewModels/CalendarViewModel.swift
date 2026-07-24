import Foundation
import Observation

@MainActor
@Observable
final class CalendarViewModel {
    var days: [CalendarDay] = []
    var isLoading = false
    var errorMessage: String?

    private let api: BangumiAPIClient

    init(api: BangumiAPIClient) {
        self.api = api
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            days = try await api.fetchCalendar()
            await WidgetDataService.writeRecommendationData(from: days)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func items(for weekdayId: Int) -> [SlimSubject] {
        days.first(where: { $0.weekday.id == weekdayId })?.items ?? []
    }
}
