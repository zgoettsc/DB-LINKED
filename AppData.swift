import Foundation
import SwiftUI
import FirebaseDatabase

class AppData: ObservableObject {
    @Published var cycles: [Cycle] = []
    @Published var cycleItems: [UUID: [Item]] = [:]
    @Published var groupedItems: [UUID: [GroupedItem]] = [:]
    @Published var units: [Unit] = []
    @Published var consumptionLog: [UUID: [UUID: [LogEntry]]] = [:]
    @Published var lastResetDate: Date?
    @Published var users: [User] = []
    @Published var currentUser: User? {
        didSet { saveCurrentUserSettings() }
    }
    @Published var treatmentTimer: TreatmentTimer? {
        didSet {
            saveTimerState()
        }
    }
    // Keep this property if it's already there, otherwise add it
    private var lastSaveTime: Date?
    @Published var categoryCollapsed: [String: Bool] = [:]
    @Published var groupCollapsed: [UUID: Bool] = [:] // Keyed by group ID
    @Published var roomCode: String? {
        didSet {
            if let roomCode = roomCode {
                UserDefaults.standard.set(roomCode, forKey: "roomCode")
                // Log warning for legacy use
                print("WARNING: Using deprecated roomCode property with value: \(roomCode)")
                logToFile("WARNING: Using deprecated roomCode property with value: \(roomCode)")
                // Do NOT create a new room or set dbRef
                // Instead, treat this as an attempt to join an existing room
                // Assume roomCode might be a legacy invitation code
                let dbRef = Database.database().reference()
                dbRef.child("invitations").child(roomCode).observeSingleEvent(of: .value) { snapshot in
                    if let invitation = snapshot.value as? [String: Any],
                       let roomId = invitation["roomId"] as? String {
                        print("Found invitation with roomId: \(roomId) for legacy roomCode: \(roomCode)")
                        // Set currentRoomId instead
                        self.currentRoomId = roomId
                    } else {
                        print("No valid invitation found for roomCode: \(roomCode)")
                        self.syncError = "Invalid or expired invitation code."
                        self.isLoading = false
                    }
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "roomCode")
                // Do not clear dbRef here; let currentRoomId handle it
            }
        }
    }
    @Published var syncError: String?
    @Published var isLoading: Bool = true
    @Published var currentRoomId: String? {
        didSet {
            if let roomId = currentRoomId {
                print("Setting currentRoomId to: \(roomId)")
                UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                
                // IMPORTANT: Clear roomCode to avoid confusion
                self.roomCode = nil
                UserDefaults.standard.removeObject(forKey: "roomCode")
                
                loadRoomData(roomId: roomId)
            } else {
                print("Clearing currentRoomId")
                UserDefaults.standard.removeObject(forKey: "currentRoomId")
            }
        }
    }
    
    // Add this method to the AppData class
    func clearGroupedItems(forCycleId cycleId: UUID) {
        // Clear in memory
        groupedItems[cycleId] = []
        
        // Clear in Firebase
        if let dbRef = dbRef {
            dbRef.child("cycles").child(cycleId.uuidString).child("groupedItems").setValue([:])
            print("Cleared grouped items for cycle \(cycleId) in Firebase")
        } else {
            print("No database reference available, only cleared grouped items in memory")
        }
    }
    
    // Add to AppData class
    func createUserFromAuth(authUser: AuthUser, isAdmin: Bool = false) -> User {
        let userId = UUID()
        let user = User(
            id: userId,
            name: authUser.displayName ?? "User",
            isAdmin: isAdmin,
            remindersEnabled: [:],
            reminderTimes: [:],
            treatmentFoodTimerEnabled: false,
            treatmentTimerDuration: 900
        )
        
        addUser(user)
        currentUser = user
        UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
        return user
    }


    func linkUserToFirebaseAuth(user: User, authId: String) {
        guard let dbRef = dbRef else { return }
        
        // Create a mapping between Firebase Auth UID and our app's UUID
        dbRef.child("auth_mapping").child(authId).setValue(user.id.uuidString)
        
        // Add Firebase Auth ID to user record
        dbRef.child("users").child(user.id.uuidString).child("authId").setValue(authId)
    }

    func getUserByAuthId(authId: String, completion: @escaping (User?) -> Void) {
        guard let dbRef = dbRef else {
            completion(nil)
            return
        }
        
        // Look up the user UUID from auth mapping
        dbRef.child("auth_mapping").child(authId).observeSingleEvent(of: .value) { snapshot in
            guard let userIdString = snapshot.value as? String,
                  let userId = UUID(uuidString: userIdString) else {
                completion(nil)
                return
            }
            
            // Get the user data
            dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot in
                guard let userData = userSnapshot.value as? [String: Any],
                      let user = User(dictionary: userData) else {
                    completion(nil)
                    return
                }
                
                DispatchQueue.main.async {
                    self.currentUser = user
                    UserDefaults.standard.set(userIdString, forKey: "currentUserId")
                    completion(user)
                }
            }
        }
    }
    
    // Function to start a new treatment timer
    func startTreatmentTimer(duration: TimeInterval = 900) {
        guard currentUser?.treatmentFoodTimerEnabled ?? false else { return }
        
        // Cancel any existing timer
        stopTreatmentTimer()
        
        // Create a new timer
        let endTime = Date().addingTimeInterval(duration)
        let timerId = UUID().uuidString
        
        // Get unlogged treatment items
        let unloggedItems = getUnloggedTreatmentItems()
        
        // Schedule notifications
        let notificationIds = scheduleNotifications(timerId: timerId, endTime: endTime, duration: duration)
        
        // Create and save the timer
        let newTimer = TreatmentTimer(
            id: timerId,
            isActive: true,
            endTime: endTime,
            associatedItemIds: unloggedItems.map { $0.id },
            notificationIds: notificationIds
        )
        
        self.treatmentTimer = newTimer
    }

    // Get unlogged treatment items
    private func getUnloggedTreatmentItems() -> [Item] {
        guard let cycleId = currentCycleId() else { return [] }
        
        let treatmentItems = (cycleItems[cycleId] ?? []).filter { $0.category == .treatment }
        let today = Calendar.current.startOfDay(for: Date())
        
        return treatmentItems.filter { item in
            let logs = consumptionLog[cycleId]?[item.id] ?? []
            return !logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
    }

    // Function to stop the treatment timer
    func stopTreatmentTimer() {
        // Cancel notifications
        if let timer = treatmentTimer, let notificationIds = timer.notificationIds {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIds)
        }
        
        // Set to nil to trigger didSet and save
        treatmentTimer = nil
    }

    // Function to snooze the treatment timer
    func snoozeTreatmentTimer(duration: TimeInterval = 300) {
        guard let currentTimer = treatmentTimer else { return }
        
        // Cancel existing notifications
        if let notificationIds = currentTimer.notificationIds {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIds)
        }
        
        // Create new end time
        let endTime = Date().addingTimeInterval(duration)
        
        // Schedule new notifications
        let notificationIds = scheduleNotifications(timerId: currentTimer.id, endTime: endTime, duration: duration)
        
        // Create and save new timer
        let newTimer = TreatmentTimer(
            id: currentTimer.id,
            isActive: true,
            endTime: endTime,
            associatedItemIds: currentTimer.associatedItemIds,
            notificationIds: notificationIds
        )
        
        self.treatmentTimer = newTimer
    }

    // Schedule multiple notifications and return their IDs
    private func scheduleNotifications(timerId: String, endTime: Date, duration: TimeInterval) -> [String] {
        let center = UNUserNotificationCenter.current()
        var notificationIds: [String] = []
        
        // Schedule 4 notifications 1 second apart to ensure notification is seen
        for i in 0..<4 {
            let content = UNMutableNotificationContent()
            content.title = "Time for the next treatment food"
            content.body = "Your treatment food timer has ended."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = "TREATMENT_TIMER"
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "treatment-timer-thread-\(timerId)"
            
            // Calculate delay - add small offset for each notification
            let delay = max(endTime.timeIntervalSinceNow, 0) + Double(i)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            
            // Create unique ID for each notification
            let notificationId = "\(timerId)_repeat_\(i)"
            notificationIds.append(notificationId)
            
            let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification \(i): \(error)")
                    self.logToFile("Error scheduling notification \(i): \(error)")
                }
            }
        }
        
        return notificationIds
    }

    // Check timer status and update UI
    func checkTimerStatus() -> TimeInterval? {
        guard let timer = treatmentTimer, timer.isActive else { return nil }
        
        let remainingTime = timer.endTime.timeIntervalSinceNow
        
        if remainingTime <= 0 {
            // Timer expired but wasn't properly cleared
            stopTreatmentTimer()
            return nil
        }
        
        return remainingTime
    }

    // Check if all treatment items are logged
    func checkIfAllTreatmentItemsLogged() {
        guard let timer = treatmentTimer, timer.isActive,
              let associatedItemIds = timer.associatedItemIds,
              !associatedItemIds.isEmpty,
              let cycleId = currentCycleId() else {
            return
        }
        
        // Get the items
        let allLogged = associatedItemIds.allSatisfy { itemId in
            let logs = consumptionLog[cycleId]?[itemId] ?? []
            let today = Calendar.current.startOfDay(for: Date())
            return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
        
        if allLogged {
            // All items have been logged, stop the timer
            stopTreatmentTimer()
        }
    }

    func loadRoomData(roomId: String) {
        let dbRef = Database.database().reference()
        
        print("Loading room data for roomId: \(roomId)")
        self.isLoading = true
        
        // Load room data
        dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value) { snapshot in
            guard snapshot.exists() else {
                print("ERROR: Room \(roomId) does not exist in Firebase")
                self.syncError = "Room \(roomId) not found"
                self.isLoading = false
                // Clear currentRoomId to prevent further attempts
                self.currentRoomId = nil
                UserDefaults.standard.removeObject(forKey: "currentRoomId")
                return
            }
            
            print("Room \(roomId) found in Firebase, updating references")
            
            // Update references to point to the right room in the database
            self.dbRef = Database.database().reference().child("rooms").child(roomId)
            
            // Now load from Firebase
            self.loadFromFirebase()
        } withCancel: { error in
            print("Error loading room \(roomId): \(error.localizedDescription)")
            self.syncError = "Failed to load room data: \(error.localizedDescription)"
            self.isLoading = false
            // Clear currentRoomId to prevent further attempts
            self.currentRoomId = nil
            UserDefaults.standard.removeObject(forKey: "currentRoomId")
        }
    }

    func setupNewDatabaseStructure() {
        let dbRef = Database.database().reference()
        
        // Create your own admin account first
        let adminId = UUID()
        let adminUser = User(
            id: adminId,
            name: "Admin", // Use a default name
            isAdmin: true
        )
        
        // Create a default room
        let roomId = UUID().uuidString
        let roomData = [
            "name": "Default Room",
            "createdBy": adminId.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Set up the structure
        dbRef.child("users").child(adminId.uuidString).setValue(adminUser.toDictionary())
        dbRef.child("rooms").child(roomId).setValue(roomData)
        dbRef.child("users").child(adminId.uuidString).child("roomAccess").child(roomId).setValue(true)
        
        // Create an empty cycles node
        dbRef.child("rooms").child(roomId).child("cycles").setValue([:])
        
        // Set up the invitations node
        dbRef.child("invitations").setValue([:])
        
        // Set current user and room
        self.currentUser = adminUser
        self.currentRoomId = roomId
        UserDefaults.standard.set(adminId.uuidString, forKey: "currentUserId")
        UserDefaults.standard.set(roomId, forKey: "currentRoomId")
        
        print("New database structure created for room \(roomId) with admin \(adminId)")
    }
    
    private var pendingConsumptionLogUpdates: [UUID: [UUID: [LogEntry]]] = [:] // Track pending updates
    
    private var dbRef: DatabaseReference?
    private var isAddingCycle = false
    public var treatmentTimerId: String? {
        didSet { saveTimerState() }
    }

    // Functions to handle profile images
    func saveProfileImage(_ image: UIImage, forCycleId cycleId: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        let fileName = "profile_\(cycleId.uuidString).jpg"
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName) {
            try? data.write(to: url)
            UserDefaults.standard.set(fileName, forKey: "profileImage_\(cycleId.uuidString)")
        }
    }
    
    func loadProfileImage(forCycleId cycleId: UUID) -> UIImage? {
        guard let fileName = UserDefaults.standard.string(forKey: "profileImage_\(cycleId.uuidString)") else {
            return nil
        }
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        
        return nil
    }
    
    func deleteProfileImage(forCycleId cycleId: UUID) {
        guard let fileName = UserDefaults.standard.string(forKey: "profileImage_\(cycleId.uuidString)") else {
            return
        }
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName) {
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.removeObject(forKey: "profileImage_\(cycleId.uuidString)")
        }
    }

    init() {
        print("AppData initializing")
        logToFile("AppData initializing")
        
        // First check if we have a user ID and room ID
        if let userIdStr = UserDefaults.standard.string(forKey: "currentUserId"),
           let userId = UUID(uuidString: userIdStr) {
            print("Found existing user ID: \(userIdStr)")
            loadCurrentUserSettings(userId: userId)
            
            // Prioritize currentRoomId over roomCode
            if let roomId = UserDefaults.standard.string(forKey: "currentRoomId") {
                print("Found existing room ID: \(roomId), loading room data")
                self.currentRoomId = roomId
                // Clear roomCode to avoid confusion
                UserDefaults.standard.removeObject(forKey: "roomCode")
            } else if let roomCode = UserDefaults.standard.string(forKey: "roomCode") {
                // Legacy support for old room code system
                print("Using legacy room code: \(roomCode)")
                self.roomCode = roomCode
            } else {
                print("No existing room found, will need setup")
            }
        } else {
            print("No existing user or room found, will need setup")
        }
        
        units = [Unit(name: "mg"), Unit(name: "g"), Unit(name: "tsp"), Unit(name: "tbsp"), Unit(name: "oz"), Unit(name: "mL"), Unit(name: "nuts"), Unit(name: "fist sized")]
        loadCachedData()
        
        // Ensure all groups start collapsed
        for (cycleId, groups) in groupedItems {
            for group in groups {
                if groupCollapsed[group.id] == nil {
                    groupCollapsed[group.id] = true
                }
            }
        }
        
        loadTimerState()
        checkAndResetIfNeeded()
        rescheduleDailyReminders()
        
        // Log timer state
        print("AppData init: Loaded treatmentTimer = \(String(describing: treatmentTimer))")
        logToFile("AppData init: Loaded treatmentTimer = \(String(describing: treatmentTimer))")
        
        if let timer = treatmentTimer {
            if timer.isActive && timer.endTime > Date() {
                print("AppData init: Active timer found, endDate = \(timer.endTime)")
                logToFile("AppData init: Active timer found, endDate = \(timer.endTime)")
            } else {
                print("AppData init: Timer expired, clearing treatmentTimer")
                logToFile("AppData init: Timer expired, clearing treatmentTimer")
                self.treatmentTimer = nil
            }
        } else {
            print("AppData init: No active timer to resume")
            logToFile("AppData init: No active timer to resume")
        }
    }
    
    func ensureCorrectRoomReference() {
        // If we have a currentRoomId, make sure dbRef points to the right place
        if let roomId = currentRoomId {
            print("Ensuring database reference points to room: \(roomId)")
            dbRef = Database.database().reference().child("rooms").child(roomId)
            
            // Clear roomCode to avoid confusion
            self.roomCode = nil
            UserDefaults.standard.removeObject(forKey: "roomCode")
        }
    }
    
    private func loadCachedData() {
        if let cycleData = UserDefaults.standard.data(forKey: "cachedCycles"),
           let decodedCycles = try? JSONDecoder().decode([Cycle].self, from: cycleData) {
            self.cycles = decodedCycles
        }
        if let itemsData = UserDefaults.standard.data(forKey: "cachedCycleItems"),
           let decodedItems = try? JSONDecoder().decode([UUID: [Item]].self, from: itemsData) {
            self.cycleItems = decodedItems
        }
        if let groupedItemsData = UserDefaults.standard.data(forKey: "cachedGroupedItems"),
           let decodedGroupedItems = try? JSONDecoder().decode([UUID: [GroupedItem]].self, from: groupedItemsData) {
            self.groupedItems = decodedGroupedItems
        }
        if let logData = UserDefaults.standard.data(forKey: "cachedConsumptionLog"),
           let decodedLog = try? JSONDecoder().decode([UUID: [UUID: [LogEntry]]].self, from: logData) {
            self.consumptionLog = decodedLog
        }
    }

    private func saveCachedData() {
        if let cycleData = try? JSONEncoder().encode(cycles) {
            UserDefaults.standard.set(cycleData, forKey: "cachedCycles")
        }
        if let itemsData = try? JSONEncoder().encode(cycleItems) {
            UserDefaults.standard.set(itemsData, forKey: "cachedCycleItems")
        }
        if let groupedItemsData = try? JSONEncoder().encode(groupedItems) {
            UserDefaults.standard.set(groupedItemsData, forKey: "cachedGroupedItems")
        }
        if let logData = try? JSONEncoder().encode(consumptionLog) {
            UserDefaults.standard.set(logData, forKey: "cachedConsumptionLog")
        }
        UserDefaults.standard.synchronize()
    }

    private func loadTimerState() {
        guard let url = timerStateURL() else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let state = try JSONDecoder().decode(TimerState.self, from: data)
                self.treatmentTimer = state.timer
                print("Loaded timer state: \(String(describing: treatmentTimer))")
                logToFile("Loaded timer state: \(String(describing: treatmentTimer))")
            } else {
                print("No timer state file found at \(url.path)")
                logToFile("No timer state file found at \(url.path)")
            }
        } catch {
            print("Failed to load timer state: \(error)")
            logToFile("Failed to load timer state: \(error)")
        }
    }

    public func saveTimerState() {
        guard let url = timerStateURL() else { return }
        
        let now = Date()
        if let last = lastSaveTime, now.timeIntervalSince(last) < 0.5 {
            print("Debounced saveTimerState: too soon since last save at \(last)")
            logToFile("Debounced saveTimerState: too soon since last save at \(last)")
            return
        }
        
        do {
            let state = TimerState(timer: treatmentTimer)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
            lastSaveTime = now
            print("Saved timer state: \(String(describing: treatmentTimer)) to \(url.path)")
            logToFile("Saved timer state: \(String(describing: treatmentTimer)) to \(url.path)")
        } catch {
            print("Failed to save timer state: \(error)")
            logToFile("Failed to save timer state: \(error)")
        }
    }

    private func timerStateURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("timer_state.json")
    }

    func logToFile(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent("app_log.txt")
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logEntry.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? logEntry.data(using: .utf8)?.write(to: fileURL)
            }
        }
    }

    private func loadCurrentUserSettings(userId: UUID) {
        if let data = UserDefaults.standard.data(forKey: "userSettings_\(userId.uuidString)"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            self.currentUser = user
            print("Loaded current user \(userId)")
            logToFile("Loaded current user \(userId)")
        }
    }

    private func saveCurrentUserSettings() {
        guard let user = currentUser else { return }
        UserDefaults.standard.set(user.id.uuidString, forKey: "currentUserId")
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "userSettings_\(user.id.uuidString)")
        }
        saveCachedData()
    }

    public func loadFromFirebase() {
        guard let dbRef = dbRef else {
            print("ERROR: No database reference available.")
            logToFile("ERROR: No database reference available.")
            syncError = "No room code set."
            self.isLoading = false
            return
        }
        
        print("Loading data from Firebase path: \(dbRef.description())")
        
        // First check if the cycles node exists
        dbRef.child("cycles").observeSingleEvent(of: .value) { snapshot in
            if !snapshot.exists() {
                print("Creating empty cycles node")
                dbRef.child("cycles").setValue([:]) { error, ref in
                    if let error = error {
                        print("Error creating cycles node: \(error.localizedDescription)")
                        self.syncError = "Failed to initialize database structure"
                    } else {
                        print("Successfully created cycles node")
                        // Continue loading after ensuring the node exists
                        self.observeCycles()
                    }
                }
            } else {
                // Node exists, continue with regular loading
                self.observeCycles()
            }
        }
        

        dbRef.child("units").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: [String: Any]] {
                let units = value.compactMap { (key, dict) -> Unit? in
                    var mutableDict = dict
                    mutableDict["id"] = key
                    return Unit(dictionary: mutableDict)
                }
                
                DispatchQueue.main.async {
                    if units.isEmpty {
                        // Ensure we always have at least the default units
                        if self.units.isEmpty {
                            self.units = [Unit(name: "mg"), Unit(name: "g"), Unit(name: "tsp"), Unit(name: "tbsp"), Unit(name: "oz"), Unit(name: "mL"), Unit(name: "nuts"), Unit(name: "fist sized")]
                        }
                    } else {
                        // Add default units if they don't exist
                        var allUnits = units
                        let defaultUnits = ["mg", "g", "tsp", "tbsp", "oz", "mL", "nuts", "fist sized"]
                        for defaultUnit in defaultUnits {
                            if !allUnits.contains(where: { $0.name == defaultUnit }) {
                                allUnits.append(Unit(name: defaultUnit))
                            }
                        }
                        self.units = allUnits
                    }
                    
                    // If we have items that reference units not in our units list, add those units
                    self.ensureItemUnitsExist()
                    
                    self.saveCachedData()
                    self.objectWillChange.send()
                }
            } else {
                // If Firebase returns no units, make sure we have at least the defaults
                DispatchQueue.main.async {
                    if self.units.isEmpty {
                        self.units = [Unit(name: "mg"), Unit(name: "g"), Unit(name: "tsp"), Unit(name: "tbsp"), Unit(name: "oz"), Unit(name: "mL"), Unit(name: "nuts"), Unit(name: "fist sized")]
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
        
        dbRef.child("users").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: [String: Any]] {
                let users = value.compactMap { (key, dict) -> User? in
                    var mutableDict = dict
                    mutableDict["id"] = key
                    return User(dictionary: mutableDict)
                }
                DispatchQueue.main.async {
                    self.users = users
                    if let userIdStr = UserDefaults.standard.string(forKey: "currentUserId"),
                       let userId = UUID(uuidString: userIdStr),
                       let updatedUser = users.first(where: { $0.id == userId }) {
                        self.currentUser = updatedUser
                        self.saveCurrentUserSettings()
                    }
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
        
        dbRef.child("consumptionLog").observe(.value) { snapshot in
            var newConsumptionLog: [UUID: [UUID: [LogEntry]]] = [:] // Start fresh, Firebase is source of truth
            for cycleSnapshot in snapshot.children {
                guard let cycleSnapshot = cycleSnapshot as? DataSnapshot,
                      let cycleId = UUID(uuidString: cycleSnapshot.key) else { continue }
                var cycleLog: [UUID: [LogEntry]] = [:]
                for itemSnapshot in cycleSnapshot.children {
                    guard let itemSnapshot = itemSnapshot as? DataSnapshot,
                          let itemId = UUID(uuidString: itemSnapshot.key),
                          let logsData = itemSnapshot.value as? [[String: Any]] else { continue }
                    var itemLogs: [LogEntry] = logsData.compactMap { dict -> LogEntry? in
                        guard let dateStr = dict["timestamp"] as? String,
                              let date = ISO8601DateFormatter().date(from: dateStr),
                              let userIdStr = dict["userId"] as? String,
                              let userId = UUID(uuidString: userIdStr) else { return nil }
                        return LogEntry(date: date, userId: userId)
                    }
                    // Initial deduplication from Firebase
                    itemLogs = Array(Set(itemLogs))
                    cycleLog[itemId] = itemLogs
                }
                if !cycleLog.isEmpty {
                    newConsumptionLog[cycleId] = cycleLog
                }
            }
            DispatchQueue.main.async {
                print("Firebase updated consumptionLog: \(newConsumptionLog)")
                self.logToFile("Firebase updated consumptionLog: \(newConsumptionLog)")
                // Apply pending updates, ensuring no duplicates
                for (cycleId, pendingItems) in self.pendingConsumptionLogUpdates {
                    if var cycleLog = newConsumptionLog[cycleId] {
                        for (itemId, pendingLogs) in pendingItems {
                            var mergedLogs = cycleLog[itemId] ?? []
                            mergedLogs.append(contentsOf: pendingLogs)
                            // Final deduplication after merge
                            mergedLogs = Array(Set(mergedLogs))
                            cycleLog[itemId] = mergedLogs
                        }
                        newConsumptionLog[cycleId] = cycleLog
                    } else {
                        var dedupedPendingItems: [UUID: [LogEntry]] = [:]
                        for (itemId, logs) in pendingItems {
                            dedupedPendingItems[itemId] = Array(Set(logs))
                        }
                        newConsumptionLog[cycleId] = dedupedPendingItems
                    }
                }
                self.consumptionLog = newConsumptionLog
                self.pendingConsumptionLogUpdates.removeAll() // Clear all pending updates after merge
                self.saveCachedData()
                self.objectWillChange.send()
            }
        }
        
        dbRef.child("categoryCollapsed").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: Bool] {
                DispatchQueue.main.async {
                    self.categoryCollapsed = value
                }
            }
        }
        
        dbRef.child("groupCollapsed").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: Bool] {
                DispatchQueue.main.async {
                    let firebaseCollapsed = value.reduce(into: [UUID: Bool]()) { result, pair in
                        if let groupId = UUID(uuidString: pair.key) {
                            result[groupId] = pair.value
                        }
                    }
                    // Merge Firebase data, preserving local changes if they exist
                    for (groupId, isCollapsed) in firebaseCollapsed {
                        if self.groupCollapsed[groupId] == nil {
                            self.groupCollapsed[groupId] = isCollapsed
                        }
                    }
                }
            }
        }
        dbRef.child("treatmentTimer").observe(.value) { snapshot in
            if let timerDict = snapshot.value as? [String: Any],
               let timerObj = TreatmentTimer.fromDictionary(timerDict) {
                
                // Only update if the timer is still active and has not expired
                if timerObj.isActive && timerObj.endTime > Date() {
                    DispatchQueue.main.async {
                        self.treatmentTimer = timerObj
                    }
                } else {
                    // Timer is inactive or expired, clear it
                    DispatchQueue.main.async {
                        self.treatmentTimer = nil
                    }
                }
            } else {
                // No timer in Firebase, clear local timer
                DispatchQueue.main.async {
                    if self.treatmentTimer != nil {
                        self.treatmentTimer = nil
                    }
                }
            }
        }
    }
    
    private func ensureItemUnitsExist() {
        var unitNames = Set(units.map { $0.name })
        
        // Scan all items in all cycles
        for (_, items) in cycleItems {
            for item in items {
                if let unitName = item.unit, !unitName.isEmpty, !unitNames.contains(unitName) {
                    // This item references a unit that doesn't exist in our units list
                    let newUnit = Unit(name: unitName)
                    units.append(newUnit)
                    unitNames.insert(unitName)
                    
                    // Save to Firebase if possible
                    if let dbRef = dbRef {
                        dbRef.child("units").child(newUnit.id.uuidString).setValue(newUnit.toDictionary())
                    }
                }
                
                // Also check weekly doses if present
                if let weeklyDoses = item.weeklyDoses, let unitName = item.unit, !unitName.isEmpty, !unitNames.contains(unitName) {
                    let newUnit = Unit(name: unitName)
                    units.append(newUnit)
                    unitNames.insert(unitName)
                    
                    // Save to Firebase if possible
                    if let dbRef = dbRef {
                        dbRef.child("units").child(newUnit.id.uuidString).setValue(newUnit.toDictionary())
                    }
                }
            }
        }
    }

    func setLastResetDate(_ date: Date) {
        guard let dbRef = dbRef else { return }
        dbRef.child("lastResetDate").setValue(ISO8601DateFormatter().string(from: date))
        lastResetDate = date
    }

    func setTreatmentTimerEnd(_ date: Date?) {
        guard let dbRef = dbRef else { return }
        if let date = date {
            dbRef.child("treatmentTimerEnd").setValue(ISO8601DateFormatter().string(from: date))
        } else {
            dbRef.child("treatmentTimerEnd").removeValue()
            self.treatmentTimerId = nil
        }
    }

    func addUnit(_ unit: Unit) {
        guard let dbRef = dbRef else { return }
        
        // Check if unit already exists with same name to avoid duplicates
        if !units.contains(where: { $0.name == unit.name }) {
            // Add to local array
            units.append(unit)
            
            // Save to Firebase
            dbRef.child("units").child(unit.id.uuidString).setValue(unit.toDictionary())
            
            // Save to cache for offline use
            saveCachedData()
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    func addItem(_ item: Item, toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }), currentUser?.isAdmin == true else {
            completion(false)
            return
        }
        let currentItems = cycleItems[toCycleId] ?? []
        let newOrder = item.order == 0 ? currentItems.count : item.order
        let updatedItem = Item(
            id: item.id,
            name: item.name,
            category: item.category,
            dose: item.dose,
            unit: item.unit,
            weeklyDoses: item.weeklyDoses,
            order: newOrder
        )
        let itemRef = dbRef.child("cycles").child(toCycleId.uuidString).child("items").child(updatedItem.id.uuidString)
        itemRef.setValue(updatedItem.toDictionary()) { error, _ in
            if let error = error {
                print("Error adding item \(updatedItem.id) to Firebase: \(error)")
                self.logToFile("Error adding item \(updatedItem.id) to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    if var items = self.cycleItems[toCycleId] {
                        if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                            items[index] = updatedItem
                        } else {
                            items.append(updatedItem)
                        }
                        self.cycleItems[toCycleId] = items.sorted { $0.order < $1.order }
                    } else {
                        self.cycleItems[toCycleId] = [updatedItem]
                    }
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }
    
    // Add this new method
    private func observeCycles() {
        guard let dbRef = dbRef else { return }
        
        dbRef.child("cycles").observe(.value) { snapshot in
            if self.isAddingCycle { return }
            var newCycles: [Cycle] = []
            
            // IMPORTANT: Don't reset these, keep existing data until we confirm changes
            var newCycleItems = self.cycleItems
            var newGroupedItems = self.groupedItems
            
            print("Firebase cycles snapshot received: \(snapshot.key), childCount: \(snapshot.childrenCount)")
            self.logToFile("Firebase cycles snapshot received: \(snapshot.key), childCount: \(snapshot.childrenCount)")
            
            if snapshot.exists(), let value = snapshot.value as? [String: [String: Any]] {
                print("Processing \(value.count) cycles from Firebase")
                
                for (key, dict) in value {
                    var mutableDict = dict
                    mutableDict["id"] = key
                    guard let cycle = Cycle(dictionary: mutableDict) else {
                        print("Failed to parse cycle with key: \(key)")
                        continue
                    }
                    
                    print("Parsed cycle: \(cycle.number) - \(cycle.patientName)")
                    newCycles.append(cycle)
                    
                    if let itemsDict = dict["items"] as? [String: [String: Any]], !itemsDict.isEmpty {
                        let firebaseItems = itemsDict.compactMap { (itemKey, itemDict) -> Item? in
                            var mutableItemDict = itemDict
                            mutableItemDict["id"] = itemKey
                            return Item(dictionary: mutableItemDict)
                        }.sorted { $0.order < $1.order }
                        
                        if let localItems = newCycleItems[cycle.id] {
                            // Improved merging logic - preserve weekly doses information
                            var mergedItems = localItems.map { localItem in
                                if let firebaseItem = firebaseItems.first(where: { $0.id == localItem.id }) {
                                    // If the item exists in both places, create a merged version
                                    // that prioritizes local weekly doses if they exist
                                    return Item(
                                        id: localItem.id,
                                        name: firebaseItem.name,
                                        category: firebaseItem.category,
                                        dose: firebaseItem.dose,
                                        unit: firebaseItem.unit,
                                        weeklyDoses: localItem.weeklyDoses ?? firebaseItem.weeklyDoses,
                                        order: firebaseItem.order
                                    )
                                } else {
                                    return localItem
                                }
                            }
                            let newFirebaseItems = firebaseItems.filter { firebaseItem in
                                !mergedItems.contains(where: { mergedItem in mergedItem.id == firebaseItem.id })
                            }
                            mergedItems.append(contentsOf: newFirebaseItems)
                            newCycleItems[cycle.id] = mergedItems.sorted { $0.order < $1.order }
                        } else {
                            newCycleItems[cycle.id] = firebaseItems
                        }
                    } else if newCycleItems[cycle.id] == nil {
                        newCycleItems[cycle.id] = []
                    }
                    
                    if let groupedItemsDict = dict["groupedItems"] as? [String: [String: Any]] {
                        let firebaseGroupedItems = groupedItemsDict.compactMap { (groupKey, groupDict) -> GroupedItem? in
                            var mutableGroupDict = groupDict
                            mutableGroupDict["id"] = groupKey
                            return GroupedItem(dictionary: mutableGroupDict)
                        }
                        newGroupedItems[cycle.id] = firebaseGroupedItems
                    } else if newGroupedItems[cycle.id] == nil {
                        newGroupedItems[cycle.id] = []
                    }
                }
                // When updating, carefully merge data
                DispatchQueue.main.async {
                    self.cycles = newCycles.sorted { $0.startDate < $1.startDate }
                    
                    // Don't wipe out existing data if nothing new came in
                    if !newCycleItems.isEmpty {
                        self.cycleItems = newCycleItems
                    }
                    if !newGroupedItems.isEmpty {
                        self.groupedItems = newGroupedItems
                    }
                    
                    self.saveCachedData()
                    self.syncError = nil
                    self.isLoading = false
                }
            
            } else {
                DispatchQueue.main.async {
                    if self.cycles.isEmpty {
                        print("ERROR: No cycles found in Firebase or data is malformed: \(snapshot.key)")
                        self.syncError = "No cycles found in Firebase or data is malformed."
                    } else {
                        // Keep using cached cycles if Firebase returns empty
                        print("No cycles in Firebase but using cached data")
                        self.syncError = nil
                    }
                    self.isLoading = false
                }
            }
        } withCancel: { error in
            DispatchQueue.main.async {
                self.syncError = "Failed to sync cycles: \(error.localizedDescription)"
                self.isLoading = false
                print("Sync error: \(error.localizedDescription)")
                self.logToFile("Sync error: \(error.localizedDescription)")
            }
        }
    }

    func saveItems(_ items: [Item], toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }) else {
            completion(false)
            return
        }
        let itemsDict = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.toDictionary()) })
        dbRef.child("cycles").child(toCycleId.uuidString).child("items").setValue(itemsDict) { error, _ in
            if let error = error {
                print("Error saving items to Firebase: \(error)")
                self.logToFile("Error saving items to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    self.cycleItems[toCycleId] = items.sorted { $0.order < $1.order }
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }

    func removeItem(_ itemId: UUID, fromCycleId: UUID) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == fromCycleId }), currentUser?.isAdmin == true else { return }
        dbRef.child("cycles").child(fromCycleId.uuidString).child("items").child(itemId.uuidString).removeValue()
        if var items = cycleItems[fromCycleId] {
            items.removeAll { $0.id == itemId }
            cycleItems[fromCycleId] = items
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    func addCycle(_ cycle: Cycle, copyItemsFromCycleId: UUID? = nil) {
        guard let dbRef = dbRef, currentUser?.isAdmin == true else { return }
        
        print("Adding cycle \(cycle.id) with number \(cycle.number)")
        
        if cycles.contains(where: { $0.id == cycle.id }) {
            print("Cycle \(cycle.id) already exists, updating")
            saveCycleToFirebase(cycle, withItems: cycleItems[cycle.id] ?? [], groupedItems: groupedItems[cycle.id] ?? [], previousCycleId: copyItemsFromCycleId)
            return
        }
        
        isAddingCycle = true
        cycles.append(cycle)
        var copiedItems: [Item] = []
        var copiedGroupedItems: [GroupedItem] = []
        
        let effectiveCopyId = copyItemsFromCycleId ?? (cycles.count > 1 ? cycles[cycles.count - 2].id : nil)
        
        if let fromCycleId = effectiveCopyId {
            dbRef.child("cycles").child(fromCycleId.uuidString).observeSingleEvent(of: .value) { snapshot in
                if let dict = snapshot.value as? [String: Any] {
                    if let itemsDict = dict["items"] as? [String: [String: Any]] {
                        copiedItems = itemsDict.compactMap { (itemKey, itemDict) -> Item? in
                            var mutableItemDict = itemDict
                            mutableItemDict["id"] = itemKey
                            return Item(dictionary: mutableItemDict)
                        }.map { Item(id: UUID(), name: $0.name, category: $0.category, dose: $0.dose, unit: $0.unit, weeklyDoses: $0.weeklyDoses, order: $0.order) }
                    }
                    if let groupedItemsDict = dict["groupedItems"] as? [String: [String: Any]] {
                        copiedGroupedItems = groupedItemsDict.compactMap { (groupKey, groupDict) -> GroupedItem? in
                            var mutableGroupDict = groupDict
                            mutableGroupDict["id"] = groupKey
                            return GroupedItem(dictionary: mutableGroupDict)
                        }.map { GroupedItem(id: UUID(), name: $0.name, category: $0.category, itemIds: $0.itemIds.map { _ in UUID() }) }
                    }
                }
                DispatchQueue.main.async {
                    self.cycleItems[cycle.id] = copiedItems
                    self.groupedItems[cycle.id] = copiedGroupedItems
                    self.saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
                }
            } withCancel: { error in
                DispatchQueue.main.async {
                    self.cycleItems[cycle.id] = copiedItems
                    self.groupedItems[cycle.id] = copiedGroupedItems
                    self.saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
                }
            }
        } else {
            cycleItems[cycle.id] = []
            groupedItems[cycle.id] = []
            saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
        }
        cycleItems[cycle.id] = copiedItems
            groupedItems[cycle.id] = copiedGroupedItems
            
            // Initialize Firebase structure for this cycle
            var cycleDict = cycle.toDictionary()
            dbRef.child("cycles").child(cycle.id.uuidString).setValue(cycleDict) { error, _ in
                if let error = error {
                    print("ERROR: Failed to create initial cycle: \(error.localizedDescription)")
                } else {
                    print("Successfully created initial cycle structure for \(cycle.id)")
                }
            }
            
            saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: copyItemsFromCycleId)
        }
    

    private func saveCycleToFirebase(_ cycle: Cycle, withItems items: [Item], groupedItems: [GroupedItem], previousCycleId: UUID?) {
        guard let dbRef = dbRef else { return }
        var cycleDict = cycle.toDictionary()
        let cycleRef = dbRef.child("cycles").child(cycle.id.uuidString)
        
        cycleRef.updateChildValues(cycleDict) { error, _ in
            if let error = error {
                DispatchQueue.main.async {
                    if let index = self.cycles.firstIndex(where: { $0.id == cycle.id }) {
                        self.cycles.remove(at: index)
                        self.cycleItems.removeValue(forKey: cycle.id)
                        self.groupedItems.removeValue(forKey: cycle.id)
                    }
                    self.isAddingCycle = false
                    self.objectWillChange.send()
                }
                return
            }
            
            if !items.isEmpty {
                let itemsDict = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.toDictionary()) })
                cycleRef.child("items").updateChildValues(itemsDict)
            }
            
            if !groupedItems.isEmpty {
                let groupedItemsDict = Dictionary(uniqueKeysWithValues: groupedItems.map { ($0.id.uuidString, $0.toDictionary()) })
                cycleRef.child("groupedItems").updateChildValues(groupedItemsDict)
            }
            
            if let prevId = previousCycleId, let prevItems = self.cycleItems[prevId], !prevItems.isEmpty {
                let prevCycleRef = dbRef.child("cycles").child(prevId.uuidString)
                prevCycleRef.child("items").observeSingleEvent(of: .value) { snapshot in
                    if snapshot.value == nil || (snapshot.value as? [String: [String: Any]])?.isEmpty ?? true {
                        let prevItemsDict = Dictionary(uniqueKeysWithValues: prevItems.map { ($0.id.uuidString, $0.toDictionary()) })
                        prevCycleRef.child("items").updateChildValues(prevItemsDict)
                    }
                }
            }
            
            DispatchQueue.main.async {
                if self.cycleItems[cycle.id] == nil || self.cycleItems[cycle.id]!.isEmpty {
                    self.cycleItems[cycle.id] = items
                }
                if self.groupedItems[cycle.id] == nil || self.groupedItems[cycle.id]!.isEmpty {
                    self.groupedItems[cycle.id] = groupedItems
                }
                self.saveCachedData()
                self.isAddingCycle = false
                self.objectWillChange.send()
            }
        }
    }

    func addUser(_ user: User) {
        guard let dbRef = dbRef else { return }
        print("Adding/updating user: \(user.id) with name: \(user.name)")
        
        let userRef = dbRef.child("users").child(user.id.uuidString)
        userRef.setValue(user.toDictionary()) { error, _ in
            if let error = error {
                print("Error adding/updating user \(user.id): \(error)")
                self.logToFile("Error adding/updating user \(user.id): \(error)")
            } else {
                print("Successfully added/updated user \(user.id) with name: \(user.name)")
            }
        }
        DispatchQueue.main.async {
            if let index = self.users.firstIndex(where: { $0.id == user.id }) {
                self.users[index] = user
            } else {
                self.users.append(user)
            }
            if self.currentUser?.id == user.id {
                self.currentUser = user
            }
            self.saveCurrentUserSettings()
        }
    }

    func logConsumption(itemId: UUID, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef, let userId = currentUser?.id, cycles.contains(where: { $0.id == cycleId }) else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let logEntry = LogEntry(date: date, userId: userId)
        let today = Calendar.current.startOfDay(for: Date())

        // Fetch current Firebase state first
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var currentLogs = (snapshot.value as? [[String: String]]) ?? []
            let newEntryDict = ["timestamp": timestamp, "userId": userId.uuidString]
            
            // Remove any existing log for today to prevent duplicates
            currentLogs.removeAll { entry in
                if let logTimestamp = entry["timestamp"],
                   let logDate = formatter.date(from: logTimestamp) {
                    return Calendar.current.isDate(logDate, inSameDayAs: today)
                }
                return false
            }
            
            // Add the new entry
            currentLogs.append(newEntryDict)
            
            // Write to Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(currentLogs) { error, _ in
                if let error = error {
                    print("Failed to log consumption for \(itemId): \(error)")
                    self.logToFile("Failed to log consumption for \(itemId): \(error)")
                } else {
                    // Update local consumptionLog only after Firebase success
                    DispatchQueue.main.async {
                        if var cycleLog = self.consumptionLog[cycleId] {
                            var itemLogs = cycleLog[itemId] ?? []
                            // Remove today's existing logs locally
                            itemLogs.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
                            itemLogs.append(logEntry)
                            cycleLog[itemId] = itemLogs
                            self.consumptionLog[cycleId] = cycleLog
                        } else {
                            self.consumptionLog[cycleId] = [itemId: [logEntry]]
                        }
                        // Clear pending updates for this item
                        if var cyclePending = self.pendingConsumptionLogUpdates[cycleId] {
                            cyclePending.removeValue(forKey: itemId)
                            if cyclePending.isEmpty {
                                self.pendingConsumptionLogUpdates.removeValue(forKey: cycleId)
                            } else {
                                self.pendingConsumptionLogUpdates[cycleId] = cyclePending
                            }
                        }
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }

    func removeConsumption(itemId: UUID, cycleId: UUID, date: Date) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        
        // Update local consumptionLog
        if var cycleLogs = consumptionLog[cycleId], var itemLogs = cycleLogs[itemId] {
            itemLogs.removeAll { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .second) }
            if itemLogs.isEmpty {
                cycleLogs.removeValue(forKey: itemId)
            } else {
                cycleLogs[itemId] = itemLogs
            }
            consumptionLog[cycleId] = cycleLogs.isEmpty ? nil : cycleLogs
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        // Update Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if var entries = snapshot.value as? [[String: String]] {
                entries.removeAll { $0["timestamp"] == timestamp }
                dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(entries.isEmpty ? nil : entries) { error, _ in
                    if let error = error {
                        print("Failed to remove consumption for \(itemId): \(error)")
                        self.logToFile("Failed to remove consumption for \(itemId): \(error)")
                    }
                }
            }
        }
    }

    func setConsumptionLog(itemId: UUID, cycleId: UUID, entries: [LogEntry]) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let newEntries = Array(Set(entries)) // Deduplicate entries
        
        print("Setting consumption log for item \(itemId) in cycle \(cycleId) with entries: \(newEntries.map { $0.date })")
        
        // Fetch existing logs and update
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var existingEntries = (snapshot.value as? [[String: String]]) ?? []
            let newEntryDicts = newEntries.map { ["timestamp": formatter.string(from: $0.date), "userId": $0.userId.uuidString] }
            
            // Remove any existing entries not in the new list to prevent retaining old logs
            existingEntries = existingEntries.filter { existingEntry in
                guard let timestamp = existingEntry["timestamp"],
                      let date = formatter.date(from: timestamp) else { return false }
                return newEntries.contains { $0.date == date && $0.userId.uuidString == existingEntry["userId"] }
            }
            
            // Add new entries
            for newEntry in newEntryDicts {
                if !existingEntries.contains(where: { $0["timestamp"] == newEntry["timestamp"] && $0["userId"] == newEntry["userId"] }) {
                    existingEntries.append(newEntry)
                }
            }
            
            // Update local consumptionLog
            if var cycleLog = self.consumptionLog[cycleId] {
                cycleLog[itemId] = newEntries
                self.consumptionLog[cycleId] = cycleLog.isEmpty ? nil : cycleLog
            } else {
                self.consumptionLog[cycleId] = [itemId: newEntries]
            }
            if self.pendingConsumptionLogUpdates[cycleId] == nil {
                self.pendingConsumptionLogUpdates[cycleId] = [:]
            }
            self.pendingConsumptionLogUpdates[cycleId]![itemId] = newEntries
            self.saveCachedData()
            
            print("Updating Firebase with: \(existingEntries)")
            
            // Update Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(existingEntries.isEmpty ? nil : existingEntries) { error, _ in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Failed to set consumption log for \(itemId): \(error)")
                        self.logToFile("Failed to set consumption log for \(itemId): \(error)")
                        self.syncError = "Failed to sync log: \(error.localizedDescription)"
                    } else {
                        if var cyclePending = self.pendingConsumptionLogUpdates[cycleId] {
                            cyclePending.removeValue(forKey: itemId)
                            if cyclePending.isEmpty {
                                self.pendingConsumptionLogUpdates.removeValue(forKey: cycleId)
                            } else {
                                self.pendingConsumptionLogUpdates[cycleId] = cyclePending
                            }
                        }
                        print("Firebase update complete, local log: \(self.consumptionLog[cycleId]?[itemId] ?? [])")
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func setCategoryCollapsed(_ category: Category, isCollapsed: Bool) {
        guard let dbRef = dbRef else { return }
        categoryCollapsed[category.rawValue] = isCollapsed
        dbRef.child("categoryCollapsed").child(category.rawValue).setValue(isCollapsed)
    }
    
    func setGroupCollapsed(_ groupId: UUID, isCollapsed: Bool) {
        guard let dbRef = dbRef else { return }
        groupCollapsed[groupId] = isCollapsed
        dbRef.child("groupCollapsed").child(groupId.uuidString).setValue(isCollapsed)
    }

    func setReminderEnabled(_ category: Category, enabled: Bool) {
        guard var user = currentUser else { return }
        user.remindersEnabled[category] = enabled
        addUser(user)
    }

    func setReminderTime(_ category: Category, time: Date) {
        guard var user = currentUser else { return }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return }
        let now = Date()
        var normalizedComponents = calendar.dateComponents([.year, .month, .day], from: now)
        normalizedComponents.hour = hour
        normalizedComponents.minute = minute
        normalizedComponents.second = 0
        if let normalizedTime = calendar.date(from: normalizedComponents) {
            user.reminderTimes[category] = normalizedTime
            addUser(user)
        }
    }

    func setTreatmentFoodTimerEnabled(_ enabled: Bool) {
        guard var user = currentUser else { return }
        user.treatmentFoodTimerEnabled = enabled
        addUser(user)
    }

    func setTreatmentTimerDuration(_ duration: TimeInterval) {
        guard var user = currentUser else { return }
        user.treatmentTimerDuration = duration
        addUser(user)
    }

    func addGroupedItem(_ groupedItem: GroupedItem, toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }), currentUser?.isAdmin == true else {
            completion(false)
            return
        }
        let groupRef = dbRef.child("cycles").child(toCycleId.uuidString).child("groupedItems").child(groupedItem.id.uuidString)
        groupRef.setValue(groupedItem.toDictionary()) { error, _ in
            if let error = error {
                print("Error adding grouped item \(groupedItem.id) to Firebase: \(error)")
                self.logToFile("Error adding grouped item \(groupedItem.id) to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    var cycleGroups = self.groupedItems[toCycleId] ?? []
                    if let index = cycleGroups.firstIndex(where: { $0.id == groupedItem.id }) {
                        cycleGroups[index] = groupedItem
                    } else {
                        cycleGroups.append(groupedItem)
                    }
                    self.groupedItems[toCycleId] = cycleGroups
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }

    func removeGroupedItem(_ groupId: UUID, fromCycleId: UUID) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == fromCycleId }), currentUser?.isAdmin == true else { return }
        dbRef.child("cycles").child(fromCycleId.uuidString).child("groupedItems").child(groupId.uuidString).removeValue()
        if var groups = groupedItems[fromCycleId] {
            groups.removeAll { $0.id == groupId }
            groupedItems[fromCycleId] = groups
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    func logGroupedItem(_ groupedItem: GroupedItem, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef else { return }
        let today = Calendar.current.startOfDay(for: date)
        let isChecked = groupedItem.itemIds.allSatisfy { itemId in
            self.consumptionLog[cycleId]?[itemId]?.contains { Calendar.current.isDate($0.date, inSameDayAs: today) } ?? false
        }
        
        print("logGroupedItem: Group \(groupedItem.name) isChecked=\(isChecked)")
        self.logToFile("logGroupedItem: Group \(groupedItem.name) isChecked=\(isChecked)")
        
        if isChecked {
            for itemId in groupedItem.itemIds {
                if let logs = self.consumptionLog[cycleId]?[itemId], !logs.isEmpty {
                    print("Clearing all \(logs.count) logs for item \(itemId)")
                    self.logToFile("Clearing all \(logs.count) logs for item \(itemId)")
                    if var itemLogs = self.consumptionLog[cycleId] {
                        itemLogs[itemId] = []
                        if itemLogs[itemId]?.isEmpty ?? true {
                            itemLogs.removeValue(forKey: itemId)
                        }
                        self.consumptionLog[cycleId] = itemLogs.isEmpty ? nil : itemLogs
                    }
                    let path = "consumptionLog/\(cycleId.uuidString)/\(itemId.uuidString)"
                    dbRef.child(path).removeValue { error, _ in
                        if let error = error {
                            print("Failed to clear logs for \(itemId): \(error)")
                            self.logToFile("Failed to clear logs for \(itemId): \(error)")
                        } else {
                            print("Successfully cleared logs for \(itemId) in Firebase")
                            self.logToFile("Successfully cleared logs for \(itemId) in Firebase")
                        }
                    }
                }
            }
        } else {
            for itemId in groupedItem.itemIds {
                if !(self.consumptionLog[cycleId]?[itemId]?.contains { Calendar.current.isDate($0.date, inSameDayAs: today) } ?? false) {
                    print("Logging item \(itemId) for \(date)")
                    self.logToFile("Logging item \(itemId) for \(date)")
                    self.logConsumption(itemId: itemId, cycleId: cycleId, date: date)
                }
            }
        }
        self.saveCachedData()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func resetDaily() {
        let today = Calendar.current.startOfDay(for: Date())
        setLastResetDate(today)
        
        for (cycleId, itemLogs) in consumptionLog {
            var updatedItemLogs = itemLogs
            for (itemId, logs) in itemLogs {
                updatedItemLogs[itemId] = logs.filter { !Calendar.current.isDate($0.date, inSameDayAs: today) }
                if updatedItemLogs[itemId]?.isEmpty ?? false {
                    updatedItemLogs.removeValue(forKey: itemId)
                }
            }
            if let dbRef = dbRef {
                let formatter = ISO8601DateFormatter()
                let updatedLogDict = updatedItemLogs.mapValues { entries in
                    entries.map { ["timestamp": formatter.string(from: $0.date), "userId": $0.userId.uuidString] }
                }
                dbRef.child("consumptionLog").child(cycleId.uuidString).setValue(updatedLogDict.isEmpty ? nil : updatedLogDict)
            }
            consumptionLog[cycleId] = updatedItemLogs.isEmpty ? nil : updatedItemLogs
        }
        
        Category.allCases.forEach { category in
            setCategoryCollapsed(category, isCollapsed: false)
        }
        
        if let timer = treatmentTimer, timer.isActive, timer.endTime > Date() {
            print("Preserving active timer ending at: \(timer.endTime)")
            logToFile("Preserving active timer ending at: \(timer.endTime)")
        } else {
            treatmentTimer = nil
        }
        
        saveCachedData()
        saveTimerState()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func checkAndResetIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if lastResetDate == nil || !Calendar.current.isDate(lastResetDate!, inSameDayAs: today) {
            resetDaily()
        }
    }

    func currentCycleId() -> UUID? {
        let today = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        
        // First check if today is within any cycle's date range
        for cycle in cycles {
            let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
            let cycleEndDay = calendar.startOfDay(for: cycle.foodChallengeDate)
            
            if todayStart >= cycleStartDay && todayStart <= cycleEndDay {
                return cycle.id
            }
        }
        
        // If we're between cycles, use the most recent cycle that has started
        return cycles.filter {
            calendar.startOfDay(for: $0.startDate) <= todayStart
        }.max(by: {
            $0.startDate < $1.startDate
        })?.id ?? cycles.last?.id
    }

    func verifyFirebaseState() {
        guard let dbRef = dbRef else { return }
        dbRef.child("cycles").observeSingleEvent(of: .value) { snapshot in
            if let value = snapshot.value as? [String: [String: Any]] {
                print("Final Firebase cycles state: \(value)")
                self.logToFile("Final Firebase cycles state: \(value)")
            } else {
                print("Final Firebase cycles state is empty or missing")
                self.logToFile("Final Firebase cycles state is empty or missing")
            }
        }
    }

    func rescheduleDailyReminders() {
        guard let user = currentUser else { return }
        for category in Category.allCases where user.remindersEnabled[category] == true {
            if let view = UIApplication.shared.windows.first?.rootViewController?.view {
                RemindersView(appData: self).scheduleReminder(for: category)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 24 * 3600) {
            self.rescheduleDailyReminders()
        }
    }
}

struct TimerState: Codable {
    let timer: TreatmentTimer?
}

extension AppData {
    // This method logs a consumption for a specific item without triggering group logging behavior
    // Add or replace this method in your AppData extension
    func logIndividualConsumption(itemId: UUID, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef, let userId = currentUser?.id, cycles.contains(where: { $0.id == cycleId }) else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let logEntry = LogEntry(date: date, userId: userId)
        let calendar = Calendar.current
        let logDay = calendar.startOfDay(for: date)
        
        // Check if the item already has a log for this day locally
        if let existingLogs = consumptionLog[cycleId]?[itemId] {
            let existingLogForDay = existingLogs.first { calendar.isDate($0.date, inSameDayAs: logDay) }
            if existingLogForDay != nil {
                print("Item \(itemId) already has a log for \(logDay), skipping")
                return
            }
        }
        
        // Fetch current logs from Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var currentLogs = (snapshot.value as? [[String: String]]) ?? []
            
            // Deduplicate entries by day in case there are already duplicates in Firebase
            var entriesByDay = [String: [String: String]]()
            
            for entry in currentLogs {
                if let entryTimestamp = entry["timestamp"],
                   let entryDate = formatter.date(from: entryTimestamp) {
                    let dayKey = formatter.string(from: calendar.startOfDay(for: entryDate))
                    entriesByDay[dayKey] = entry
                }
            }
            
            // Check if there's already an entry for this day
            let todayKey = formatter.string(from: logDay)
            if entriesByDay[todayKey] != nil {
                print("Firebase already has an entry for \(logDay), skipping")
                return
            }
            
            // Add new entry
            let newEntryDict = ["timestamp": timestamp, "userId": userId.uuidString]
            entriesByDay[todayKey] = newEntryDict
            
            // Convert back to array
            let deduplicatedLogs = Array(entriesByDay.values)
            
            // Update Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(deduplicatedLogs) { error, _ in
                if let error = error {
                    print("Error logging consumption for \(itemId): \(error)")
                    self.logToFile("Error logging consumption for \(itemId): \(error)")
                } else {
                    // Update local data after Firebase success
                    DispatchQueue.main.async {
                        if var cycleLog = self.consumptionLog[cycleId] {
                            if var itemLogs = cycleLog[itemId] {
                                // Remove any existing logs for the same day before adding the new one
                                itemLogs.removeAll { calendar.isDate($0.date, inSameDayAs: logDay) }
                                itemLogs.append(logEntry)
                                cycleLog[itemId] = itemLogs
                            } else {
                                cycleLog[itemId] = [logEntry]
                            }
                            self.consumptionLog[cycleId] = cycleLog
                        } else {
                            self.consumptionLog[cycleId] = [itemId: [logEntry]]
                        }
                        
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    // This method enhances the deletion of consumption logs to ensure consistent state
    func removeIndividualConsumption(itemId: UUID, cycleId: UUID, date: Date) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let calendar = Calendar.current
        
        // Update local consumptionLog first
        if var cycleLogs = consumptionLog[cycleId], var itemLogs = cycleLogs[itemId] {
            itemLogs.removeAll { calendar.isDate($0.date, equalTo: date, toGranularity: .second) }
            if itemLogs.isEmpty {
                cycleLogs.removeValue(forKey: itemId)
            } else {
                cycleLogs[itemId] = itemLogs
            }
            consumptionLog[cycleId] = cycleLogs.isEmpty ? nil : cycleLogs
            saveCachedData()
        }
        
        // Then update Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if var entries = snapshot.value as? [[String: String]] {
                // Remove entries that match the date (could be multiple if there were duplicates)
                entries.removeAll { entry in
                    guard let entryTimestamp = entry["timestamp"],
                          let entryDate = formatter.date(from: entryTimestamp) else {
                        return false
                    }
                    return calendar.isDate(entryDate, equalTo: date, toGranularity: .second)
                }
                
                // Update or remove the entry in Firebase
                if entries.isEmpty {
                    dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).removeValue { error, _ in
                        if let error = error {
                            print("Error removing consumption for \(itemId): \(error)")
                            self.logToFile("Error removing consumption for \(itemId): \(error)")
                        } else {
                            print("Successfully removed all logs for item \(itemId)")
                            self.logToFile("Successfully removed all logs for item \(itemId)")
                        }
                    }
                } else {
                    dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(entries) { error, _ in
                        if let error = error {
                            print("Error updating consumption for \(itemId): \(error)")
                            self.logToFile("Error updating consumption for \(itemId): \(error)")
                        } else {
                            print("Successfully updated logs for item \(itemId)")
                            self.logToFile("Successfully updated logs for item \(itemId)")
                        }
                    }
                }
            }
        }
        
        // Ensure UI updates
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
extension AppData {
    // Method to safely access dbRef for direct Firebase operations in critical code paths
    func valueForDBRef() -> DatabaseReference? {
        return dbRef
    }
}
