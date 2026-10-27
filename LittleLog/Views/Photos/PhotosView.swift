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
                PhotoDetailView(store: store, startID: photo.pageID, babyID: baby.babyID)
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

extension BabyPhoto {
    /// Stable id for paging, even before the server assigns a document id.
    var pageID: String { id ?? url }
}

/// Full-screen photos: swipe left and right to move between them, newest first like the grid.
struct PhotoDetailView: View {
    let store: PhotoStore
    let babyID: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String
    @State private var loaded: [String: Image] = [:]
    @State private var caption = ""
    @State private var editingCaption = false
    @State private var confirmingDelete = false

    init(store: PhotoStore, startID: String, babyID: String) {
        self.store = store
        self.babyID = babyID
        _currentID = State(initialValue: startID)
    }

    private var current: BabyPhoto? { store.photos.first { $0.pageID == currentID } }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentID) {
                ForEach(store.photos, id: \.pageID) { photo in
                    AsyncImage(url: URL(string: photo.url)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                                .onAppear { loaded[photo.pageID] = image }
                        } else if phase.error != nil {
                            Label("Couldn't load photo", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(photo.pageID)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let photo = current {
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
            }
            .navigationTitle(positionText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if let photo = current, let image = loaded[photo.pageID] {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: image, preview: SharePreview(photo.caption ?? "Baby photo", image: image))
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        caption = current?.caption ?? ""
                        editingCaption = true
                    } label: { Label("Caption", systemImage: "text.bubble") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .alert("Caption", isPresented: $editingCaption) {
                TextField("Add a caption", text: $caption)
                Button("Save") {
                    if let photo = current { PhotoStore.updateCaption(caption, photo: photo, babyID: babyID) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this photo for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteCurrent() }
            }
        }
    }

    /// "3 of 12", so it's clear there are more to swipe through.
    private var positionText: String {
        guard store.photos.count > 1, let index = store.photos.firstIndex(where: { $0.pageID == currentID }) else { return "" }
        return "\(index + 1) of \(store.photos.count)"
    }

    /// Deletes the photo on screen and moves to the next one (or closes when it was the last).
    private func deleteCurrent() {
        guard let photo = current, let index = store.photos.firstIndex(where: { $0.pageID == photo.pageID }) else { return }
        let others = store.photos.filter { $0.pageID != photo.pageID }
        Task {
            await PhotoStore.delete(photo, babyID: babyID)
            if others.isEmpty {
                dismiss()
            } else {
                currentID = others[min(index, others.count - 1)].pageID
            }
        }
    }
}
