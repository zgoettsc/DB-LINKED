import SwiftUI
import FirebaseAuth
import FirebaseDatabase

struct InitialSetupView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var isInitialSetupActive: Bool
    @State private var step = 0
    @State private var isLogOnly = false
    @State private var cycleNumber: Int
    @State private var startDate: Date
    @State private var foodChallengeDate: Date
    @State private var patientName: String
    @State private var roomCodeInput = ""
    @State private var showingRoomCodeError = false
    @State private var userName: String = ""
    @State private var newCycleId: UUID?
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var debugMessage = ""

    init(appData: AppData, isInitialSetupActive: Binding<Bool>) {
        self.appData = appData
        self._isInitialSetupActive = isInitialSetupActive
        let lastCycle = appData.cycles.last
        self._cycleNumber = State(initialValue: (lastCycle?.number ?? 0) + 1)
        self._startDate = State(initialValue: lastCycle?.foodChallengeDate.addingTimeInterval(3 * 24 * 3600) ?? Date())
        self._foodChallengeDate = State(initialValue: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: lastCycle?.foodChallengeDate.addingTimeInterval(3 * 24 * 3600) ?? Date())!)
        self._patientName = State(initialValue: lastCycle?.patientName ?? "")
    }

    var body: some View {
        NavigationView {
            VStack {
                if step == 0 {
                    ZStack {
                        Color(red: 242/255, green: 247/255, blue: 255/255).ignoresSafeArea()
                        VStack(spacing: 24) {
                            VStack(spacing: 8) {
                                Text("Welcome to")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                                Text("Tolerance Tracker")
                                    .font(.largeTitle.bold())
                                    .foregroundColor(.blue)
                            }

                            VStack(spacing: 16) {
                                Button(action: {
                                    isLogOnly = false
                                    step = 1
                                }) {
                                    Text("Setup New Program")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                }

                                Button(action: {
                                    isLogOnly = true
                                    step = 1
                                }) {
                                    Text("Join Existing Program")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue, lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.top, 20)
                        }
                        .padding(.horizontal, 30)
                    }
                }

                else if step == 1 && isLogOnly {
                    ZStack {
                        Color(red: 242/255, green: 247/255, blue: 255/255).ignoresSafeArea()
                        
                        VStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Join Existing Program")
                                    .font(.title.bold())
                                    .foregroundColor(.blue)
                                
                                TextField("Your Name", text: $userName)
                                    .foregroundColor(.black)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
                                
                                TextField("Invitation Code", text: $roomCodeInput)
                                    .foregroundColor(.black)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
                                
                                if showingRoomCodeError {
                                    Text(debugMessage)
                                        .foregroundColor(.red)
                                        .font(.subheadline)
                                        .padding(.top, 4)
                                }
                                
                                Button(action: {
                                    if !roomCodeInput.isEmpty && !userName.isEmpty {
                                        let dbRef = Database.database().reference()
                                        dbRef.child("invitations").child(roomCodeInput).observeSingleEvent(of: .value) { snapshot in
                                            if let invitation = snapshot.value as? [String: Any],
                                               let status = invitation["status"] as? String,
                                               (status == "created" || status == "sent"),
                                               let roomId = invitation["roomId"] as? String,
                                               let expiryDateString = invitation["expiryDate"] as? String,
                                               let expiryDate = ISO8601DateFormatter().date(from: expiryDateString),
                                               expiryDate > Date() {
                                                
                                                dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value) { roomSnapshot in
                                                    guard roomSnapshot.exists() else {
                                                        self.showingRoomCodeError = true
                                                        self.debugMessage = "The room associated with this invitation no longer exists."
                                                        return
                                                    }
                                                    
                                                    let userId = UUID()
                                                    let newUser = User(
                                                        id: userId,
                                                        name: self.userName,
                                                        isAdmin: invitation["isAdmin"] as? Bool ?? false
                                                    )
                                                    
                                                    dbRef.child("users").child(userId.uuidString).setValue(newUser.toDictionary()) { error, _ in
                                                        if let error = error {
                                                            self.showingRoomCodeError = true
                                                            self.debugMessage = "Error creating user account: \(error.localizedDescription)"
                                                            return
                                                        }
                                                        
                                                        dbRef.child("users").child(userId.uuidString).child("roomAccess").child(roomId).setValue(true) { error, _ in
                                                            if let error = error {
                                                                self.showingRoomCodeError = true
                                                                self.debugMessage = "Error granting room access: \(error.localizedDescription)"
                                                                return
                                                            }
                                                            
                                                            dbRef.child("invitations").child(self.roomCodeInput).updateChildValues([
                                                                "status": "accepted",
                                                                "acceptedBy": userId.uuidString
                                                            ]) { error, _ in }
                                                            
                                                            self.appData.currentUser = newUser
                                                            UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
                                                            self.appData.roomCode = nil
                                                            UserDefaults.standard.removeObject(forKey: "roomCode")
                                                            self.appData.currentRoomId = roomId
                                                            UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                                                            self.step = 2
                                                        }
                                                    }
                                                }
                                            } else {
                                                self.showingRoomCodeError = true
                                                self.debugMessage = "Invalid, expired, or already used invitation code."
                                            }
                                        } withCancel: { error in
                                            self.showingRoomCodeError = true
                                            self.debugMessage = "Error connecting to the server: \(error.localizedDescription)"
                                        }
                                    } else {
                                        self.showingRoomCodeError = true
                                        self.debugMessage = "Please enter both a name and an invitation code."
                                    }
                                }) {
                                    Text("Join Program")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                }
                                
                                Button(action: {
                                    step = 0
                                }) {
                                    Text("Back")
                                        .font(.body)
                                        .foregroundColor(.blue)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }
                }

                else if step == 1 && !isLogOnly {
                    Form {
                        Section(header: Text("Participant Image")) {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        showingImagePicker = true
                                    }
                            } else {
                                Button("Add Participant Image") {
                                    showingImagePicker = true
                                }
                            }
                        }
                        Section(header: Text("Cycle Information")) {
                            TextField("Participant Name", text: $patientName)
                            DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
                            DatePicker("Food Challenge Date", selection: $foodChallengeDate, displayedComponents: [.date])
                        }
                        Section(header: Text("Your Name")) {
                            TextField("Your Name", text: $userName)
                        }
                    }
                }

                else if step == 2 && isLogOnly {
                    RemindersView(appData: appData)
                }
                else if step == 2 && !isLogOnly {
                    EditItemsView(appData: appData, cycleId: newCycleId ?? UUID())
                }
                else if step == 3 && isLogOnly {
                    TreatmentFoodTimerView(appData: appData)
                }
                else if step == 3 && !isLogOnly {
                    EditGroupedItemsView(
                        appData: appData,
                        cycleId: newCycleId ?? UUID(),
                        step: Binding<Int?>(
                            get: { step },
                            set: { newValue in if let value = newValue { step = value } }
                        )
                    )
                }
                else if step == 4 && !isLogOnly {
                    RemindersView(appData: appData)
                }
                else if step == 5 && !isLogOnly {
                    TreatmentFoodTimerView(appData: appData)
                }
            }
            .navigationTitle(getNavigationTitle())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step > 1 && step != 3 {
                        Button("Previous") {
                            step -= 1
                        }
                    }
                    else if step == 1 {
                        Button("Back") {
                            step = 0
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if step == 0 || (step == 3 && !isLogOnly) {
                        EmptyView()
                    } else {
                        Button(getNextButtonTitle()) {
                            if isLogOnly && step == 1 {
                                if !roomCodeInput.isEmpty && !userName.isEmpty {
                                    debugMessage = "Setting room code to: \(roomCodeInput)"
                                    appData.roomCode = roomCodeInput
                                    let newUser = User(id: UUID(), name: userName, isAdmin: false)
                                    appData.addUser(newUser)
                                    appData.currentUser = newUser
                                    UserDefaults.standard.set(newUser.id.uuidString, forKey: "currentUserId")
                                    debugMessage += "\nCreated user: \(newUser.name) with ID: \(newUser.id)"
                                    step = 2
                                } else {
                                    showingRoomCodeError = true
                                }
                            } else if !isLogOnly && step == 1 {
                                if !userName.isEmpty {
                                    debugMessage = "Creating new setup with name: \(userName)"
                                    
                                    // Generate a new room ID
                                    let roomId = UUID().uuidString
                                    
                                    // Create user
                                    let userId = UUID()
                                    let newUser = User(
                                        id: userId,
                                        name: userName,
                                        isAdmin: true
                                    )
                                    
                                    // Get database reference
                                    let dbRef = Database.database().reference()
                                    
                                    // Create the effective patient name
                                    let effectivePatientName = patientName.isEmpty ? "Unnamed" : patientName
                                    
                                    // Create room data
                                    let roomData = [
                                        "name": "\(effectivePatientName)'s Program",
                                        "createdBy": userId.uuidString,
                                        "createdAt": ISO8601DateFormatter().string(from: Date())
                                    ]
                                    
                                    // Create cycle
                                    let newCycleId = UUID()
                                    self.newCycleId = newCycleId
                                    
                                    let newCycle = Cycle(
                                        id: newCycleId,
                                        number: cycleNumber,
                                        patientName: effectivePatientName,
                                        startDate: startDate,
                                        foodChallengeDate: foodChallengeDate
                                    )
                                    
                                    // Create cycle data dictionary
                                    let cycleData = newCycle.toDictionary()
                                    
                                    // Set up the complete structure with all necessary nodes
                                    // First set up user and room
                                    dbRef.child("users").child(userId.uuidString).setValue(newUser.toDictionary())
                                    dbRef.child("rooms").child(roomId).setValue(roomData)
                                    dbRef.child("users").child(userId.uuidString).child("roomAccess").child(roomId).setValue(true)
                                    
                                    // Explicitly create cycles node with the cycle data
                                    dbRef.child("rooms").child(roomId).child("cycles").child(newCycleId.uuidString).setValue(cycleData)
                                    
                                    // Create items node within the cycle
                                    dbRef.child("rooms").child(roomId).child("cycles").child(newCycleId.uuidString).child("items").setValue([:])
                                    
                                    // Create grouped items node within the cycle
                                    dbRef.child("rooms").child(roomId).child("cycles").child(newCycleId.uuidString).child("groupedItems").setValue([:])
                                    
                                    // Ensure invitations node exists
                                    dbRef.child("invitations").setValue([:])
                                    
                                    // Set current user and room in memory
                                    appData.currentUser = newUser
                                    appData.currentRoomId = roomId
                                    
                                    // Update UserDefaults
                                    UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
                                    UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                                    
                                    // Save profile image if provided
                                    if let profileImage = profileImage {
                                        appData.saveProfileImage(profileImage, forCycleId: newCycleId)
                                    }
                                    
                                    // Important: Make sure the cycle is properly loaded into appData
                                    appData.cycles = [newCycle]
                                    appData.cycleItems[newCycleId] = []
                                    appData.groupedItems[newCycleId] = []
                                    
                                    print("Setup complete: Created room \(roomId) with cycle \(newCycleId)")
                                    
                                    // Now we can proceed to step 2
                                    step = 2
                                }
                            } else if (isLogOnly && step == 3) || (!isLogOnly && step == 5) {
                                debugMessage = "Setup completed"
                                UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
                                NotificationCenter.default.post(name: Notification.Name("SetupCompleted"), object: nil)
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isInitialSetupActive = false
                                }
                            } else {
                                step += 1
                            }
                        }
                        .disabled(isNextDisabled())
                    }
                }
            }
            .onAppear {
                ensureUserInitialized()
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $profileImage)
            }
            .alert("Error", isPresented: $showingRoomCodeError) {
                Button("OK") { }
            } message: {
                Text("Please enter both a name and a room code")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func getNavigationTitle() -> String {
        switch step {
        case 0: return ""
        case 1: return isLogOnly ? "Join Program" : "Setup Cycle"
        case 2: return isLogOnly ? "Dose Reminders" : "Edit Items"
        case 3: return isLogOnly ? "Treatment Food Timer" : "Edit Grouped Items"
        case 4: return "Dose Reminders"
        case 5: return "Treatment Timer"
        default: return "Setup"
        }
    }

    private func getNextButtonTitle() -> String {
        if (isLogOnly && step == 3) || (!isLogOnly && step == 5) {
            return "Finish"
        }
        return "Next"
    }

    private func isNextDisabled() -> Bool {
        if step == 1 && isLogOnly {
            return roomCodeInput.isEmpty || userName.isEmpty
        } else if step == 1 && !isLogOnly {
            return userName.isEmpty
        }
        return false
    }

    private func ensureUserInitialized() {
        // If we already have an authenticated user from Firebase, use that display name
        if let authUser = authViewModel.currentUser, userName.isEmpty {
            userName = authUser.displayName ?? ""
        }
        
        if appData.currentUser == nil && !userName.isEmpty {
            let newUser: User
            
            // Create a new user
            if let authUser = authViewModel.currentUser {
                // If we have Firebase Auth, link the user to it
                newUser = createFirebaseLinkedUser(authUser: authUser, isAdmin: !isLogOnly)
            } else {
                // Fallback to legacy user creation
                newUser = User(id: UUID(), name: userName, isAdmin: !isLogOnly)
                appData.addUser(newUser)
                appData.currentUser = newUser
                UserDefaults.standard.set(newUser.id.uuidString, forKey: "currentUserId")
            }
            
            print("Initialized user in InitialSetupView: \(newUser.id) with name: \(userName)")
            debugMessage += "\nInitialized user: \(userName)"
        } else if let currentUser = appData.currentUser, currentUser.name != userName && !userName.isEmpty {
            let updatedUser = User(
                id: currentUser.id,
                name: userName,
                isAdmin: currentUser.isAdmin,
                remindersEnabled: currentUser.remindersEnabled,
                reminderTimes: currentUser.reminderTimes,
                treatmentFoodTimerEnabled: currentUser.treatmentFoodTimerEnabled,
                treatmentTimerDuration: currentUser.treatmentTimerDuration
            )
            appData.addUser(updatedUser)
            appData.currentUser = updatedUser
            print("Updated user name from \(currentUser.name) to \(userName)")
            debugMessage += "\nUpdated user name to: \(userName)"
        }
    }
    
    private func createFirebaseLinkedUser(authUser: AuthUser, isAdmin: Bool) -> User {
        let userId = UUID()
        let newUser = User(
            id: userId,
            name: userName,
            isAdmin: isAdmin
        )
        
        appData.addUser(newUser)
        appData.currentUser = newUser
        UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
        
        // Link user to Firebase Auth
        if let dbRef = appData.valueForDBRef() {
            dbRef.child("auth_mapping").child(authUser.uid).setValue(userId.uuidString)
            dbRef.child("users").child(userId.uuidString).child("authId").setValue(authUser.uid)
        }
        
        return newUser
    }
}

struct InitialSetupView_Previews: PreviewProvider {
    static var previews: some View {
        InitialSetupView(appData: AppData(), isInitialSetupActive: .constant(true))
            .environmentObject(AuthViewModel())
    }
}
