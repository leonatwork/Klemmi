import AppKit

/// Wie der Verlauf in der Übersicht gruppiert wird.
enum GroupingMode: Int, CaseIterable {
    case date, app, type, none

    var title: String {
        switch self {
        case .date: return "Datum"
        case .app: return "App"
        case .type: return "Typ"
        case .none: return "Alle"
        }
    }
}

/// Knoten der Gruppierung (Datum/App/Typ) im Übersichtsfenster.
final class GroupNode: NSObject {
    let title: String
    let children: [ItemNode]
    init(title: String, children: [ItemNode]) {
        self.title = title
        self.children = children
    }
}

/// Blatt-Knoten: ein einzelner Verlaufseintrag.
final class ItemNode: NSObject {
    let item: HistoryItem
    init(_ item: HistoryItem) { self.item = item }
}

/// NSOutlineView, die pro Zeile ein Kontextmenü anbietet (Rechtsklick).
final class HistoryOutlineView: NSOutlineView {
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return contextMenuProvider?(row)
    }
}

/// Großes Übersichtsfenster: Suche, Gruppierung nach Datum/App/Typ.
final class MainWindowController: NSWindowController, NSWindowDelegate,
    NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {

    private let searchField = NSSearchField()
    private let groupControl = NSSegmentedControl(labels: GroupingMode.allCases.map(\.title),
                                                    trackingMode: .selectOne, target: nil, action: nil)
    private let outlineView = HistoryOutlineView()
    private let countLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "Leeren", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "Noch nichts kopiert")

    private var groups: [GroupNode] = []
    private var mode: GroupingMode {
        get { GroupingMode(rawValue: Settings.groupingMode) ?? .date }
        set { Settings.groupingMode = newValue.rawValue }
    }

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Klemmi – Übersicht"
        w.center()
        w.setFrameAutosaveName("KlemmiMain")
        w.minSize = NSSize(width: 320, height: 360)
        self.init(window: w)
        w.delegate = self
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(historyChanged),
                                                name: .klemmiHistoryDidChange, object: nil)
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func historyChanged() { reload() }

    private func build() {
        guard let content = window?.contentView else { return }

        searchField.placeholderString = "Suchen …"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        groupControl.selectedSegment = mode.rawValue
        groupControl.target = self
        groupControl.action = #selector(groupChanged)
        groupControl.translatesAutoresizingMaskIntoConstraints = false

        outlineView.headerView = nil
        outlineView.indentationPerLevel = 0
        outlineView.backgroundColor = .clear
        outlineView.selectionHighlightStyle = .regular
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(rowActivated)
        outlineView.contextMenuProvider = { [weak self] row in self?.buildContextMenu(for: row) }
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let col = NSTableColumn(identifier: .init("main"))
        col.width = 400
        col.resizingMask = .autoresizingMask
        outlineView.addTableColumn(col)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.target = self
        clearButton.action = #selector(clearHistory)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        [searchField, groupControl, scrollView, emptyLabel, countLabel, clearButton].forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            groupControl.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            groupControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),

            scrollView.topAnchor.constraint(equalTo: groupControl.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            countLabel.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            clearButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    // MARK: Gruppierung

    @objc private func groupChanged() {
        mode = GroupingMode.allCases[groupControl.selectedSegment]
        reload()
    }

    private func reload() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = HistoryStore.shared.items
        let filteredItems = query.isEmpty ? all : all.filter {
            ($0.text ?? "").lowercased().contains(query) || ($0.sourceAppName ?? "").lowercased().contains(query)
        }
        groups = Self.buildGroups(from: filteredItems, mode: mode)
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        emptyLabel.isHidden = !all.isEmpty
        countLabel.stringValue = "\(all.count) \(all.count == 1 ? "Eintrag" : "Einträge")"
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    private static func buildGroups(from items: [HistoryItem], mode: GroupingMode) -> [GroupNode] {
        switch mode {
        case .none:
            guard !items.isEmpty else { return [] }
            return [GroupNode(title: "Alle (\(items.count))", children: items.map(ItemNode.init))]

        case .type:
            let texts = items.filter { $0.kind == .text }
            let images = items.filter { $0.kind == .image }
            var out: [GroupNode] = []
            if !texts.isEmpty { out.append(GroupNode(title: "Text (\(texts.count))", children: texts.map(ItemNode.init))) }
            if !images.isEmpty { out.append(GroupNode(title: "Bilder (\(images.count))", children: images.map(ItemNode.init))) }
            return out

        case .app:
            var order: [String] = []
            var buckets: [String: [HistoryItem]] = [:]
            for item in items {
                let key = item.sourceAppName ?? "Unbekannt"
                if buckets[key] == nil { buckets[key] = []; order.append(key) }
                buckets[key]!.append(item)
            }
            let sortedKeys = order.sorted { (buckets[$0]?.count ?? 0) > (buckets[$1]?.count ?? 0) }
            return sortedKeys.map { GroupNode(title: "\($0) (\(buckets[$0]!.count))", children: buckets[$0]!.map(ItemNode.init)) }

        case .date:
            let cal = Calendar.current
            var order: [String] = []
            var buckets: [String: [HistoryItem]] = [:]
            let df = DateFormatter()
            df.dateStyle = .long
            df.locale = Locale(identifier: "de_DE")
            for item in items {
                let key: String
                if cal.isDateInToday(item.date) { key = "Heute" }
                else if cal.isDateInYesterday(item.date) { key = "Gestern" }
                else if let days = cal.dateComponents([.day], from: item.date, to: Date()).day, days < 7 { key = "Diese Woche" }
                else { key = df.string(from: item.date) }
                if buckets[key] == nil { buckets[key] = []; order.append(key) }
                buckets[key]!.append(item)
            }
            let priority: [String: Int] = ["Heute": 0, "Gestern": 1, "Diese Woche": 2]
            let sortedKeys = order.sorted { a, b in
                if let pa = priority[a], let pb = priority[b] { return pa < pb }
                if priority[a] != nil { return true }
                if priority[b] != nil { return false }
                let da = buckets[a]?.first?.date ?? .distantPast
                let db = buckets[b]?.first?.date ?? .distantPast
                return da > db
            }
            return sortedKeys.map { GroupNode(title: "\($0) (\(buckets[$0]!.count))", children: buckets[$0]!.map(ItemNode.init)) }
        }
    }

    // MARK: Aktionen

    @objc private func clearHistory() { HistoryStore.shared.clear() }

    @objc private func rowActivated() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard let node = outlineView.item(atRow: row) as? ItemNode else { return }
        Clipboard.copyToPasteboard(node.item)
    }

    private func buildContextMenu(for row: Int) -> NSMenu? {
        guard let node = outlineView.item(atRow: row) as? ItemNode else { return nil }
        let menu = NSMenu()
        let copy = NSMenuItem(title: "In Zwischenablage kopieren", action: #selector(copyRow(_:)), keyEquivalent: "")
        let delete = NSMenuItem(title: "Löschen", action: #selector(deleteRow(_:)), keyEquivalent: "")
        [copy, delete].forEach { $0.target = self; $0.representedObject = node.item; menu.addItem($0) }
        return menu
    }

    @objc private func copyRow(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? HistoryItem else { return }
        Clipboard.copyToPasteboard(item)
    }

    @objc private func deleteRow(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? HistoryItem else { return }
        HistoryStore.shared.delete(item.id)
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return groups.count }
        if let g = item as? GroupNode { return g.children.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return groups[index] }
        return (item as! GroupNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is GroupNode
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is GroupNode
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        item is GroupNode ? 22 : 44
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is ItemNode
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let g = item as? GroupNode {
            let id = NSUserInterfaceItemIdentifier("group")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? Self.makeGroupCell(id: id)
            cell.textField?.stringValue = g.title
            return cell
        }
        if let n = item as? ItemNode {
            let id = NSUserInterfaceItemIdentifier("row")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? HistoryRowView) ?? HistoryRowView(frame: .zero)
            cell.identifier = id
            cell.configure(with: n.item)
            return cell
        }
        return nil
    }

    private static func makeGroupCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
