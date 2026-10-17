import SwiftUI
import Translation
// Cross-import overlay providing `.translationTask`; xtool's Linux build doesn't pick it up implicitly.
import _Translation_SwiftUI

struct ContentView: View {
    @State private var model = ConversationModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            // Faces the person across the table.
            TranscriptPane(items: model.items(for: .top), language: model.top)
                .rotationEffect(.degrees(180))

            ControlBar(model: model)

            TranscriptPane(items: model.items(for: .bottom), language: model.bottom)
        }
        .background(Color(.systemBackground))
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .translationTask(model.translationPreparation) { session in
            do {
                try await session.prepareTranslation()
                await model.translationPrepared(success: true)
            } catch {
                await model.translationPrepared(success: false)
            }
        }
        .task {
            await model.loadAvailableLanguages()
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if model.phase == .paused || model.phase == .idle {
                    Task { await model.start() }
                }
            case .background:
                Task { await model.pause() }
            default:
                break
            }
        }
    }
}

/// Plain text, newest at the bottom (towards the middle of the phone).
private struct TranscriptPane: View {
    let items: [ConversationModel.Turn]
    let language: AppLanguage

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(items) { item in
                        let isNewest = item.id == items.last?.id
                        Text(item.translation.isEmpty ? "…" : item.translation)
                            .font(isNewest ? .title.weight(.semibold) : .title3)
                            .foregroundStyle(isNewest ? .primary : .secondary)
                            .opacity(item.isLive ? 0.6 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentTransition(.opacity)
                            .animation(.smooth(duration: 0.2), value: item.translation)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .overlay {
                if items.isEmpty {
                    Text(language.listeningHint)
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .onChange(of: items.last?.translation) {
                guard let last = items.last?.id else { return }
                withAnimation(.smooth) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The only chrome: language pair, swap, listening state, and a reset.
private struct ControlBar: View {
    let model: ConversationModel

    var body: some View {
        VStack(spacing: 8) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.smooth) { model.clear() }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body.weight(.medium))
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)

                    HStack(spacing: 2) {
                        languageMenu(.top)
                        Button {
                            withAnimation(.smooth) { model.swapSides() }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 32, height: 48)
                        }
                        languageMenu(.bottom)
                    }
                    .padding(.horizontal, 12)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Button {
                        model.toggleListening()
                    } label: {
                        micIcon
                            .font(.body.weight(.medium))
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .buttonStyle(.plain)

            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 10)
        .animation(.smooth, value: model.phase)
    }

    private var status: String? {
        switch model.phase {
        case .preparing(let message), .failed(let message): message
        case .paused: "Pausiert"
        case .idle, .listening: nil
        }
    }

    @ViewBuilder
    private var micIcon: some View {
        switch model.phase {
        case .listening:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .preparing:
            ProgressView()
        case .paused, .idle:
            Image(systemName: "mic.slash")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        }
    }

    private func languageMenu(_ side: Side) -> some View {
        Menu {
            Picker(selection: Binding(
                get: { model.language(of: side) },
                set: { model.setLanguage($0, for: side) }
            )) {
                ForEach(model.availableLanguages) { language in
                    Text(language.fullName).tag(language)
                }
            } label: {
                EmptyView()
            }
        } label: {
            Text(model.language(of: side).shortName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .frame(height: 48)
                .contentShape(.rect)
        }
    }
}
