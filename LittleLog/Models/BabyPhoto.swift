import Foundation
import FirebaseFirestore

/// Stored at babies/{babyId}/photos/{photoId}; image files live in Storage under babies/{babyId}/photos/.
struct BabyPhoto: Identifiable, Codable, Equatable {
    @DocumentID var id: String? = nil
    var url: String
    var thumbURL: String
    var storagePath: String
    var thumbStoragePath: String
    var caption: String?
    var createdAt: Date
    var createdByUid: String
    var createdByName: String
    /// Used by the notification function.
    var summary: String?
}
