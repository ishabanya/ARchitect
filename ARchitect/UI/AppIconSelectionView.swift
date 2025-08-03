import SwiftUI

// MARK: - App Icon Selection View

struct AppIconSelectionView: View {
    @StateObject private var iconManager = AppIconManager()
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingUnlockAnimation = false
    @State private var selectedIcon: AppIconManager.AppIcon?
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(iconManager.getAllIconsWithProgress(), id: \.icon.id) { iconData in
                        IconSelectionCell(
                            iconData: iconData,
                            isSelected: iconData.icon == iconManager.currentIcon,
                            onSelect: {
                                selectedIcon = iconData.icon
                                Task {
                                    await iconManager.changeIcon(to: iconData.icon)
                                }
                            }
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: iconManager.currentIcon)
                    }
                }
                .padding()
            }
            .navigationTitle("App Icons")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iconUnlocked)) { notification in
            if let icon = notification.userInfo?["icon"] as? AppIconManager.AppIcon {
                showUnlockAnimation(for: icon)
            }
        }
        .overlay {
            if showingUnlockAnimation, let icon = selectedIcon {
                IconUnlockOverlay(icon: icon) {
                    showingUnlockAnimation = false
                    selectedIcon = nil
                }
            }
        }
    }
    
    private func showUnlockAnimation(for icon: AppIconManager.AppIcon) {
        selectedIcon = icon
        showingUnlockAnimation = true
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Icon Selection Cell

struct IconSelectionCell: View {
    let iconData: IconWithProgress
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon Container
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 22)
                    .fill(iconData.isUnlocked ? Color.clear : Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                
                // Selection Ring
                if isSelected {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 80, height: 80)
                        .scaleEffect(1.1)
                        .animation(.spring(response: 0.3), value: isSelected)
                }
                
                // Icon Image
                if iconData.isUnlocked {
                    Image(iconData.icon.previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        }
                } else {
                    // Locked Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 70, height: 70)
                        
                        Image(systemName: "lock.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                
                // Progress Ring for Locked Icons
                if !iconData.isUnlocked && iconData.progress.percentage > 0 {
                    Circle()
                        .trim(from: 0, to: iconData.progress.percentage)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 85, height: 85)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5), value: iconData.progress.percentage)
                }
                
                // Special Badge
                if iconData.icon.isSpecial && iconData.isUnlocked {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 20, height: 20)
                                )
                        }
                        Spacer()
                    }
                    .frame(width: 80, height: 80)
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2), value: isPressed)
            
            // Icon Name
            Text(iconData.icon.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(iconData.isUnlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // Progress Text for Locked Icons
            if !iconData.isUnlocked {
                ProgressText(progress: iconData.progress, condition: iconData.icon.unlockCondition)
            }
        }
        .onTapGesture {
            if iconData.isUnlocked {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                onSelect()
            }
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            // Show details
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .accessibility(label: Text("\(iconData.icon.displayName) app icon"))
        .accessibility(hint: Text(iconData.isUnlocked ? "Tap to select" : iconData.icon.unlockCondition.description))
    }
}

// MARK: - Progress Text

struct ProgressText: View {
    let progress: IconUnlockProgress
    let condition: AppIconManager.IconUnlockCondition
    
    var body: some View {
        VStack(spacing: 2) {
            if progress.percentage > 0 {
                Text("\(progress.current)/\(progress.required)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            Text(conditionShortText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
    
    private var conditionShortText: String {
        switch condition {
        case .useAppInDarkMode(let times):
            return "Use in dark \(times)x"
        case .completeProjects(let count):
            return "Complete \(count) projects"
        case .useAppConsecutiveDays(let days):
            return "Use \(days) days straight"
        case .seasonal:
            return "Seasonal"
        case .enableDeveloperMode:
            return "Developer mode"
        case .achievement(let name):
            return "Achievement: \(name)"
        case .none:
            return ""
        }
    }
}

// MARK: - Icon Unlock Overlay

struct IconUnlockOverlay: View {
    let icon: AppIconManager.AppIcon
    let onDismiss: () -> Void
    
    @State private var showContent = false
    @State private var showConfetti = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }
            
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .scaleEffect(showContent ? 1.0 : 0.5)
                        .opacity(showContent ? 1.0 : 0.0)
                    
                    Image(icon.previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .scaleEffect(showContent ? 1.0 : 0.1)
                        .rotationEffect(.degrees(showContent ? 0 : 180))
                }
                
                VStack(spacing: 12) {
                    Text("New Icon Unlocked!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(icon.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                    
                    Text(icon.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .opacity(showContent ? 1.0 : 0.0)
                .offset(y: showContent ? 0 : 20)
                
                // Dismiss Button
                Button {
                    dismissWithAnimation()
                } label: {
                    Text("Awesome!")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                }
                .opacity(showContent ? 1.0 : 0.0)
                .scaleEffect(showContent ? 1.0 : 0.8)
            }
            .padding()
            
            // Confetti Effect
            if showConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showContent = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showContent = false
            showConfetti = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            ForEach(0..<50, id: \.self) { index in
                ConfettiPiece()
                    .offset(
                        x: animate ? .random(in: -200...200) : 0,
                        y: animate ? .random(in: -400...400) : -50
                    )
                    .rotationEffect(.degrees(animate ? .random(in: 0...360) : 0))
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: .random(in: 1.0...2.0))
                        .delay(.random(in: 0...0.5)),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}

struct ConfettiPiece: View {
    let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink]
    
    var body: some View {
        Rectangle()
            .fill(colors.randomElement() ?? .blue)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Preview

struct AppIconSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        AppIconSelectionView()
    }
}