import SwiftUI

struct EditGroupedItemsView: View {
    @ObservedObject var appData: AppData
    let cycleId: UUID
    @State private var showingAddGroup = false
    @State private var editingGroup: GroupedItem?
    @State private var isEditing = false
    @Binding var step: Int?
    @Environment(\.dismiss) var dismiss
    
    init(appData: AppData, cycleId: UUID, step: Binding<Int?> = .constant(nil)) {
        self.appData = appData
        self.cycleId = cycleId
        self._step = step
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(Category.allCases, id: \.self) { category in
                    let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == category }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .foregroundColor(category.iconColor)
                                .font(.title3)

                            Text(category.rawValue)
                                .font(.headline)
                                .foregroundColor(.primary)

                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            if groups.isEmpty {
                                Text("No grouped items")
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal)
                            } else {
                                ForEach(groups) { group in
                                    Button(action: { editingGroup = group }) {
                                        HStack {
                                            Text(group.name)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal)
                                    }
                                    if group.id != groups.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .background(category.backgroundColor)
                        .cornerRadius(16)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                }

                // Only the Add Grouped Item button remains
                Button {
                    showingAddGroup = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Grouped Item")
                    }
                    .font(.body.weight(.medium))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .padding(.horizontal)
                }
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Edit Grouped Items")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Previous") {
                    if step != nil {
                        step! -= 1
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Next") {
                    if step != nil {
                        step! += 1
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.editMode, .constant(EditMode.inactive))
        .sheet(isPresented: $showingAddGroup) {
            NavigationStack {
                AddGroupedItemView(appData: appData, cycleId: cycleId)
            }
        }
        .sheet(item: $editingGroup) { group in
            NavigationStack {
                AddGroupedItemView(appData: appData, cycleId: cycleId, group: group)
            }
        }
    }

}

struct AddGroupedItemView: View {
    @ObservedObject var appData: AppData
    let cycleId: UUID
    @State private var group: GroupedItem?
    @State private var name: String
    @State private var category: Category = .maintenance
    @State private var selectedItemIds: [UUID] = []
    @Environment(\.dismiss) var dismiss

    init(appData: AppData, cycleId: UUID, group: GroupedItem? = nil) {
        self.appData = appData
        self.cycleId = cycleId
        self._group = State(initialValue: group)
        self._name = State(initialValue: group?.name ?? "")
        self._category = State(initialValue: group?.category ?? .maintenance)
        self._selectedItemIds = State(initialValue: group?.itemIds ?? [])
    }

    var body: some View {
        Form {
            Section {
                TextField("Group Name (e.g., Muffin)", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
            }

            Section(header: Text("Select Items")) {
                let categoryItems = appData.cycleItems[cycleId]?.filter { $0.category == category } ?? []
                if categoryItems.isEmpty {
                    Text("No items in this category")
                        .foregroundColor(.gray)
                } else {
                    ForEach(categoryItems) { item in
                        MultipleSelectionRow(
                            title: itemDisplayText(item: item),
                            isSelected: selectedItemIds.contains(item.id)
                        ) {
                            if selectedItemIds.contains(item.id) {
                                selectedItemIds.removeAll { $0 == item.id }
                            } else {
                                selectedItemIds.append(item.id)
                            }
                        }
                    }
                }
            }

            if group != nil {
                Section {
                    Button("Delete Group", role: .destructive) {
                        if let groupId = group?.id {
                            appData.removeGroupedItem(groupId, fromCycleId: cycleId)
                        }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(group == nil ? "Add Group" : "Edit Group")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    let newGroup = GroupedItem(
                        id: group?.id ?? UUID(),
                        name: name,
                        category: category,
                        itemIds: selectedItemIds
                    )
                    appData.addGroupedItem(newGroup, toCycleId: cycleId)
                    dismiss()
                }
                .disabled(name.isEmpty || selectedItemIds.isEmpty)
            }
        }
    }

    private func itemDisplayText(item: Item) -> String {
        if let dose = item.dose, let unit = item.unit {
            return "\(item.name) - \(String(format: "%.1f", dose)) \(unit)"
        }
        return item.name
    }
}

struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

