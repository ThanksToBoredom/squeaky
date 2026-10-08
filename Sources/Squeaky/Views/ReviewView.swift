import SwiftUI

struct ReviewView: View {
    @Bindable var model: ModuleModel
    @ViewState private var categoryID: String
    @ViewState private var sort: ItemSort = .size

    enum ItemSort: String, CaseIterable, Identifiable {
        case size = "Size", name = "Name"
        var id: Self { self }
    }

    init(model: ModuleModel, initialCategoryID: String?) {
        self.model = model
        _categoryID = ViewState(wrappedValue: initialCategoryID ?? model.categories.first?.id ?? "")
    }

    private var category: ScanCategory? {
        model.categories.first { $0.id == categoryID } ?? model.categories.first
    }

    private var sortedItems: [CleanItem] {
        guard let category else { return [] }
        return switch sort {
        case .size: category.items.sorted { model.effectiveSize(of: $0) > model.effectiveSize(of: $1) }
        case .name: category.items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                categoryList
                itemList
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            ZStack {
                PrimaryActionButton(
                    title: model.module.actionVerb,
                    palette: model.module.palette,
                    enabled: !model.selection.isEmpty
                ) {
                    model.requestClean()
                }
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.selectedSize().formattedBytes)
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()
                        let count = model.selectedItems().count
                        Text("\(count) item\(count == 1 ? "" : "s") selected")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 40)
            }
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(model.categories) { category in
                    let isCurrent = category.id == self.category?.id
                    HStack(spacing: 10) {
                        CheckBox(state: model.checkState(for: category)) {
                            model.setAll(category, selected: model.checkState(for: category) != .on)
                        }
                        SymbolImage(name: category.symbol, size: 13)
                            .frame(width: 18)
                        Text(category.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(category.totalSize.formattedBytes)
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(isCurrent ? 0.18 : 0))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { categoryID = category.id }
                }
            }
            .padding(10)
        }
        .frame(width: 310)
        .glassCard()
    }

    @ViewBuilder
    private var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let category {
                HStack(alignment: .top, spacing: 14) {
                    CategoryBadge(symbol: category.symbol, palette: model.module.palette, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.system(size: 20, weight: .semibold))
                        Text(category.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.bottom, 12)

                HStack {
                    let state = model.checkState(for: category)
                    Button(state == .on ? "Deselect All" : "Select All") {
                        model.setAll(category, selected: state != .on)
                    }
                    .buttonStyle(GlassButtonStyle())
                    Spacer()
                    Picker("Sort by", selection: $sort) {
                        ForEach(ItemSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                }
                .padding(.bottom, 8)

                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

                ScrollView {
                    let showsDisclosure = category.items.contains { !$0.extras.isEmpty }
                    LazyVStack(spacing: 2) {
                        ForEach(sortedItems) { item in
                            ItemRow(item: item, model: model, showsDisclosure: showsDisclosure)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Spacer()
                Text("Nothing left to review.")
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
}

/// An item, plus its support files when expanded. Each support file can be unticked on its own.
private struct ItemRow: View {
    let item: CleanItem
    let model: ModuleModel
    let showsDisclosure: Bool

    @ViewState private var expanded = false

    var body: some View {
        let isOn = model.selection.contains(item.url)
        VStack(spacing: 2) {
            FileRow(
                url: item.url,
                name: item.name,
                detail: item.detail,
                size: model.effectiveSize(of: item),
                isOn: isOn,
                toggle: { model.toggle(item) },
                leading: showsDisclosure ? AnyView(disclosure) : nil
            )
            if expanded {
                ForEach(item.extras) { extra in
                    FileRow(
                        url: extra.url,
                        name: extra.url.lastPathComponent,
                        detail: extra.url.deletingLastPathComponent().abbreviatedPath,
                        size: extra.size,
                        iconSize: 22,
                        isOn: !model.excludedExtras.contains(extra.url),
                        toggle: { model.toggleExtra(extra) }
                    )
                    .padding(.leading, 26)
                    // Support files only matter while their app is selected.
                    .opacity(isOn ? 1 : 0.45)
                    .disabled(!isOn)
                }
            }
        }
    }

    private var disclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 14, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.extras.isEmpty ? 0 : 0.8)
        .disabled(item.extras.isEmpty)
        .help(expanded ? "Hide support files" : "Show support files")
    }
}

private struct FileRow: View {
    let url: URL
    let name: String
    let detail: String?
    let size: Int64
    var iconSize: CGFloat = 30
    let isOn: Bool
    let toggle: () -> Void
    var leading: AnyView?

    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let leading {
                leading.padding(.trailing, -4)
            }
            CheckBox(state: isOn ? .on : .off, action: toggle)
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: iconSize < 30 ? 12 : 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            Text(size.formattedBytes)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, iconSize < 30 ? 3 : 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
    }
}
