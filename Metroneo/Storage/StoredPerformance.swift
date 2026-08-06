import Foundation
import SwiftData

/// SwiftData row for the performance **sidecar** (DESIGN R3.1) — the local
/// metadata attached to an Apple reminder, keyed by its stable external id.
@Model
final class StoredPerformance {
    @Attribute(.unique) var reminderId: String
    var rating: Int?
    var performanceNotes: String?
    var estimatedDuration: Int?
    var actualDuration: Int?

    init(reminderId: String, rating: Int? = nil, performanceNotes: String? = nil,
         estimatedDuration: Int? = nil, actualDuration: Int? = nil) {
        self.reminderId = reminderId
        self.rating = rating
        self.performanceNotes = performanceNotes
        self.estimatedDuration = estimatedDuration
        self.actualDuration = actualDuration
    }
}
