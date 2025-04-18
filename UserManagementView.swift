import SwiftUI
import FirebaseDatabase
import MessageUI

struct UserManagementView: View {
    @ObservedObject var appData: AppData
    @State private var users: [User] = []
    @State private var pendingInvitations: [String: [String: Any]] = [:]
    @State private var isShowingInviteSheet = false
    @State private var isLoading = true
    @State private var isShowingMessageComposer = false
    @State private var messageRecipient = ""
    @State private var messageBody = ""
    @State private var editedName: String = ""
    @State private var showingEditNameSheet = false
    @State private var selectedUser: User? = nil
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading users...")
            } else {
                List {
                    Section(header: Text("CURRENT USERS")) {
                        ForEach(users) { user in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text(user.isAdmin ? "Admin" : "Regular User")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Menu {
                                    // Only show "Remove Admin" if not the last admin
                                    if user.isAdmin && !isLastAdmin(user) {
                                        Button(action: {
                                            toggleAdminStatus(user)
                                        }) {
                                            Label("Remove Admin Permissions", systemImage: "person.fill.badge.minus")
                                        }
                                    } else if !user.isAdmin {
                                        Button(action: {
                                            toggleAdminStatus(user)
                                        }) {
                                            Label("Make Admin", systemImage: "person.fill.badge.plus")
                                        }
                                    }
                                    
                                    // Only show edit name and sign out for current user
                                    if user.id == appData.currentUser?.id {
                                        Button(action: {
                                            editedName = user.name
                                            selectedUser = user
                                            showingEditNameSheet = true
                                        }) {
                                            Label("Edit Name", systemImage: "pencil")
                                        }
                                        
                                        // Only show sign out if not the last admin
                                        if !isLastAdmin(user) {
                                            Button(action: {
                                                signOut()
                                            }) {
                                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                            }
                                        }
                                    }
                                    
                                    // Only show remove user if not the last admin
                                    if !(user.id == appData.currentUser?.id && isLastAdmin(user)) {
                                        Button(action: {
                                            removeUser(user)
                                        }) {
                                            Label("Remove User", systemImage: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                    }
                    
                    Section(header: Text("PENDING INVITATIONS")) {
                        if pendingInvitations.isEmpty {
                            Text("No pending invitations")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(pendingInvitations.keys), id: \.self) { code in
                                if let invitation = pendingInvitations[code] {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Code: \(code)")
                                                .font(.headline)
                                            
                                            if let phone = invitation["phoneNumber"] as? String {
                                                Text(phone)
                                                    .font(.subheadline)
                                            }
                                            
                                            Text(invitation["isAdmin"] as? Bool == true ? "Admin" : "Regular User")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Text("Status: \(invitation["status"] as? String ?? "Unknown")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            resendInvitation(code, invitation: invitation)
                                        }) {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                        }
                                        
                                        Button(action: {
                                            deleteInvitation(code)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Section {
                        Button(action: {
                            isShowingInviteSheet = true
                        }) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Invite New User")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage Users")
        .onAppear(perform: loadData)
        .sheet(isPresented: $isShowingInviteSheet) {
            NavigationView {
                InviteUserView(appData: appData, onComplete: loadData)
            }
        }
        .sheet(isPresented: $isShowingMessageComposer) {
            MessageComposeView(
                recipients: [messageRecipient],
                body: messageBody,
                isShowing: $isShowingMessageComposer,
                completion: { _ in }
            )
        }
        .sheet(isPresented: $showingEditNameSheet) {
            NavigationView {
                Form {
                    TextField("Your Name", text: $editedName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .navigationTitle("Edit Your Name")
                .navigationBarItems(
                    leading: Button("Cancel") { showingEditNameSheet = false },
                    trailing: Button("Save") {
                        if let user = selectedUser, !editedName.isEmpty {
                            let updatedUser = User(
                                id: user.id,
                                name: editedName,
                                isAdmin: user.isAdmin,
                                remindersEnabled: user.remindersEnabled,
                                reminderTimes: user.reminderTimes,
                                treatmentFoodTimerEnabled: user.treatmentFoodTimerEnabled,
                                treatmentTimerDuration: user.treatmentTimerDuration
                            )
                            appData.addUser(updatedUser)
                            if appData.currentUser?.id == user.id {
                                appData.currentUser = updatedUser
                            }
                            loadData() // Refresh the user list
                        }
                        showingEditNameSheet = false
                    }
                    .disabled(editedName.isEmpty)
                )
            }
        }
    }
    
    // Check if this user is the last admin in the room
    private func isLastAdmin(_ user: User) -> Bool {
        return user.isAdmin && users.filter { $0.isAdmin }.count <= 1
    }
    
    // Sign out function
    func signOut() {
        // Clear user data
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentRoomId")
        appData.currentUser = nil
        appData.currentRoomId = nil
        
        // Notify ContentView to show login screen
        NotificationCenter.default.post(name: Notification.Name("UserDidSignOut"), object: nil)
        
        // Dismiss current view
        presentationMode.wrappedValue.dismiss()
    }
    
    func loadData() {
        guard let currentRoomId = UserDefaults.standard.string(forKey: "currentRoomId") else { return }
        
        isLoading = true
        users = []
        pendingInvitations = [:]
        
        print("Loading users for room: \(currentRoomId)")
        
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        // Load all users with access to this room
        dbRef.child("users").observeSingleEvent(of: .value) { snapshot in
            print("User snapshot received: \(snapshot.childrenCount) users found")
            
            guard let usersData = snapshot.value as? [String: [String: Any]] else {
                print("Failed to parse users data")
                isLoading = false
                return
            }
            
            for (userId, userData) in usersData {
                print("Processing user: \(userId), name: \(userData["name"] as? String ?? "unknown")")
                
                if let roomAccess = userData["roomAccess"] as? [String: Bool],
                   roomAccess[currentRoomId] == true {
                    
                    // Check if this is the current user
                    if let currentUser = appData.currentUser,
                       currentUser.id.uuidString == userId &&
                       (userData["name"] as? String) != currentUser.name {
                        
                        // Sync Firebase with the current user name
                        print("Syncing user name from \(userData["name"] as? String ?? "unknown") to \(currentUser.name)")
                        
                        var updatedUserData = userData
                        updatedUserData["name"] = currentUser.name
                        
                        // Update Firebase with correct name
                        dbRef.child("users").child(userId).child("name").setValue(currentUser.name)
                        
                        // Create user with correct name
                        if var userData = userData as? [String: Any] {
                            userData["name"] = currentUser.name
                            userData["id"] = userId
                            if let user = User(dictionary: userData) {
                                users.append(user)
                                print("Added user (synchronized): \(user.name)")
                            }
                        }
                    } else if let user = User(dictionary: userData) {
                        users.append(user)
                        print("Added user: \(user.name), isAdmin: \(user.isAdmin)")
                    }
                }
            }
            
            // Now load pending invitations for this room
            dbRef.child("invitations").observeSingleEvent(of: .value) { snapshot in
                guard let invitationsData = snapshot.value as? [String: [String: Any]] else {
                    isLoading = false
                    return
                }
                
                for (code, invitationData) in invitationsData {
                    if let roomId = invitationData["roomId"] as? String,
                       roomId == currentRoomId,
                       let status = invitationData["status"] as? String,
                       status != "accepted" {
                        pendingInvitations[code] = invitationData
                    }
                }
                
                isLoading = false
            }
        }
    }
    
    func toggleAdminStatus(_ user: User) {
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        let updatedAdmin = !user.isAdmin
        
        // Don't allow removing last admin
        if user.isAdmin && isLastAdmin(user) {
            return
        }
        
        // Update the admin status in Firebase
        dbRef.child("users").child(user.id.uuidString).child("isAdmin").setValue(updatedAdmin) { error, _ in
            if error == nil {
                if let index = users.firstIndex(where: { $0.id == user.id }) {
                    // Create a new User with the updated isAdmin status
                    let updatedUser = User(
                        id: user.id,
                        name: user.name,
                        isAdmin: updatedAdmin,
                        remindersEnabled: user.remindersEnabled,
                        reminderTimes: user.reminderTimes,
                        treatmentFoodTimerEnabled: user.treatmentFoodTimerEnabled,
                        treatmentTimerDuration: user.treatmentTimerDuration
                    )
                    users[index] = updatedUser
                    
                    // Update currentUser if needed
                    if appData.currentUser?.id == user.id {
                        appData.currentUser = updatedUser
                    }
                }
            }
        }
    }
    
    func removeUser(_ user: User) {
        guard let currentRoomId = UserDefaults.standard.string(forKey: "currentRoomId") else { return }
        
        // Don't allow removing the last admin
        if user.isAdmin && isLastAdmin(user) {
            return
        }
        
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        // Remove room access for this user
        dbRef.child("users").child(user.id.uuidString).child("roomAccess").child(currentRoomId).removeValue { error, _ in
            if error == nil {
                if let index = users.firstIndex(where: { $0.id == user.id }) {
                    users.remove(at: index)
                }
            }
        }
    }
    
    func deleteInvitation(_ code: String) {
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        dbRef.child("invitations").child(code).removeValue { error, _ in
            if error == nil {
                pendingInvitations.removeValue(forKey: code)
            }
        }
    }
    
    func resendInvitation(_ code: String, invitation: [String: Any]) {
        if let phoneNumber = invitation["phoneNumber"] as? String {
            // Update invitation status
            let dbRef = Database.database().reference()
            dbRef.child("invitations").child(code).child("status").setValue("sent")
            
            // Update local state
            if var updatedInvitation = pendingInvitations[code] {
                updatedInvitation["status"] = "sent"
                pendingInvitations[code] = updatedInvitation
            }
            
            // Show message composer with pre-populated text
            let appStoreLink = "https://testflight.apple.com/join/W93z4G4W" // Replace with your actual link
            let messageText = "You've been invited to use the TIPs App! Download here: \(appStoreLink) and use invitation code: \(code)"
            
            messageRecipient = phoneNumber
            messageBody = messageText
            isShowingMessageComposer = true
        }
    }
}
