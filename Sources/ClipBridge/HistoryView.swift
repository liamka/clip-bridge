import AppKit
import SwiftUI
import ClipBridgeCore

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @AppStorage("onboardingDismissed") private var onboardingDismissed = false
    @FocusState private var searchFocused: Bool
    @State private var confirmClear = false
    @State private var launchAtLogin = LoginItem.isEnabled

    let onAssemble: (String) -> Void
    let onCopyOne: (String) -> Void
    let onSaveFile: (String) -> Void
    let onClose: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Поиск", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit(assemble)
                settingsMenu
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if !onboardingDismissed {
                onboarding
                Divider()
            }

            if model.items.isEmpty {
                emptyState
            } else {
                List(selection: $model.selection) {
                    ForEach(model.items) { item in
                        ClipRow(item: item, order: model.orderNumber(of: item.id))
                            .tag(item.id)
                            .contextMenu {
                                Button("Копировать") { model.text(of: item.id).map(onCopyOne) }
                                Button("Удалить") { model.delete([item.id]) }
                            }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand { model.delete(model.selection) }
                .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
                    // Двойной клик по одной записи — просто скопировать её как есть.
                    if ids.count == 1, let id = ids.first, let text = model.text(of: id) { onCopyOne(text) }
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 340, minHeight: 260)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onClose)
        .confirmationDialog("Очистить всю историю?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { model.clearAll() }
        } message: {
            Text("Записи удалятся без возможности восстановления.")
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Пауза записи", isOn: $model.isPaused)
            Toggle("Запускать при входе", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    LoginItem.set(on)
                    launchAtLogin = LoginItem.isEnabled
                }
            Divider()
            Button("Очистить историю…") { confirmClear = true }
                .disabled(model.items.isEmpty && model.query.isEmpty)
            Divider()
            Button("Выйти из ClipBridge", action: onQuit)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Настройки")
    }

    private var onboarding: some View {
        HStack(spacing: 6) {
            Text("⌘-клик — выбрать несколько · ⏎ — собрать · ⌘V — вставить")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button { onboardingDismissed = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Скрыть подсказку")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        Text(model.query.isEmpty ? "Скопируйте что-нибудь — появится здесь" : "Ничего не найдено")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(model.selection.isEmpty ? "\(model.items.count)" : "Выбрано \(model.selection.count)")
                .foregroundStyle(.secondary)
            if model.isPaused {
                Text("пауза").foregroundStyle(.orange)
            }
            Spacer()
            Button { model.assembledContext().map(onSaveFile) } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Сохранить в .md")
            .disabled(model.selection.isEmpty)
            Button("Собрать", action: assemble)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(model.selection.isEmpty)
        }
        .font(.caption)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func assemble() {
        guard let text = model.assembledContext() else { return }
        onAssemble(text)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let order: Int?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = appIcon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            .help(item.sourceName ?? "Неизвестный источник")
            Text(preview)
                .font(item.kind == .code ? .system(.callout, design: .monospaced) : .callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let order {
                Text("\(order)")
                    .font(.caption2.bold())
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 1)
    }

    private var symbol: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var preview: String {
        item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var appIcon: NSImage? {
        guard let id = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
