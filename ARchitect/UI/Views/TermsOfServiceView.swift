import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        Text("Terms of Service")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding(.bottom, 10)
                        
                        Text("Effective Date: \(formattedDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 20)
                        
                        termsSection(
                            title: "Acceptance of Terms",
                            content: """
                            By downloading, installing, or using ARchitect ("the App"), you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the App.
                            """
                        )
                        
                        termsSection(
                            title: "Description of Service",
                            content: """
                            ARchitect is an augmented reality application that allows users to:
                            • Scan and measure rooms using AR technology
                            • Place virtual furniture in real spaces
                            • Save and share room layouts
                            • Access furniture catalogs and recommendations
                            """
                        )
                        
                        termsSection(
                            title: "User Responsibilities",
                            content: """
                            You agree to:
                            • Use the App in accordance with applicable laws
                            • Provide accurate information when required
                            • Respect intellectual property rights
                            • Not attempt to reverse engineer or modify the App
                            • Use the App for personal, non-commercial purposes only
                            """
                        )
                        
                        termsSection(
                            title: "Privacy and Data",
                            content: """
                            • Your privacy is important to us
                            • Room scans and measurements are stored locally on your device
                            • We collect minimal analytics data to improve the App
                            • See our Privacy Policy for detailed information
                            """
                        )
                        
                        termsSection(
                            title: "Intellectual Property",
                            content: """
                            • The App and its content are protected by copyright and other laws
                            • Furniture models and designs remain property of their respective owners
                            • You retain ownership of content you create using the App
                            • You grant us permission to use aggregated, anonymized data for improvements
                            """
                        )
                        
                        termsSection(
                            title: "Disclaimers",
                            content: """
                            • The App is provided "as is" without warranties
                            • AR measurements are approximate and should not be used for construction
                            • We are not responsible for decisions made based on App measurements
                            • Furniture placement is for visualization purposes only
                            """
                        )
                        
                        termsSection(
                            title: "Limitation of Liability",
                            content: """
                            In no event shall ARchitect be liable for any indirect, incidental, special, or consequential damages arising from use of the App.
                            """
                        )
                        
                        termsSection(
                            title: "Termination",
                            content: """
                            We may terminate or suspend access to the App at any time. You may stop using the App at any time by uninstalling it from your device.
                            """
                        )
                        
                        termsSection(
                            title: "Changes to Terms",
                            content: """
                            We reserve the right to modify these terms at any time. Continued use of the App after changes constitutes acceptance of new terms.
                            """
                        )
                        
                        termsSection(
                            title: "Contact Information",
                            content: """
                            For questions about these Terms of Service, contact us at:
                            
                            Email: legal@architect-app.com
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
    
    private func termsSection(title: String, content: String) -> some View {
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
    TermsOfServiceView()
}