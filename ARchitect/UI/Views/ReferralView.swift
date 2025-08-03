import SwiftUI

struct ReferralView: View {
    @StateObject private var referralManager = ReferralManager.shared
    @State private var showingShareSheet = false
    @State private var referralCodeInput = ""
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    myReferralSection
                    
                    rewardsSection
                    
                    enterReferralSection
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Referrals")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: [referralManager.shareReferralCode()])
            }
            .alert("Success!", isPresented: $showingSuccessAlert) {
                Button("OK") { }
            } message: {
                Text("Referral code applied successfully! You've earned a reward.")
            }
            .alert("Invalid Code", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                Text("This referral code is invalid or you've already used it.")
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Invite Friends & Earn Rewards")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Share ARchitect with friends and unlock exclusive features together!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var myReferralSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Referral Code")
                    .font(.headline)
                Spacer()
                Text("\(referralManager.referralCount) referrals")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            
            HStack {
                Text(referralManager.referralCode)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button(action: { showingShareSheet = true }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share with Friends")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Available Rewards")
                .font(.headline)
            
            ForEach(referralManager.getReferralProgress(), id: \.reward.id) { item in
                RewardCard(reward: item.reward, progress: item.progress)
            }
        }
    }
    
    private var enterReferralSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Have a Referral Code?")
                .font(.headline)
            
            HStack {
                TextField("Enter code", text: $referralCodeInput)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                
                Button("Apply") {
                    applyReferralCode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(referralCodeInput.isEmpty)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = referralManager.referralCode
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func applyReferralCode() {
        let success = referralManager.processReferral(code: referralCodeInput.uppercased())
        referralCodeInput = ""
        
        if success {
            showingSuccessAlert = true
        } else {
            showingErrorAlert = true
        }
    }
}

struct RewardCard: View {
    let reward: ReferralManager.ReferralReward
    let progress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(reward.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if reward.isClaimed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else {
                    Text("\(reward.requiredReferrals)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: reward.isClaimed ? .green : .blue))
        }
        .padding()
        .background(reward.isClaimed ? Color.green.opacity(0.1) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ReferralView()
}