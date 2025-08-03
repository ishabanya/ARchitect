import SwiftUI

// MARK: - Furniture Filters View

public struct FurnitureFiltersView: View {
    @Binding var filters: FurnitureFilters
    @Environment(\.dismiss) private var dismiss
    @State private var tempFilters: FurnitureFilters
    
    public init(filters: Binding<FurnitureFilters>) {
        self._filters = filters
        self._tempFilters = State(initialValue: filters.wrappedValue)
    }
    
    public var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Categories
                    FilterSection(title: "Categories") {
                        categoryFilters
                    }
                    
                    // Price Range
                    FilterSection(title: "Price Range") {
                        priceFilters
                    }
                    
                    // Materials
                    FilterSection(title: "Materials") {
                        materialFilters
                    }
                    
                    // Styles
                    FilterSection(title: "Styles") {
                        styleFilters
                    }
                    
                    // Colors
                    FilterSection(title: "Color Families") {
                        colorFilters
                    }
                    
                    // Features
                    FilterSection(title: "Features") {
                        featureFilters
                    }
                    
                    // Dimensions
                    FilterSection(title: "Maximum Dimensions") {
                        dimensionFilters
                    }
                    
                    // Other Options
                    FilterSection(title: "Other Options") {
                        otherFilters
                    }
                }
                .padding()
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear All") {
                        tempFilters = FurnitureFilters()
                    }
                    .disabled(!tempFilters.hasActiveFilters)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        filters = tempFilters
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Category Filters
    
    private var categoryFilters: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
            ForEach(FurnitureCategory.allCases, id: \.self) { category in
                FilterChip(
                    title: category.displayName,
                    icon: category.icon,
                    isSelected: tempFilters.categories.contains(category)
                ) {
                    toggleSelection(category, in: &tempFilters.categories)
                }
            }
        }
    }
    
    // MARK: - Price Filters
    
    private var priceFilters: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Price Range Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Price Range")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(PriceRange.allCases, id: \.self) { range in
                        FilterChip(
                            title: range.displayName,
                            isSelected: tempFilters.priceRange == range
                        ) {
                            tempFilters.priceRange = tempFilters.priceRange == range ? nil : range
                        }
                    }
                }
            }
            
            // Custom Price Range
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Price Range")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Min Price")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("$0", value: $tempFilters.minPrice, format: .currency(code: "USD"))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.decimalPad)
                    }
                    
                    Text("to")
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                    
                    VStack(alignment: .leading) {
                        Text("Max Price")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("$10,000", value: $tempFilters.maxPrice, format: .currency(code: "USD"))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.decimalPad)
                    }
                }
            }
        }
    }
    
    // MARK: - Material Filters
    
    private var materialFilters: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(FurnitureMaterial.allCases, id: \.self) { material in
                FilterChip(
                    title: material.displayName,
                    isSelected: tempFilters.materials.contains(material)
                ) {
                    toggleSelection(material, in: &tempFilters.materials)
                }
            }
        }
    }
    
    // MARK: - Style Filters
    
    private var styleFilters: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
            ForEach(FurnitureStyle.allCases, id: \.self) { style in
                FilterChip(
                    title: style.displayName,
                    isSelected: tempFilters.styles.contains(style)
                ) {
                    toggleSelection(style, in: &tempFilters.styles)
                }
            }
        }
    }
    
    // MARK: - Color Filters
    
    private var colorFilters: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(ColorFamily.allCases, id: \.self) { colorFamily in
                FilterChip(
                    title: colorFamily.displayName,
                    isSelected: tempFilters.colorFamilies.contains(colorFamily)
                ) {
                    toggleSelection(colorFamily, in: &tempFilters.colorFamilies)
                }
            }
        }
    }
    
    // MARK: - Feature Filters
    
    private var featureFilters: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
            ForEach(FunctionalFeature.allCases, id: \.self) { feature in
                FilterChip(
                    title: feature.displayName,
                    icon: feature.icon,
                    isSelected: tempFilters.features.contains(feature)
                ) {
                    toggleSelection(feature, in: &tempFilters.features)
                }
            }
        }
    }
    
    // MARK: - Dimension Filters
    
    private var dimensionFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Width (m)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Max width", value: $tempFilters.maxWidth, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                }
                
                VStack(alignment: .leading) {
                    Text("Depth (m)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Max depth", value: $tempFilters.maxDepth, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                }
                
                VStack(alignment: .leading) {
                    Text("Height (m)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Max height", value: $tempFilters.maxHeight, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                }
            }
        }
    }
    
    // MARK: - Other Filters
    
    private var otherFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("In Stock Only", isOn: $tempFilters.inStockOnly)
            
            HStack {
                Text("Assembly Required")
                Spacer()
                Picker("Assembly", selection: $tempFilters.assemblyRequired) {
                    Text("Any").tag(nil as Bool?)
                    Text("Yes").tag(true as Bool?)
                    Text("No").tag(false as Bool?)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
            }
            
            HStack {
                Text("Show Custom Items Only")
                Spacer()
                Picker("Custom", selection: $tempFilters.showCustomOnly) {
                    Text("All").tag(nil as Bool?)
                    Text("Custom Only").tag(true as Bool?)
                    Text("Standard Only").tag(false as Bool?)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 180)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleSelection<T: Hashable>(_ item: T, in array: inout [T]) {
        if let index = array.firstIndex(of: item) {
            array.remove(at: index)
        } else {
            array.append(item)
        }
    }
}

// MARK: - Filter Section

private struct FilterSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            content
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void
    
    init(title: String, icon: String? = nil, isSelected: Bool, onTap: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color(.systemGray6))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    FurnitureFiltersView(filters: .constant(FurnitureFilters()))
}