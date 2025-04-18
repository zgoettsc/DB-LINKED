import SwiftUI
import UserNotifications

struct RemindersView: View {
    @ObservedObject var appData: AppData
    @State private var notificationPermissionDenied = false
    @State private var showingPermissionAlert = false
    
    var body: some View {
        Form {
            Section {
                Text("Set daily dose reminders for each category. If items in a category are not logged by the selected time, a notification will be sent.")
                    .font(.caption)
                    .foregroundColor(.gray)
                if notificationPermissionDenied {
                    Text("Notifications are disabled. Enable them in Settings > Notifications > TIPs App.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            ForEach(Category.allCases, id: \.self) { category in
                Section(header: Text(category.rawValue)) {
                    Toggle("Daily Dose Reminder", isOn: Binding(
                        get: { appData.currentUser?.remindersEnabled[category] ?? false },
                        set: { newValue in
                            ensureUserInitialized()
                            if var user = appData.currentUser {
                                user.remindersEnabled[category] = newValue
                                appData.currentUser = user
                                appData.addUser(user)
                                print("Toggle set \(category.rawValue) to \(newValue)")
                                if newValue {
                                    if user.reminderTimes[category] == nil {
                                        appData.setReminderTime(category, time: defaultReminderTime())
                                    }
                                    scheduleReminder(for: category)
                                } else {
                                    cancelReminder(for: category)
                                }
                            }
                        }
                    ))
                    if appData.currentUser?.remindersEnabled[category] ?? false {
                        DatePicker("Time", selection: Binding(
                            get: { appData.currentUser?.reminderTimes[category] ?? defaultReminderTime() },
                            set: { newValue in
                                print("DatePicker setting \(category.rawValue) to \(newValue)")
                                ensureUserInitialized()
                                appData.setReminderTime(category, time: newValue)
                                scheduleReminder(for: category)
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                }
            }
        }
        .navigationTitle("Dose Reminders")
        .onAppear {
            requestNotificationPermission()
            checkNotificationPermissions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.rescheduleAllReminders()
            }
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Notifications Required"),
                message: Text("Please enable notifications in Settings to use dose reminders."),
                primaryButton: .default(Text("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func defaultReminderTime() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? now
    }
    
    private func ensureUserInitialized() {
        if appData.currentUser == nil {
            let defaultUser = User(id: UUID(), name: "Default User", isAdmin: true)
            appData.addUser(defaultUser)
            appData.currentUser = defaultUser
            UserDefaults.standard.set(defaultUser.id.uuidString, forKey: "currentUserId")
            print("Initialized default user: \(defaultUser.id)")
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("Notification permission granted")
                    UNUserNotificationCenter.current().delegate = UIApplication.shared.delegate as? UNUserNotificationCenterDelegate
                } else {
                    self.notificationPermissionDenied = true
                    self.showingPermissionAlert = true
                }
                if let error = error {
                    print("Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationPermissionDenied = settings.authorizationStatus == .denied
            }
        }
    }
    
    func scheduleReminder(for category: Category) {
        guard let user = appData.currentUser, user.remindersEnabled[category] == true,
              let time = user.reminderTimes[category] else {
            print("Skipping reminder for \(category.rawValue): not enabled or no time set")
            return
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(category.rawValue)"
        content.body = "Have you consumed all items in \(category.rawValue) yet?"
        content.sound = .default
        content.categoryIdentifier = "REMINDER_CATEGORY"
        
        var triggerComponents = DateComponents()
        triggerComponents.hour = hour
        triggerComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
        let identifier = "reminder_\(user.id.uuidString)_\(category.rawValue)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Clear any prior reminders for this category
        cancelReminder(for: category)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling reminder for \(category.rawValue): \(error.localizedDescription)")
            } else {
                let timeString = String(format: "%02d:%02d", hour, minute)
                print("Scheduled repeating reminder for \(category.rawValue) at \(timeString) local time (identifier: \(identifier))")
            }
        }
        
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let pending = requests.map { "\($0.identifier) - \($0.trigger?.description ?? "No trigger")" }
            print("Pending notifications after scheduling \(category.rawValue): \(pending)")
        }
    }
    
    func cancelReminder(for category: Category) {
        guard let userId = appData.currentUser?.id else { return }
        let identifier = "reminder_\(userId.uuidString)_\(category.rawValue)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("Cancelled reminder for \(category.rawValue): \(identifier)")
    }
    
    func rescheduleAllReminders() {
        guard let user = appData.currentUser else {
            print("No current user, skipping reschedule")
            return
        }
        print("Rescheduling reminders for user \(user.id), enabled: \(user.remindersEnabled), times: \(user.reminderTimes)")
        for category in Category.allCases {
            if user.remindersEnabled[category] == true {
                scheduleReminder(for: category)
            } else {
                cancelReminder(for: category)
            }
        }
    }
}

struct RemindersView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RemindersView(appData: AppData())
        }
    }
}
