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
    let onRecordShortcut: () -> Void
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

            if model.isRecordingShortcut {
                recordingBanner
                Divider()
            } else if !onboardingDismissed {
                onboarding
                Divider()
            }

            if model.items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List(selection: $model.selection) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            ClipRow(item: item, order: model.orderNumber(of: item.id),
                                    number: index < 9 ? index + 1 : nil,
                                    isCursor: model.cursor == item.id)
                                .tag(item.id)
                                .id(item.id)
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
                    .onChange(of: model.cursor) { id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            if model.showPreview {
                Divider()
                PreviewPane(item: model.cursor.flatMap(model.item))
                    .frame(height: 150)
            }

            Divider()
            footer
        }
        .frame(minWidth: 340, minHeight: 260)
        .onAppear { searchFocused = true }
        .onChange(of: model.searchFocusRequest) { _ in searchFocused = true }
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
            Button("Сочетание для окна: \(model.shortcutDisplay)…", action: onRecordShortcut)
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

    private var recordingBanner: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Нажмите новое сочетание для окна · Esc — отмена")
                if let error = model.shortcutError {
                    Text(error).foregroundStyle(.orange)
                }
            }
            .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var onboarding: some View {
        HStack(spacing: 6) {
            Text("↑↓ и пробел или ⌘-клик — выбрать · ⌘1…9 — по номеру\n⏎ — собрать · ⌘V — вставить · ⌘Y — просмотр")
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
            Button { model.togglePreview() } label: {
                Image(systemName: model.showPreview ? "eye.fill" : "eye")
            }
            .buttonStyle(.borderless)
            .help("Просмотр записи (⌘Y)")
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
    /// Номер для ⌘1…9.
    let number: Int?
    let isCursor: Bool

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
            } else if let number {
                Text("⌘\(number)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, lineWidth: isCursor ? 1.5 : 0)
        )
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

/// Запись целиком: источник, время, размер и текст с прокруткой.
struct PreviewPane: View {
    let item: ClipItem?
    /// Больше не показываем: огромный Text заметно тормозит окно.
    static let maxCharacters = 20_000

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 4) {
                Text(meta(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(shown(item))
                        .font(item.kind == .code ? .system(.caption, design: .monospaced) : .caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else {
            Text("Выберите строку стрелками или кликом")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func meta(_ item: ClipItem) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(item.text.utf8.count), countStyle: .file)
        let lines = item.text.split(separator: "\n", omittingEmptySubsequences: false).count
        let time = item.copiedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(item.sourceName ?? "Неизвестный источник") · \(time) · \(lines) стр. · \(bytes)"
    }

    private func shown(_ item: ClipItem) -> String {
        guard item.text.count > Self.maxCharacters else { return item.text }
        return String(item.text.prefix(Self.maxCharacters)) + "\n\n… показано начало, в сборку войдёт целиком"
    }
}
