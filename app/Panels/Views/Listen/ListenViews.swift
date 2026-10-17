import AVFoundation
import SwiftUI

/// Compact player shown above the tab bar while a book is being read aloud.
struct ListenMiniPlayer: View {
    @Environment(Listener.self) private var listener
    @Environment(ContentStore.self) private var store
    @State private var showControls = false

    var body: some View {
        if let book = listener.book, let page = listener.page {
            let tint = Theme.tint(store.collection(for: book)?.tint ?? "")
            HStack(spacing: 12) {
                Button { showControls = true } label: {
                    HStack(spacing: 12) {
                        ContentImage(path: page.thumb)
                            .frame(width: 24, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title)
                                .font(.serif(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(book.title) · \(listener.pageIndex + 1)/\(book.pages.count)")
                                .font(.rounded(.caption2))
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Listening to \(page.title). Show controls")

                Button { listener.toggle() } label: {
                    Image(systemName: listener.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(listener.isPlaying ? "Pause" : "Play")
                Button { listener.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 34)
                }
                .accessibilityLabel("Next page")
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 3)
            // Opaque backing: the glass accessory turns text pale over dark comic covers.
            .background(Theme.surface, in: Capsule())
            .padding(2)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Capsule().fill(tint).frame(width: geo.size.width * listener.pageProgress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 18)
                .opacity(0.8)
                .animation(.easeInOut, value: listener.pageProgress)
            }
            .sheet(isPresented: $showControls) { ListenControlsSheet() }
        }
    }
}

/// Full listen controls: transport, speed, voice and the book's pages.
struct ListenControlsSheet: View {
    @Environment(Listener.self) private var listener
    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let book = listener.book, let page = listener.page {
                let tint = Theme.tint(store.collection(for: book)?.tint ?? "")
                ScrollView {
                    VStack(spacing: 22) {
                        ContentImage(path: page.thumb)
                            .frame(width: 150, height: 225)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
                            .padding(.top, 8)
                        VStack(spacing: 4) {
                            Text(page.title)
                                .font(.serif(.title3, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.center)
                            Text("\(book.title) · page \(listener.pageIndex + 1) of \(book.pages.count)")
                                .font(.rounded(.subheadline))
                                .foregroundStyle(Theme.inkSecondary)
                                .multilineTextAlignment(.center)
                        }
                        ListenTransport(tint: tint)
                        speedPicker(tint: tint)
                        HStack(spacing: 12) {
                            Button {
                                let index = listener.pageIndex
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.read(book, at: index, mode: .text) }
                            } label: {
                                Label("Read along", systemImage: "text.alignleft").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
                            Button(role: .destructive) {
                                listener.stop()
                                dismiss()
                            } label: {
                                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FilledButtonStyle(tint: Theme.tint("coral"), secondary: true))
                        }
                        pageList(book: book, tint: tint)
                    }
                    .padding(20)
                }
                .background(Theme.background)
                .navigationTitle("Listening")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Voice", selection: Binding(get: { listener.voiceId ?? Listener.voices.first?.identifier ?? "" }, set: { listener.setVoice($0) })) {
                                ForEach(Listener.voices, id: \.identifier) { v in
                                    Text("\(v.name) · \(Self.qualityLabel(v)) · \(v.language)").tag(v.identifier)
                                }
                            }
                        } label: {
                            Image(systemName: "person.wave.2")
                        }
                        .accessibilityLabel("Voice")
                    }
                }
            } else {
                ContentUnavailableView("Nothing playing", systemImage: "headphones")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
        .presentationDetents([.large])
    }

    private func speedPicker(tint: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(Listener.speeds, id: \.self) { s in
                let selected = abs(listener.speed - s) < 0.01
                Button { listener.setSpeed(s) } label: {
                    Text(s == 1 ? "1×" : String(format: "%g×", s))
                        .font(.rounded(.subheadline, weight: .semibold).monospacedDigit())
                        .foregroundStyle(selected ? Theme.onTint : tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? tint : tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Speed")
    }

    private func pageList(book: Book, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pages").font(.serif(.headline, weight: .bold)).foregroundStyle(Theme.ink).padding(.bottom, 8)
            ForEach(Array(book.pages.enumerated()), id: \.offset) { i, p in
                Button { listener.jump(to: i) } label: {
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(.rounded(.caption, weight: .bold).monospacedDigit())
                            .foregroundStyle(i == listener.pageIndex ? Theme.onTint : Theme.inkSecondary)
                            .frame(width: 26, height: 26)
                            .background(i == listener.pageIndex ? tint : Theme.sunken, in: Circle())
                        Text(p.title)
                            .font(.serif(.subheadline, weight: i == listener.pageIndex ? .semibold : .regular))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        if i == listener.pageIndex && listener.isPlaying {
                            Image(systemName: "waveform").foregroundStyle(tint).symbolEffect(.variableColor.iterative)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.hairline)
            }
        }
        .padding(16)
        .card(radius: 18)
    }

    static func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Standard"
        }
    }
}

/// Previous / play-pause / next.
struct ListenTransport: View {
    let tint: Color
    @Environment(Listener.self) private var listener

    var body: some View {
        HStack(spacing: 36) {
            Button { listener.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 24))
            }
            .accessibilityLabel("Previous page")
            Button { listener.toggle() } label: {
                Image(systemName: listener.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.onTint)
                    .frame(width: 72, height: 72)
                    .background(tint, in: Circle())
                    .shadow(color: tint.opacity(0.4), radius: 12, y: 5)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(listener.isPlaying ? "Pause" : "Play")
            Button { listener.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 24))
            }
            .accessibilityLabel("Next page")
        }
        .foregroundStyle(Theme.ink)
        .buttonStyle(.plain)
    }
}
