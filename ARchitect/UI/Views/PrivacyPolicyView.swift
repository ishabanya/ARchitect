import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        Text("Privacy Policy")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding(.bottom, 10)
                        
                        Text("Effective Date: \(formattedDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 20)
                        
                        privacySection(
                            title: "Information We Collect",
                            content: """
                            • Device information (model, iOS version)
                            • App usage analytics (features used, session duration)
                            • Camera permissions for AR functionality
                            • Room scan data (stored locally on your device)
                            • Furniture placement data (stored locally)
                            """
                        )
                        
                        privacySection(
                            title: "How We Use Your Information",
                            content: """
                            • To provide AR room scanning and furniture placement features
                            • To improve app performance and user experience
                            • To analyze usage patterns for feature development
                            • To provide customer support when requested
                            """
                        )
                        
                        privacySection(
                            title: "Data Storage and Security",
                            content: """
                            • All room scans and measurements are stored locally on your device
                            • We use industry-standard encryption for data transmission
                            • Analytics data is anonymized and aggregated
                            • We do not sell or share personal data with third parties
                            """
                        )
                        
                        privacySection(
                            title: "Your Rights",
                            content: """
                            • You can delete app data by uninstalling the app
                            • You can opt out of analytics in app settings
                            • You can request data deletion by contacting support
                            • You control camera and other permissions through iOS settings
                            """
                        )
                        
                        privacySection(
                            title: "Third-Party Services",
                            content: """
                            • We use Apple's analytics framework for usage tracking
                            • AR functionality uses Apple's ARKit framework
                            • No data is shared with advertising networks
                            """
                        )
                        
                        privacySection(
                            title: "Contact Us",
                            content: """
                            If you have questions about this privacy policy, please contact us at:
                            
                            Email: privacy@architect-app.com
                            """
                        )
                    }
                }
                .padding()
            }
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
    
    private func privacySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
}

#Preview {
    PrivacyPolicyView()
}