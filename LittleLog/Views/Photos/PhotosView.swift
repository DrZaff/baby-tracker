import SwiftUI
import PhotosUI

struct PhotosView: View {
    let baby: Baby

    @Environment(AuthService.self) private var auth
    @State private var store = PhotoStore()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploadProgress: (done: Int, total: Int)?
    @State private var uploadError: String?
    @State private var selected: BabyPhoto?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let progress = uploadProgress {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Uploading \(progress.done + 1) of \(progress.total)…")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                }
                if let uploadError {
                    Text(uploadError).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.photos) { photo in
                        Button { selected = photo } label: {
                            PhotoThumbnail(url: URL(string: photo.thumbURL))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 2))
                                .shadow(color: Theme.canopy.opacity(0.15), radius: 5, y: 3)
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .background(JungleBackground())
            .overlay {
                if store.hasLoaded && store.photos.isEmpty && uploadProgress == nil {
                    ContentUnavailableView {
                        VStack(spacing: 8) {
                            Text("🦒📸").font(.system(size: 56))
                            Text("No photos yet").font(.title2.bold())
                        }
                    } description: {
                        Text("Tap + to share photos of \(baby.name) with your family.")
                    }
                }
            }
            .navigationTitle("Photos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BabySwitcher() }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .disabled(uploadProgress != nil)
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await upload(items) }
            }
            .fullScreenCover(item: $selected) { photo in
                PhotoDetailView(photo: photo, babyID: baby.babyID)
            }
            .task(id: baby.babyID) { store.listen(babyID: baby.babyID) }
        }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        uploadError = nil
        var failures = 0
        for (index, item) in items.enumerated() {
            uploadProgress = (index, items.count)
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    failures += 1
                    continue
                }
                try await PhotoStore.upload(image, babyID: baby.babyID, auth: auth)
            } catch {
                failures += 1
            }
        }
        uploadProgress = nil
        pickerItems = []
        if failures > 0 {
            uploadError = "\(failures) photo\(failures == 1 ? "" : "s") couldn't be uploaded. Check your connection and try again."
        }
    }
}

struct PhotoThumbnail: View {
    let url: URL?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

struct PhotoDetailView: View {
    let photo: BabyPhoto
    let babyID: String

    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    @State private var editingCaption = false
    @State private var confirmingDelete = false

    init(photo: BabyPhoto, babyID: String) {
        self.photo = photo
        self.babyID = babyID
        _caption = State(initialValue: photo.caption ?? "")
    }

    var body: some View {
        NavigationStack {
            AsyncImage(url: URL(string: photo.url)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                ShareLink(item: image, preview: SharePreview(photo.caption ?? "Baby photo", image: image))
                            }
                        }
                } else if phase.error != nil {
                    Label("Couldn't load photo", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if let text = photo.caption, !text.isEmpty {
                        Text(text).font(.body)
                    }
                    Text("\(photo.createdByName) · \(photo.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.black.opacity(0.6))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { editingCaption = true } label: { Label("Caption", systemImage: "text.bubble") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .alert("Caption", isPresented: $editingCaption) {
                TextField("Add a caption", text: $caption)
                Button("Save") { PhotoStore.updateCaption(caption, photo: photo, babyID: babyID) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this photo for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await PhotoStore.delete(photo, babyID: babyID)
                        dismiss()
                    }
                }
            }
        }
    }
}
