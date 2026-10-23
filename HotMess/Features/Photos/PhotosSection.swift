//
//  PhotosSection.swift
//  HotMess
//

import SwiftUI
import UIKit

/// A page's photos: photographers' and the ones members took with the app's
/// camera, newest first, each badged Pro or not. At the venue the user is at
/// it leads with "Take a photo": camera only, posted to the venue, the event
/// under way and whoever is on stage. Loads on its own, and draws nothing
/// while loading, when there are none and no camera, or on an API without
/// photos.
struct PhotosSection: View {
    let subject: PostsSubject
    /// The venue the user is at, when this page is it: offers the camera.
    var cameraVenueID: UUID?
    var title = String(localized: "Photos")

    @Environment(AppModel.self) private var model
    @State private var photos: [EventPhoto] = []
    @State private var capturing = false
    @State private var noCamera = false
    @State private var captured: CapturedPhoto?
    @State private var viewing: EventPhoto?
    /// What the viewer asked for, run once its sheet is down.
    @State private var afterViewing: (() -> Void)?
    @State private var reportSubject: ReportSubject?
    @State private var blockTarget: BlockedUser?

    var body: some View {
        Group {
            if !photos.isEmpty || cameraVenueID != nil {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    if photos.isEmpty {
                        Text("Snap the stage. Your photo goes on the venue's and the event's pages, and the performers' too.")
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    } else {
                        strip
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .task(id: subject) { await load() }
        .fullScreenCover(isPresented: $capturing) {
            CameraCapture { image in
                capturing = false
                if let image { captured = CapturedPhoto(image: image) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $captured) { photo in
            if let venueID = cameraVenueID {
                CrowdPhotoReview(image: photo.image, venueID: venueID) { posted in
                    photos.insert(posted, at: 0)
                }
            }
        }
        .sheet(item: $viewing, onDismiss: {
            afterViewing?()
            afterViewing = nil
        }) { photo in
            PhotoViewer(photo: photo) { action in
                afterViewing = { handle(action, on: photo) }
                viewing = nil
            }
        }
        .alert(String(localized: "No camera"), isPresented: $noCamera) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Photos here are taken with the camera, and this device doesn't have one.")
        }
        .contentReporting(report: $reportSubject, block: $blockTarget)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.hotMess(.subheadline, semibold: true))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if cameraVenueID != nil {
                Button {
                    if CameraCapture.isAvailable { capturing = true } else { noCamera = true }
                } label: {
                    Label(String(localized: "Take a photo"), systemImage: "camera.fill")
                        .font(.hotMess(.subheadline, semibold: true))
                }
                .accessibilityIdentifier("photos.take")
            }
        }
        .padding(.horizontal, 20)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(photos) { photo in
                    Button { viewing = photo } label: { PhotoThumbnail(photo: photo) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 132)
    }

    private func load() async {
        guard let fresh = try? await model.api.photos(subject) else { return }
        photos = fresh
    }

    private func handle(_ action: PhotoViewer.Action, on photo: EventPhoto) {
        switch action {
        case let .person(id):
            model.push(.person(id))
        case .report:
            reportSubject = ReportSubject(target: .photo, targetID: photo.id.uuidString.lowercased())
        case .remove:
            photos.removeAll { $0.id == photo.id }
            Task { try? await model.api.removePhoto(photo.id) }
        }
    }
}

/// A photo just taken, until it's posted or thrown away.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// One square in the strip: the photo, with a Pro badge on a photographer's.
private struct PhotoThumbnail: View {
    let photo: EventPhoto

    var body: some View {
        Color.hotMessPhotoPlaceholder
            .overlay { RemoteImage(url: photo.url) }
            .frame(width: 132, height: 132)
            .clipShape(.rect(cornerRadius: HotMessRadius.lg))
            .overlay(alignment: .topLeading) {
                if photo.isProfessional {
                    PhotoSourceTag(isProfessional: true)
                        .padding(6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(photo.altText ?? photo.peopleNames ?? String(localized: "Photo"))
            .accessibilityValue(photo.credit ?? "")
            .accessibilityAddTraits([.isImage, .isButton])
    }
}

/// "Pro" on a photographer's photo, "Crowd" on a member's.
struct PhotoSourceTag: View {
    let isProfessional: Bool

    var body: some View {
        Text(isProfessional ? String(localized: "Pro") : String(localized: "Crowd"))
            .font(.hotMess(fixedSize: 11, semibold: true))
            .tracking(0.2)
            .foregroundStyle(isProfessional ? Color.hotMessOnAccent : Color.hotMessAccentInk)
            .padding(.horizontal, 6)
            .frame(minHeight: 16)
            .background(isProfessional ? Color.hotMessAccent : Color.hotMessAccentSoft, in: .capsule)
            .fixedSize()
    }
}

/// A photo full size: who took it, who's in it, and Remove (theirs) or Report.
struct PhotoViewer: View {
    enum Action {
        case person(UUID)
        case report
        case remove
    }

    let photo: EventPhoto
    let onAction: (Action) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingRemove = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RemoteImage(url: photo.url, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: HotMessRadius.photo))
                        .accessibilityLabel(photo.altText ?? String(localized: "Photo"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            PhotoSourceTag(isProfessional: photo.isProfessional)
                            if let credit = photo.credit {
                                Text(credit)
                                    .font(.hotMess(.subheadline, semibold: true))
                            }
                        }
                        if let event = photo.event {
                            Text("At \(event.name)")
                                .font(.hotMess(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        if let caption = photo.caption {
                            Text(caption)
                                .font(.hotMess(.subheadline))
                        }
                        if !photo.people.isEmpty {
                            Text("On stage")
                                .font(.hotMess(.footnote, semibold: true))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            ForEach(photo.people) { person in
                                Button(person.name) { onAction(.person(person.id)) }
                                    .font(.hotMess(.body, semibold: true))
                            }
                        }
                        if photo.isProfessional, let viewURL = photo.viewURL {
                            Button(String(localized: "See it full size")) { openURL(viewURL) }
                                .font(.hotMess(.subheadline, semibold: true))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if photo.viewerCanRemove {
                            Button(role: .destructive) { confirmingRemove = true } label: {
                                Label(String(localized: "Remove Photo"), systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) { onAction(.report) } label: {
                                Label(String(localized: "Report Photo…"), systemImage: "exclamationmark.bubble")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("photo.optionsMenu")
                }
            }
            .confirmationDialog(
                String(localized: "Remove this photo from every page it's on?"),
                isPresented: $confirmingRemove,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Remove Photo"), role: .destructive) { onAction(.remove) }
            }
        }
    }
}

/// The photo just taken, before it goes up: Post or Retake. Says where it
/// goes, as the server tags whoever is on stage.
struct CrowdPhotoReview: View {
    let image: UIImage
    let venueID: UUID
    let onPosted: (EventPhoto) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: HotMessRadius.photo))
                        .accessibilityLabel(String(localized: "The photo you took"))

                    Text("It goes on the venue's page, tonight's event and the pages of whoever's on stage, credited to you by your first name and initial.")
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "Describe it for screen readers (optional)"), text: $description, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .navigationTitle(String(localized: "New Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Discard")) { dismiss() }
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button(String(localized: "Post")) { Task { await post() } }
                            .accessibilityIdentifier("photos.post")
                    }
                }
            }
            .interactiveDismissDisabled(isPosting)
        }
    }

    private func post() async {
        guard let jpeg = image.uploadJPEG() else {
            errorMessage = String(localized: "Couldn't read that photo. Please take another.")
            return
        }
        isPosting = true
        defer { isPosting = false }
        do {
            let photo = try await model.api.takePhoto(
                venueID: venueID,
                jpeg: jpeg,
                altText: description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onPosted(photo)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn't post the photo. Please try again.")
        }
    }
}
