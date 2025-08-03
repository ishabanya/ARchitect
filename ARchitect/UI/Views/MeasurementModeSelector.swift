import SwiftUI

struct MeasurementModeSelector: View {
    @Binding var selectedMode: MeasurementMode
    let unitSystem: UnitSystem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(MeasurementMode.allCases, id: \.self) { mode in
                    MeasurementModeRow(
                        mode: mode,
                        unitSystem: unitSystem,
                        isSelected: selectedMode == mode
                    ) {
                        selectedMode = mode
                        dismiss()
                    }
                }
            }
            .navigationTitle("Measurement Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MeasurementModeRow: View {
    let mode: MeasurementMode
    let unitSystem: UnitSystem
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(mode.instructions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack {
                        Text("Min points: \(mode.type.minimumPoints)")
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                        
                        Spacer()
                        
                        Text(unitDisplay)
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.headline)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private var unitDisplay: String {
        switch mode.type {
        case .distance, .height, .perimeter:
            return unitSystem == .metric ? "meters" : "feet"
        case .area:
            return unitSystem == .metric ? "m²" : "ft²"
        case .volume:
            return unitSystem == .metric ? "m³" : "ft³"
        case .angle:
            return "degrees"
        }
    }
}

#Preview {
    MeasurementModeSelector(
        selectedMode: .constant(.distance),
        unitSystem: .metric
    )
}