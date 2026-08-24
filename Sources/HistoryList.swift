import AppKit

/// Eine Zeile im Verlauf: Vorschau-Icon, Text bzw. „Bild“, Quell-App und Zeit.
final class HistoryRowView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = .systemFont(ofSize: 12.5)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: HistoryItem) {
        titleLabel.stringValue = item.preview.replacingOccurrences(of: "\n", with: " ⏎ ")

        let time = Self.relativeFormatter.localizedString(for: item.date, relativeTo: Date())
        subtitleLabel.stringValue = [item.sourceAppName, time].compactMap { $0 }.joined(separator: " · ")

        switch item.kind {
        case .image:
            iconView.image = HistoryStore.shared.image(for: item)
        case .text:
            iconView.image = Self.appIcon(bundleID: item.sourceBundleID)
                ?? NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: nil)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static var iconCache: [String: NSImage] = [:]
    private static func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        return icon
    }
}

/// Popover-Inhalt: Suchfeld, Tabelle mit dem Verlauf, Fußzeile mit Zähler und „Leeren“.
final class HistoryListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "Noch nichts kopiert")
    private let countLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "Leeren", target: nil, action: nil)
    private let openFullButton = NSButton(title: "Übersicht …", target: nil, action: nil)

    private var filtered: [HistoryItem] = []
    var onSelect: ((HistoryItem) -> Void)?
    var onOpenFullView: (() -> Void)?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 420))
        view = root
        build(in: root)
        NotificationCenter.default.addObserver(self, selector: #selector(historyChanged),
                                                name: .klemmiHistoryDidChange, object: nil)
        applyFilter()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func historyChanged() { applyFilter() }

    private func build(in root: NSView) {
        searchField.placeholderString = "Suchen …"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.rowHeight = 42
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowActivated)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let col = NSTableColumn(identifier: .init("main"))
        col.width = 316
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 10.5)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.target = self
        clearButton.action = #selector(clearHistory)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        openFullButton.bezelStyle = .rounded
        openFullButton.controlSize = .small
        openFullButton.target = self
        openFullButton.action = #selector(openFullView)
        openFullButton.translatesAutoresizingMaskIntoConstraints = false

        [searchField, scrollView, emptyLabel, countLabel, clearButton, openFullButton].forEach { root.addSubview($0) }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            countLabel.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),

            openFullButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6),
            openFullButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),

            clearButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            clearButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
    }

    func reload() { applyFilter() }

    @objc private func openFullView() { onOpenFullView?() }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = HistoryStore.shared.items
        filtered = query.isEmpty ? all : all.filter {
            ($0.text ?? "").lowercased().contains(query) || ($0.sourceAppName ?? "").lowercased().contains(query)
        }
        tableView.reloadData()
        emptyLabel.isHidden = !all.isEmpty
        countLabel.stringValue = "\(all.count) \(all.count == 1 ? "Eintrag" : "Einträge")"
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    @objc private func clearHistory() { HistoryStore.shared.clear() }

    @objc private func rowActivated() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard filtered.indices.contains(row) else { return }
        onSelect?(filtered[row])
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryRowView) ?? HistoryRowView(frame: .zero)
        cell.identifier = id
        cell.configure(with: filtered[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing, filtered.indices.contains(row) else { return [] }
        let item = filtered[row]
        return [NSTableViewRowAction(style: .destructive, title: "Löschen") { [weak self] _, _ in
            HistoryStore.shared.delete(item.id)
            self?.applyFilter()
        }]
    }
}
