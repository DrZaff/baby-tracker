import UIKit
import FirebaseFirestore
import FirebaseStorage

@Observable
final class PhotoStore {
    private(set) var photos: [BabyPhoto] = []
    private(set) var hasLoaded = false

    @ObservationIgnored private var listener: ListenerRegistration?

    private static func collection(_ babyID: String) -> CollectionReference {
        Firestore.firestore().collection("babies").document(babyID).collection("photos")
    }

    func listen(babyID: String) {
        listener?.remove()
        listener = Self.collection(babyID)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.photos = snapshot?.documents.compactMap { try? $0.data(as: BabyPhoto.self) } ?? []
                self.hasLoaded = true
            }
    }

    deinit { listener?.remove() }

    /// Uploads a full-size (max 2048px) image and a small thumbnail, then records the photo.
    static func upload(_ image: UIImage, babyID: String, auth: AuthService) async throws {
        let id = UUID().uuidString
        let storage = Storage.storage().reference()
        let path = "babies/\(babyID)/photos/\(id).jpg"
        let thumbPath = "babies/\(babyID)/photos/\(id)_thumb.jpg"

        guard let full = image.resized(maxDimension: 2048).jpegData(compressionQuality: 0.8),
              let thumb = image.resized(maxDimension: 400).jpegData(compressionQuality: 0.7) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        let fullRef = storage.child(path)
        let thumbRef = storage.child(thumbPath)
        _ = try await fullRef.putDataAsync(full, metadata: metadata)
        _ = try await thumbRef.putDataAsync(thumb, metadata: metadata)
        let url = try await fullRef.downloadURL()
        let thumbURL = try await thumbRef.downloadURL()

        let photo = BabyPhoto(
            url: url.absoluteString,
            thumbURL: thumbURL.absoluteString,
            storagePath: path,
            thumbStoragePath: thumbPath,
            caption: nil,
            createdAt: Date(),
            createdByUid: auth.uid,
            createdByName: auth.displayName,
            summary: "shared a new photo"
        )
        _ = try collection(babyID).addDocument(from: photo)
    }

    static func updateCaption(_ caption: String, photo: BabyPhoto, babyID: String) {
        guard let id = photo.id else { return }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        collection(babyID).document(id).updateData(["caption": trimmed.isEmpty ? NSNull() : trimmed])
    }

    static func delete(_ photo: BabyPhoto, babyID: String) async {
        guard let id = photo.id else { return }
        let storage = Storage.storage().reference()
        try? await storage.child(photo.storagePath).delete()
        try? await storage.child(photo.thumbStoragePath).delete()
        try? await collection(babyID).document(id).delete()
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
