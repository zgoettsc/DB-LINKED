import SwiftUI

struct SettingsView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingRoomCodeSheet = false
    @State private var newRoomCode = ""
    @State private var showingConfirmation = false
    @State private var showingShareSheet = false
    @State private var selectedUser: User?
    @State private var showingEditNameSheet = false
    @State private var editedName = ""
    
    var body: some View {
        List {
            // Plan section
            if appData.currentUser?.isAdmin ?? false {
                Section(header: Text("PLAN MANAGEMENT")) {
                    NavigationLink(destination: EditPlanView(appData: appData)) {
                        HStack {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.blue)
                            Text("Edit Plan")
                                .font(.headline)
                        }
                    }
                }
            }
            
            // Notifications section
            Section(header: Text("NOTIFICATIONS")) {
                NavigationLink(destination: NotificationsView(appData: appData)) {
                    HStack {
                        Image(systemName: "bell")
                            .foregroundColor(.orange)
                        Text("Notifications")
                            .font(.headline)
                    }
                }
            }
            
            // History and contacts
            Section(header: Text("OTHER")) {
                NavigationLink(destination: HistoryView(appData: appData)) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.green)
                        Text("History")
                            .font(.headline)
                    }
                }
                
                NavigationLink(destination: ContactTIPsView()) {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.indigo)
                        Text("Contact TIPs")
                            .font(.headline)
                    }
                }
            }

            Section(header: Text("ACCOUNT")) {
                NavigationLink(destination: AccountSettingsView(appData: appData)) {
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundColor(.blue)
                        Text("Account Settings")
                            .font(.headline)
                    }
                }
                
                Button(action: {
                    // Sign out of Firebase Auth
                    authViewModel.signOut()
                    
                    // Also perform app data cleanup
                    UserDefaults.standard.removeObject(forKey: "currentUserId")
                    UserDefaults.standard.removeObject(forKey: "currentRoomId")
                    appData.currentUser = nil
                    appData.currentRoomId = nil
                    
                    // Notify ContentView to show login screen
                    NotificationCenter.default.post(name: Notification.Name("UserDidSignOut"), object: nil)
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                        Text("Sign Out")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // User Management section (only show for admins)
            if appData.currentUser?.isAdmin ?? false {
                Section(header: Text("USER MANAGEMENT")) {
                    NavigationLink(destination: UserManagementView(appData: appData)) {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.purple)
                            Text("Manage Users")
                                .font(.headline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
