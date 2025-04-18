import SwiftUI
import FirebaseDatabase

struct NewCycleSetupView: View {
    @ObservedObject var appData: AppData
    @Environment(\.dismiss) var dismiss
    @Binding var isNewCycleSetupActive: Bool
    @State private var step = 1
    @State private var cycleNumber: Int
    @State private var startDate: Date
    @State private var foodChallengeDate: Date
    @State private var patientName: String
    @State private var userName: String
    @State private var newCycleId: UUID?
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var refreshTrigger = UUID() // Force UI refresh
    
    init(appData: AppData, isNewCycleSetupActive: Binding<Bool>) {
        self.appData = appData
        self._isNewCycleSetupActive = isNewCycleSetupActive
        
        // Initialize cycle-related fields
        if let lastCycle = appData.cycles.last {
            print("Initializing with last cycle ID: \(lastCycle.id), patientName: \(lastCycle.patientName)")
            self._cycleNumber = State(initialValue: lastCycle.number + 1)
            self._startDate = State(initialValue: lastCycle.foodChallengeDate.addingTimeInterval(3 * 24 * 3600))
            self._foodChallengeDate = State(initialValue: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: lastCycle.foodChallengeDate.addingTimeInterval(3 * 24 * 3600))!)
            self._patientName = State(initialValue: lastCycle.patientName)
            // Load profile image
            let loadedImage = appData.loadProfileImage(forCycleId: lastCycle.id)
            self._profileImage = State(initialValue: loadedImage)
            print("Profile image for cycle \(lastCycle.id): \(loadedImage != nil ? "Loaded" : "Not found")")
        } else {
            print("No previous cycle found, using defaults")
            self._cycleNumber = State(initialValue: 1)
            self._startDate = State(initialValue: Date())
            self._foodChallengeDate = State(initialValue: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date())!)
            self._patientName = State(initialValue: "")
            self._profileImage = State(initialValue: nil)
        }
        
        // Initialize user name
        let currentUserName = appData.currentUser?.name ?? ""
        self._userName = State(initialValue: currentUserName)
        print("Initializing userName with: '\(currentUserName)', currentUser: \(appData.currentUser != nil ? "Present" : "Nil")")
    }
    
    var body: some View {
        VStack {
            if step == 1 {
                Form {
                    Section(header: Text("Participant Picture")) {
                        HStack {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                                    .onAppear {
                                        print("Profile image displayed for cycle")
                                    }
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.secondary)
                                    .onAppear {
                                        print("Placeholder image displayed")
                                    }
                            }
                            
                            Button("Select Photo") {
                                showingImagePicker = true
                            }
                            .padding(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical)
                    }
                    
                    TextField("Your Name", text: $userName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onAppear {
                            print("UserName TextField displayed with value: '\(userName)'")
                        }
                    TextField("Participant Name", text: $patientName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onAppear {
                            print("Participant TextField displayed with value: '\(patientName)'")
                        }
                    Picker("Cycle Number", selection: $cycleNumber) {
                        ForEach(1...25, id: \.self) { number in
                            Text("\(number)").tag(number)
                        }
                    }
                    DatePicker("Cycle Dosing Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Food Challenge Date", selection: $foodChallengeDate, displayedComponents: .date)
                }
            } else if step == 2 {
                EditItemsView(appData: appData, cycleId: newCycleId ?? UUID())
            } else if step == 3 {
                EditGroupedItemsView(
                    appData: appData,
                    cycleId: newCycleId ?? UUID(),
                    step: Binding<Int?>(
                        get: { step },
                        set: { newValue in if let value = newValue { step = value } }
                    )
                )
            } else if step == 4 {
                RemindersView(appData: appData)
            } else if step == 5 {
                TreatmentFoodTimerView(appData: appData)
            }
        }
        .id(refreshTrigger) // Force view refresh
        .navigationTitle(getNavigationTitle())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if step != 3 { // Skip for EditGroupedItemsView
                    Button(action: {
                        if step > 1 {
                            print("Previous button tapped, step: \(step)")
                            step -= 1
                        } else {
                            print("Cancel button tapped, step: \(step)")
                            isNewCycleSetupActive = false
                            dismiss()
                        }
                    }) {
                        Text(step > 1 ? "Previous" : "Cancel")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if step != 3 { // Skip for EditGroupedItemsView
                    Button(action: {
                        print("Next/Finish button tapped, step: \(step)")
                        if step == 1 {
                            let effectivePatientName = patientName.isEmpty ? "Unnamed" : patientName
                            let newCycle = Cycle(
                                id: UUID(),
                                number: cycleNumber,
                                patientName: effectivePatientName,
                                startDate: startDate,
                                foodChallengeDate: foodChallengeDate
                            )
                            newCycleId = newCycle.id
                            let previousCycleId = appData.cycles.last?.id
                            
                            // Create new cycle with items but NO grouped items
                            createCycleWithoutGroups(newCycle, copyItemsFromCycleId: previousCycleId)
                            
                            if let profileImage = profileImage, let cycleId = newCycleId {
                                print("Saving profile image for new cycle ID: \(cycleId)")
                                appData.saveProfileImage(profileImage, forCycleId: cycleId)
                            }
                            
                            ensureUserInitialized()
                            
                            step = 2
                        } else if step == 5 {
                            print("Completing setup, dismissing NewCycleSetupView")
                            isNewCycleSetupActive = false
                            UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
                            NotificationCenter.default.post(name: Notification.Name("SetupCompleted"), object: nil)
                            dismiss()
                        } else {
                            step += 1
                        }
                    }) {
                        Text(getNextButtonTitle())
                    }
                }
            }
        }
        .onAppear {
            print("NewCycleSetupView appeared, step: \(step), userName: '\(userName)', patientName: '\(patientName)', hasProfileImage: \(profileImage != nil)")
            // Trigger refresh to ensure UI updates
            refreshTrigger = UUID()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $profileImage)
        }
    }
    
    // Custom method to create a new cycle without copying grouped items
    private func createCycleWithoutGroups(_ cycle: Cycle, copyItemsFromCycleId: UUID? = nil) {
        // First, call the regular addCycle method to handle items
        appData.addCycle(cycle, copyItemsFromCycleId: copyItemsFromCycleId)
        
        // Explicitly clear grouped items directly in the appData
        appData.groupedItems[cycle.id] = []
        
        // Then directly update Firebase using Database Reference to ensure no grouped items
        if let roomId = UserDefaults.standard.string(forKey: "currentRoomId") {
            let dbRef = Database.database().reference()
            
            // Use a transaction to ensure the groupedItems field is empty
            dbRef.child("rooms").child(roomId).child("cycles").child(cycle.id.uuidString).child("groupedItems").setValue([:])
            
            // Also clear the groupedItems in memory again to be double sure
            appData.groupedItems[cycle.id] = []
            
            // Clear consumption log for this cycle
            appData.consumptionLog[cycle.id] = [:]
            dbRef.child("rooms").child(roomId).child("consumptionLog").child(cycle.id.uuidString).setValue([:])
            
            print("### Direct Firebase update: Cleared grouped items for cycle \(cycle.id)")
        }
        
        // Force refresh to ensure UI updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Double check that grouped items are still empty
            self.appData.groupedItems[cycle.id] = []
            self.refreshTrigger = UUID()
        }
    }
    
    private func getNavigationTitle() -> String {
        switch step {
        case 1: return "Setup New Cycle"
        case 2: return "Edit Items"
        case 3: return "Edit Grouped Items"
        case 4: return "Dose Reminders"
        case 5: return "Treatment Food Timer"
        default: return "Setup"
        }
    }
    
    private func getNextButtonTitle() -> String {
        step == 5 ? "Finish" : "Next"
    }
    
    private func ensureUserInitialized() {
        if appData.currentUser == nil && !userName.isEmpty {
            print("Creating new user with name: \(userName)")
            let newUser = User(
                id: UUID(),
                name: userName,
                isAdmin: true
            )
            appData.addUser(newUser)
            appData.currentUser = newUser
            UserDefaults.standard.set(newUser.id.uuidString, forKey: "currentUserId")
            print("Initialized user in NewCycleSetupView: \(newUser.id)")
        } else if let currentUser = appData.currentUser, !userName.isEmpty, userName != currentUser.name {
            print("Updating existing user name from: \(currentUser.name) to: \(userName)")
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
        } else {
            print("No user update needed, currentUser: \(appData.currentUser?.name ?? "nil"), userName: \(userName)")
        }
    }
}

struct NewCycleSetupView_Previews: PreviewProvider {
    static var previews: some View {
        NewCycleSetupView(appData: AppData(), isNewCycleSetupActive: .constant(true))
    }
}
