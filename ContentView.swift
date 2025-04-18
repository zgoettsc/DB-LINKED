import SwiftUI
import UserNotifications
import AVFoundation
import AudioToolbox


struct TimeOfDayTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2)) // Slightly increased opacity for visibility
            .cornerRadius(10)
    }
}

extension Category {
    var icon: String {
        switch self {
        case .medicine: return "pills.fill"
        case .maintenance: return "applelogo"
        case .treatment: return "fork.knife"
        case .recommended: return "star.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .medicine: return .blue
        case .maintenance: return .green
        case .treatment: return .purple
        case .recommended: return .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .medicine, .maintenance, .treatment, .recommended:
            return Color(.secondarySystemBackground)
        }
    }

    var progressBarColor: Color {
        switch self {
        case .treatment: return .purple
        case .recommended: return .orange
        default: return .blue
        }
    }
}

struct ProfileHeaderView: View {
    let appData: AppData
    let name: String
    let cycle: Int
    let week: Int
    let day: Int
    let image: Image?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let cycleId = appData.currentCycleId(),
                   let profileImage = appData.loadProfileImage(forCycleId: cycleId) {
                    Image(uiImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)  // Increased from 56x56 to 80x80
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                } else if let image = image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)  // Increased from 56x56 to 80x80
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                } else {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)  // Increased from 56x56 to 80x80
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Cycle \(cycle) • Week \(week) • Day \(day)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }
}
extension View {
    func cardStyle(background: Color = Color(.secondarySystemBackground)) -> some View {
        self
            .padding()
            .background(background)
            .cornerRadius(20)
            .shadow(color: Color.primary.opacity(0.05), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
    }

    func timeOfDayTagStyle(color: Color) -> some View {
        self
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .cornerRadius(10)
    }
}

// --- AudioPlayer and GroupView remain unchanged ---

// AudioPlayer class to handle alarm sounds
class AudioPlayer {
    static var player: AVAudioPlayer?
    static var repeatCount = 0
    static let maxRepeats = 3

    static func playAlarmSound() {
        if let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.volume = 1.0
                player?.numberOfLoops = maxRepeats
                player?.play()
                print("Playing alarm.mp3 from \(url.path) with \(maxRepeats) repeats")
            } catch {
                print("Failed to play alarm.mp3: \(error.localizedDescription)")
                playSystemSound()
            }
        } else {
            print("Alarm sound file not found in bundle")
            playSystemSound()
        }
    }
    
    static func playSystemSound() {
        repeatCount = 0
        playSystemSoundOnce()
    }
    
    private static func playSystemSoundOnce() {
        AudioServicesPlaySystemSoundWithCompletion(SystemSoundID(1005)) {
            repeatCount += 1
            if repeatCount <= maxRepeats {
                print("Repeating system sound 1005, count: \(repeatCount)")
                playSystemSoundOnce()
            } else {
                print("Finished repeating system sound 1005")
            }
        }
        print("Playing system sound 1005")
    }
    
    static func stopAlarmSound() {
        player?.stop()
        repeatCount = maxRepeats + 1
        print("Stopped alarm sound")
    }
}

// GroupView struct for rendering grouped items
struct GroupView: View {
    @ObservedObject var appData: AppData
    let group: GroupedItem
    let cycleId: UUID
    let items: [Item]
    let weeklyCounts: [UUID: Int]
    @Binding var forceRefreshID: UUID

    init(appData: AppData, group: GroupedItem, cycleId: UUID, items: [Item], weeklyCounts: [UUID: Int], forceRefreshID: Binding<UUID>) {
        self.appData = appData
        self.group = group
        self.cycleId = cycleId
        self.items = items
        self.weeklyCounts = weeklyCounts
        self._forceRefreshID = forceRefreshID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    print("Group \(group.id) button tapped, isChecked=\(isGroupChecked())")
                    toggleGroupCheck()
                    forceRefreshID = UUID()
                }) {
                    Image(systemName: isGroupChecked() ? "checkmark.square.fill" : "square")
                        .foregroundColor(isGroupChecked() ? .secondary : .blue)
                        .font(.title3)
                }
                Text(group.name)
                    .font(.headline)
                    .bold()
                    .foregroundColor(.primary)
                    .onTapGesture {
                        let currentState = appData.groupCollapsed[group.id] ?? true
                        appData.setGroupCollapsed(group.id, isCollapsed: !currentState)
                        print("Tapped \(group.name), set isCollapsed to \(!currentState)")
                    }
                Spacer()
            }
            if !(appData.groupCollapsed[group.id] ?? true) {
                ForEach(items.filter { group.itemIds.contains($0.id) }, id: \.id) { item in
                    if group.category == .recommended {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Spacer().frame(width: 40)
                                Button(action: {
                                    print("Item \(item.id) button tapped, isChecked=\(isItemChecked(item: item))")
                                    toggleItemCheck(item: item)
                                    forceRefreshID = UUID()
                                }) {
                                    Image(systemName: isItemChecked(item: item) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(isItemChecked(item: item) ? .secondary : .blue)
                                        .font(.title3)
                                }
                                .disabled(isGroupChecked())
                                Text(itemDisplayText(item: item))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.leading, 8)
                                Spacer()
                            }
                            HStack {
                                Spacer().frame(width: 48)
                                ProgressView(value: min(Double(weeklyCounts[item.id] ?? 0) / 5.0, 1.0))
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .tint((weeklyCounts[item.id] ?? 0) >= 3 ? .green : group.category.progressBarColor)
                                    .frame(height: 5)
                            }
                            HStack {
                                Spacer().frame(width: 48)
                                Text("\(weeklyCounts[item.id] ?? 0)/5 this week")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Spacer().frame(width: 40)
                            Button(action: {
                                print("Item \(item.id) button tapped, isChecked=\(isItemChecked(item: item))")
                                toggleItemCheck(item: item)
                                forceRefreshID = UUID()
                            }) {
                                Image(systemName: isItemChecked(item: item) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isItemChecked(item: item) ? .secondary : .blue)
                                    .font(.title3)
                                }
                                .disabled(isGroupChecked())
                            Text(itemDisplayText(item: item))
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding(.leading, 8)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(isGroupChecked() ? Color.secondary.opacity(0.2) : group.category.backgroundColor)
        .cornerRadius(10)
        .onAppear {
            print("GroupView \(group.name) appeared, weeklyCounts: \(weeklyCounts)")
        }
    }

    private func isGroupChecked() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return items.filter { group.itemIds.contains($0.id) }.allSatisfy { item in
            let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
            return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
    }

    private func isItemChecked(item: Item) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
        return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    private func toggleGroupCheck() {
        let today = Calendar.current.startOfDay(for: Date())
        let isChecked = isGroupChecked()
        if isChecked {
            for item in items.filter({ group.itemIds.contains($0.id) }) {
                if let log = appData.consumptionLog[cycleId]?[item.id]?.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                    appData.removeConsumption(itemId: item.id, cycleId: cycleId, date: log.date)
                }
            }
        } else {
            for item in items.filter({ group.itemIds.contains($0.id) }) {
                if !isItemChecked(item: item) {
                    appData.logConsumption(itemId: item.id, cycleId: cycleId, date: Date())
                }
            }
        }
    }

    private func toggleItemCheck(item: Item) {
        let today = Calendar.current.startOfDay(for: Date())
        let isChecked = isItemChecked(item: item)
        if isChecked {
            if let log = appData.consumptionLog[cycleId]?[item.id]?.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                appData.removeConsumption(itemId: item.id, cycleId: cycleId, date: log.date)
            }
        } else {
            appData.logConsumption(itemId: item.id, cycleId: cycleId, date: Date())
        }
    }

    private func itemDisplayText(item: Item) -> String {
        if let dose = item.dose, let unit = item.unit {
            if dose == 1.0 {
                return "\(item.name) - 1 \(unit)"
            } else if let fraction = Fraction.fractionForDecimal(dose) {
                return "\(item.name) - \(fraction.displayString) \(unit)"
            } else if dose.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(item.name) - \(String(format: "%d", Int(dose))) \(unit)"
            }
            return "\(item.name) - \(String(format: "%.1f", dose)) \(unit)"
        } else if item.category == .treatment, let unit = item.unit {
            let currentWeek = currentWeekNumber()
            if let weeklyDose = item.weeklyDoses?[currentWeek] {
                if weeklyDose == 1.0 {
                    return "\(item.name) - 1 \(unit) (Week \(currentWeek))"
                } else if let fraction = Fraction.fractionForDecimal(weeklyDose) {
                    return "\(item.name) - \(fraction.displayString) \(unit) (Week \(currentWeek))"
                } else if weeklyDose.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(item.name) - \(String(format: "%d", Int(weeklyDose))) \(unit) (Week \(currentWeek))"
                }
                return "\(item.name) - \(String(format: "%.1f", weeklyDose)) \(unit) (Week \(currentWeek))"
            } else if let firstWeek = item.weeklyDoses?.keys.min(), let firstDose = item.weeklyDoses?[firstWeek] {
                if firstDose == 1.0 {
                    return "\(item.name) - 1 \(unit) (Week \(firstWeek))"
                } else if let fraction = Fraction.fractionForDecimal(firstDose) {
                    return "\(item.name) - \(fraction.displayString) \(unit) (Week \(firstWeek))"
                } else if firstDose.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(item.name) - \(String(format: "%d", Int(firstDose))) \(unit) (Week \(firstWeek))"
                }
                return "\(item.name) - \(String(format: "%.1f", firstDose)) \(unit) (Week \(firstWeek))"
            }
        }
        return item.name
    }

    private func currentWeekNumber() -> Int {
        guard let cycle = appData.cycles.first(where: { $0.id == cycleId }) else { return 1 }
        let calendar = Calendar.current
        let daysSinceStart = calendar.dateComponents([.day], from: cycle.startDate, to: Date()).day ?? 0
        return (daysSinceStart / 7) + 1
    }
}

// Add this custom RefreshableScrollView component
struct RefreshableScrollView<Content: View>: View {
    @State private var previousScrollOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var frozen: Bool = false
    @State private var rotation: Angle = .degrees(0)
    
    var threshold: CGFloat = 80
    let onRefresh: (@escaping () -> Void) -> Void
    let content: Content

    init(onRefresh: @escaping (@escaping () -> Void) -> Void, @ViewBuilder content: () -> Content) {
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { outerGeometry in
            ScrollView {
                ZStack(alignment: .top) {
                    MovingView()
                    
                    VStack {
                        self.content
                            .alignmentGuide(.top, computeValue: { d in
                                (self.scrollOffset >= self.threshold && self.frozen) ? -self.threshold : 0
                            })
                    }
                    
                    SymbolView(height: self.threshold, loading: self.frozen, rotation: self.rotation)
                        .offset(y: min(self.scrollOffset, 0))
                }
                .background(FixedView(scrollOffset: $scrollOffset))
            }
            .onChange(of: scrollOffset) { newValue in
                // Crossing the threshold on the way down, we start the refresh process
                if !self.frozen && self.previousScrollOffset > self.threshold && self.scrollOffset <= self.threshold {
                    self.frozen = true
                    self.rotation = .degrees(0)
                    
                    DispatchQueue.main.async {
                        withAnimation(.linear(duration: 0.3)) {
                            self.rotation = .degrees(720)
                        }
                        self.onRefresh {
                            withAnimation {
                                self.frozen = false
                            }
                        }
                    }
                }
                
                self.previousScrollOffset = self.scrollOffset
            }
        }
    }
    
    struct FixedView: View {
        @Binding var scrollOffset: CGFloat
        
        var body: some View {
            GeometryReader { geometry in
                Color.clear.preference(key: OffsetPreferenceKey.self, value: geometry.frame(in: .global).minY)
                    .onPreferenceChange(OffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }
            }
        }
    }
    
    struct MovingView: View {
        var body: some View {
            GeometryReader { geometry in
                Color.clear
            }
        }
    }
    
    struct SymbolView: View {
        var height: CGFloat
        var loading: Bool
        var rotation: Angle
        
        var body: some View {
            Group {
                if loading {
                    VStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: height * 0.25, height: height * 0.25)
                            .rotationEffect(rotation)
                            .foregroundColor(.secondary)
                        Spacer()
                    }.frame(height: height)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "arrow.down")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: height * 0.25, height: height * 0.25)
                            .foregroundColor(.secondary)
                        Spacer()
                    }.frame(height: height)
                }
            }
        }
    }
}

// Define the OffsetPreferenceKey outside of the RefreshableScrollView to avoid the static property error
struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

import SwiftUI
import UserNotifications
import AVFoundation
import AudioToolbox
import FirebaseAuth

struct ContentView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var treatmentCountdown: TimeInterval?
    @State private var showingSetupWizard = false
    @State private var showingCycleEndPopup = false
    @State private var notificationPermissionDenied = false
    @State private var isInitialSetupActive = false
    @State private var isNewCycleSetupActive = false
    @State private var showingSyncError = false
    @State private var treatmentTimerId: String?
    @State private var forceRefreshID = UUID()
    @State private var showingTimerAlert = false
    @State private var recommendedWeeklyCounts: [UUID: Int] = [:]
    @State private var isRefreshing = false
    @State private var refreshId = UUID()
    @State private var isLoggedIn: Bool = UserDefaults.standard.string(forKey: "currentUserId") != nil
    
    init(appData: AppData) {
        self.appData = appData
        
        // Check setup state
        _isInitialSetupActive = State(initialValue: !UserDefaults.standard.bool(forKey: "hasCompletedSetup"))
    }
    
    var body: some View {
        ZStack {
            switch authViewModel.authState {
            case .loading:
                // Loading state
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
                    
            case .signedOut:
                // User is not authenticated
                LoginView()
                    .environmentObject(authViewModel)
                    
            case .signedIn:
                // User is authenticated, show main app content
                mainAppContentView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserDidSignOut"))) { _ in
            authViewModel.signOut()
        }
    }
    
    private func mainContentView() -> some View {
        VStack {
            headerView()
            if appData.isLoading {
                ProgressView("Loading data from server...")
                    .padding()
            } else if appData.cycles.isEmpty && appData.roomCode != nil && appData.syncError == nil {
                ProgressView("Loading your plan...")
                    .padding()
            } else {
                categoriesScrollView()
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarHidden(true)
        .alert(isPresented: $showingSyncError) {
            Alert(
                title: Text("Sync Error"),
                message: Text(appData.syncError ?? "Unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Time for the next treatment food", isPresented: $showingTimerAlert) {
            Button("OK") {
                AudioPlayer.stopAlarmSound()
                stopTreatmentTimer()
            }
            Button("Snooze for 5 min") {
                AudioPlayer.stopAlarmSound()
                appData.snoozeTreatmentTimer(duration: 300)
                treatmentTimerId = "treatment_timer_\(UUID().uuidString)"
                appData.treatmentTimerId = treatmentTimerId
                scheduleNotification(duration: 300)
            }
        }
        .onAppear {
            updateRecommendedItemCounts()
        }
    }
    
    
    private func mainAppContentView() -> some View {
        Group {
            if isInitialSetupActive || showingSetupWizard {
                NavigationView {
                    setupWizardSheet()
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else if appData.currentUser != nil && (appData.currentRoomId != nil || appData.roomCode != nil) {
                mainTabView()
            } else {
                NavigationView {
                    InitialSetupView(appData: appData, isInitialSetupActive: $isInitialSetupActive)
                        .environmentObject(authViewModel)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
    
    private func mainTabView() -> some View {
        TabView {
            NavigationView {
                mainContentView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            .onAppear {
                updateRecommendedItemCounts()
            }

            NavigationView {
                WeekView(appData: appData)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "calendar")
                Text("Week")
            }

            NavigationView {
                HistoryView(appData: appData)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "clock.arrow.circlepath")
                Text("History")
            }

            NavigationView {
                SettingsView(appData: appData)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }
        }
        .onReceive(timer) { _ in updateTreatmentCountdown() }
        .onAppear(perform: onAppearActions)
        .onChange(of: appData.cycles) { _ in checkCycleEnd() }
        .onChange(of: appData.currentUser) { _ in checkCycleEnd() }
        .onChange(of: appData.consumptionLog) { _ in handleConsumptionLogChange() }
        .onChange(of: appData.treatmentTimer) { newValue in
            if let timer = newValue, timer.isActive, timer.endTime > Date() {
                resumeTreatmentTimer()
            } else {
                stopTreatmentTimer()
            }
        }
        .sheet(isPresented: $showingSetupWizard) { setupWizardSheet() }
        .sheet(isPresented: $showingCycleEndPopup, onDismiss: handleCycleEndDismiss) { cycleEndPopup() }
    }

    // Add this new function to update recommended item counts
    private func updateRecommendedItemCounts() {
        if let cycleId = appData.currentCycleId() {
            let (weekStart, weekEnd) = currentWeekRange()
            let items = currentItems().filter { $0.category == .recommended }
            recommendedWeeklyCounts = items.reduce(into: [UUID: Int]()) { result, item in
                let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
                result[item.id] = logs.filter { $0.date >= weekStart && $0.date <= weekEnd }.count
                print("Updated weekly count for item \(item.id) (\(item.name)): \(result[item.id] ?? 0)")
            }
            print("Manually updated recommendedWeeklyCounts: \(recommendedWeeklyCounts)")
        }
    }

    private func headerView() -> some View {
        VStack {
            HStack(alignment: .center) {
                if let cycleId = appData.currentCycleId(),
                   let profileImage = appData.loadProfileImage(forCycleId: cycleId) {
                    Image(uiImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)  // Increased from 40x40 to 70x70
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 70, height: 70)  // Increased from 40x40 to 70x70
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentPatientName())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    let (cycle, week, day) = currentWeekAndDay()
                    Text("Cycle \(cycle) • Week \(week) • Day \(day)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)  // Added vertical padding to accommodate larger image
            
            if notificationPermissionDenied {
                Text("Notifications are disabled. Go to iOS Settings > Notifications > TIPs App to enable them.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .padding(.top)
    }
    private func categoriesScrollView() -> some View {
        ScrollView {
            // Pull-to-refresh indicator at the top of the ScrollView
            PullToRefresh(coordinateSpaceName: "pullToRefresh", onRefresh: {
                // Perform refresh operations
                updateRecommendedItemCounts()
                // Force UI update
                forceRefreshID = UUID()
                // Small delay for animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isRefreshing = false
                }
            }, isRefreshing: $isRefreshing)
            
            // Your actual content
            LazyVStack(spacing: 12) {
                categorySection(for: .medicine)
                categorySection(for: .maintenance)
                treatmentCategorySection()
                categorySection(for: .recommended)
            }
            .padding(.bottom, 60)
            .id(forceRefreshID) // Ensure the view refreshes
        }
        .coordinateSpace(name: "pullToRefresh")
    }

    private func setupWizardSheet() -> some View {
        Group {
            if isNewCycleSetupActive {
                NewCycleSetupView(appData: appData, isNewCycleSetupActive: $isNewCycleSetupActive)
                    .navigationBarTitleDisplayMode(.inline)
                    .environmentObject(authViewModel)
            } else {
                InitialSetupView(appData: appData, isInitialSetupActive: $isInitialSetupActive)
                    .environmentObject(authViewModel)
            }
        }
    }

    private func cycleEndPopup() -> some View {
        // Keep your existing implementation
        VStack(spacing: 20) {
            Text("Your current cycle has ended. Would you like to set up a new cycle?")
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding()
            HStack(spacing: 20) {
                Button("Yes") {
                    print("User chose to start new cycle")
                    showingCycleEndPopup = false
                    isNewCycleSetupActive = true
                    showingSetupWizard = true
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Not Now") {
                    print("User dismissed cycle end popup")
                    showingCycleEndPopup = false
                    showingSetupWizard = false
                }
                .padding()
                .background(Color.secondary)
                .foregroundColor(.primary)
                .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    func categorySection(for category: Category) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Image(systemName: category.icon)
                        .foregroundColor(category.iconColor)
                        .font(.title3)
                    Text(category.rawValue)
                        .font(.headline)
                        .bold()
                        .foregroundColor(.primary)
                    Spacer()
                    TimeOfDayTag(text: timeOfDay(for: category), color: category.iconColor)
                }
                if !isCollapsed(category) {
                    let cycleId = appData.currentCycleId() ?? UUID()
                    let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == category }
                    let items = currentItems().filter { $0.category == category }

                    ForEach(groups, id: \ .id) { group in
                        GroupView(appData: appData, group: group, cycleId: cycleId, items: items, weeklyCounts: recommendedWeeklyCounts, forceRefreshID: $forceRefreshID)
                    }

                    let standaloneItems = items.filter { item in
                        !groups.contains(where: { $0.itemIds.contains(item.id) })
                    }
                    ForEach(standaloneItems, id: \ .id) { item in
                        if category == .recommended {
                            recommendedItemRow(item: item, weeklyCount: recommendedWeeklyCounts[item.id] ?? 0, isGroupItem: false, groupChecked: false)
                        } else {
                            itemRow(item: item, category: category, isGroupItem: false, groupChecked: false)
                        }
                    }
                }
            }
            .cardStyle()
        }
    }

    func treatmentCategorySection() -> some View {
        treatmentCategoryView()
    }



    func categoryView(for category: Category) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.iconColor)
                    .font(.title3)
                Text(category.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                TimeOfDayTag(text: timeOfDay(for: category), color: category.iconColor)
            }
            .padding(.top, 10)
            if !isCollapsed(category) {
                let cycleId = appData.currentCycleId() ?? UUID()
                let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == category }
                let items = currentItems().filter { $0.category == category }

                ForEach(groups, id: \.id) { group in
                    GroupView(appData: appData, group: group, cycleId: cycleId, items: items, weeklyCounts: recommendedWeeklyCounts, forceRefreshID: $forceRefreshID)
                }
                let standaloneItems = items.filter { item in
                    !groups.contains(where: { $0.itemIds.contains(item.id) })
                }
                if standaloneItems.isEmpty && groups.isEmpty {
                    Text("No items added")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(standaloneItems, id: \.id) { item in
                        if category == .recommended {
                            recommendedItemRow(item: item, weeklyCount: recommendedWeeklyCounts[item.id] ?? 0, isGroupItem: false, groupChecked: false)
                        } else {
                            itemRow(item: item, category: category, isGroupItem: false, groupChecked: false)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { toggleCollapse(category) }
    }

    func treatmentCategoryView() -> some View {
        let cycleId = appData.currentCycleId() ?? UUID()
        let (weekStart, weekEnd) = currentWeekRange()
        let items = currentItems().filter { $0.category == .treatment }
        let weeklyCounts = items.reduce(into: [UUID: Int]()) { result, item in
            let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
            result[item.id] = logs.filter { $0.date >= weekStart && $0.date <= weekEnd }.count
        }
        
        // Check if there are any unlogged treatment items
        let today = Calendar.current.startOfDay(for: Date())
        let hasUnloggedItems = items.contains { item in
            let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
            return !logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
        
        // Get the duration from user settings or use default
        let timerDuration = appData.currentUser?.treatmentTimerDuration ?? 900
        
        return VStack(alignment: .leading) {
            HStack {
                Image(systemName: Category.treatment.icon)
                    .foregroundColor(Category.treatment.iconColor)
                    .font(.title3)
                Text(Category.treatment.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("Evening")
                    .timeOfDayTagStyle(color: Category.treatment.iconColor)
            }
            .padding(.bottom, 4)

            // Show timer ONLY if there's an active countdown AND unlogged items
            if hasUnloggedItems, let countdown = treatmentCountdown, countdown > 0 {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundColor(.purple)
                        Text(formattedTimeRemaining(countdown))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                    
                    ProgressView(value: 1.0 - (countdown / timerDuration))
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(.purple)
                        .frame(height: 6)
                        .padding(.horizontal)

                    Text("Treatment in Progress")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(12)
            }

            let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == .treatment }
            ForEach(groups, id: \.id) { group in
                GroupView(appData: appData, group: group, cycleId: cycleId, items: items, weeklyCounts: weeklyCounts, forceRefreshID: $forceRefreshID)
            }

            let standaloneItems = items.filter { item in
                !groups.contains(where: { $0.itemIds.contains(item.id) })
            }

            if standaloneItems.isEmpty && groups.isEmpty {
                Text("No items added")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(standaloneItems, id: \.id) { item in
                    itemRow(item: item, category: .treatment, isGroupItem: false, groupChecked: false)
                }
            }
        }
        .cardStyle()
    }

    func headerView(for category: Category) -> some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundColor(category.iconColor)
                .font(.title3)
            Text(category.rawValue)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Text(timeOfDay(for: category))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 10)
    }

    func standaloneItemsView(items: [Item], groups: [GroupedItem]) -> some View {
        let standaloneItems = items.filter { item in
            !groups.contains(where: { $0.itemIds.contains(item.id) })
        }
        return Group {
            if standaloneItems.isEmpty && groups.isEmpty {
                Text("No items added")
                    .foregroundColor(.secondary)
            } else {
                ForEach(standaloneItems, id: \.id) { item in
                    itemRow(item: item, category: .treatment, isGroupItem: false, groupChecked: false)
                }
            }
        }
    }

    func itemRow(item: Item, category: Category, isGroupItem: Bool, groupChecked: Bool) -> some View {
        HStack {
            if !isGroupItem {
                Spacer().frame(width: 20)
            }
            Button(action: { toggleCheck(item: item) }) {
                Image(systemName: isItemCheckedToday(item) ? "checkmark.square.fill" : "square")
                    .foregroundColor(isItemCheckedToday(item) ? .secondary : .blue)
                    .font(.title3)
                    .accessibilityLabel(isItemCheckedToday(item) ? "Checked" : "Unchecked")
            }
            .disabled(isGroupItem && groupChecked)
            Text(itemDisplayText(item: item))
                .font(.body)
                .foregroundColor(.primary)
                .padding(.leading, 8)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    func recommendedItemRow(item: Item, weeklyCount: Int, isGroupItem: Bool, groupChecked: Bool) -> some View {
        @State var animatedColor: Color = weeklyCount >= 3 ? .green : Category.recommended.progressBarColor

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !isGroupItem {
                    Spacer().frame(width: 20)
                }
                Button(action: { toggleCheck(item: item) }) {
                    Image(systemName: isItemCheckedToday(item) ? "checkmark.square.fill" : "square")
                        .foregroundColor(isItemCheckedToday(item) ? .secondary : .blue)
                        .font(.title3)
                        .accessibilityLabel(isItemCheckedToday(item) ? "Checked" : "Unchecked")
                }
                .disabled(isGroupItem && groupChecked)
                Text(itemDisplayText(item: item))
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.leading, 8)
                Spacer()
            }

            ProgressView(value: min(Double(weeklyCount) / 5.0, 1.0))
                .progressViewStyle(LinearProgressViewStyle())
                .tint(animatedColor)
                .frame(height: 5)
                .onChange(of: weeklyCount) { newValue in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        animatedColor = newValue >= 3 ? .green : Category.recommended.progressBarColor
                    }
                }

            Text("\(weeklyCount)/5 this week")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            animatedColor = weeklyCount >= 3 ? .green : Category.recommended.progressBarColor
        }
    }


    func checkCycleEnd() {
        if isInitialSetupActive || isNewCycleSetupActive || showingSetupWizard { return }
        guard let lastCycle = appData.cycles.last else { return }
        let foodChallengeDate = lastCycle.foodChallengeDate
        let today = Calendar.current.startOfDay(for: Date())
        let isPastDue = Calendar.current.isDate(foodChallengeDate, equalTo: today, toGranularity: .day) || foodChallengeDate < today
        if appData.currentUser?.isAdmin == true && isPastDue && !showingCycleEndPopup {
            showingCycleEndPopup = true
            showingSetupWizard = false
        } else if !isPastDue {
            showingCycleEndPopup = false
        }
    }

    // In ContentView's onAppearActions or similar initialization code
    func checkSetupNeeded() {
        let hasCompletedSetup = UserDefaults.standard.bool(forKey: "hasCompletedSetup")
        print("checkSetupNeeded: hasCompletedSetup = \(hasCompletedSetup)")
        isInitialSetupActive = !hasCompletedSetup
    }

    func isCollapsed(_ category: Category) -> Bool {
        appData.categoryCollapsed[category.rawValue] ?? isCategoryComplete(category)
    }

    func toggleCollapse(_ category: Category) {
        appData.setCategoryCollapsed(category, isCollapsed: !isCollapsed(category))
    }

    func currentCycleNumber() -> Int {
        appData.cycles.last?.number ?? 0
    }

    func currentPatientName() -> String {
        appData.cycles.last?.patientName ?? "TIPs"
    }

    func isCategoryComplete(_ category: Category) -> Bool {
        let items = currentItems().filter { $0.category == category }
        return !items.isEmpty && items.allSatisfy { isItemCheckedToday($0) }
    }

    func isItemCheckedToday(_ item: Item) -> Bool {
        // Determine the appropriate cycle ID for this date
        let today = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        
        // First check if we're in an active cycle
        for cycle in appData.cycles {
            let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
            let cycleEndDay = calendar.startOfDay(for: cycle.foodChallengeDate)
            
            if todayStart >= cycleStartDay && todayStart <= cycleEndDay {
                // We're in an active cycle
                let logs = appData.consumptionLog[cycle.id]?[item.id] ?? []
                let isChecked = logs.contains { log in
                    let logDay = calendar.startOfDay(for: log.date)
                    return logDay == todayStart
                }
                return isChecked
            }
        }
        
        // If we're between cycles, find the most recent cycle
        let mostRecentCycle = appData.cycles.filter {
            calendar.startOfDay(for: $0.startDate) <= todayStart
        }.max(by: {
            $0.startDate < $1.startDate
        })
        
        if let cycleId = mostRecentCycle?.id {
            let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
            let isChecked = logs.contains { log in
                let logDay = calendar.startOfDay(for: log.date)
                return logDay == todayStart
            }
            print("Between cycles check for item \(item.id) on \(todayStart) in cycle \(cycleId) = \(isChecked)")
            return isChecked
        }
        
        return false
    }

    func isGroupCheckedToday(_ group: GroupedItem) -> Bool {
        guard let cycleId = appData.currentCycleId() else { return false }
        let items = currentItems().filter { group.itemIds.contains($0.id) }
        return items.allSatisfy { isItemCheckedToday($0) }
    }

    func weeklyDoseCount(for item: Item) -> Int {
        guard let cycleId = appData.currentCycleId() else { return 0 }
        let (weekStart, weekEnd) = currentWeekRange()
        return appData.consumptionLog[cycleId]?[item.id]?.filter { $0.date >= weekStart && $0.date <= weekEnd }.count ?? 0
    }

    func currentWeekRange() -> (start: Date, end: Date) {
        guard let cycle = appData.cycles.last else {
            let now = Date()
            let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
            let weekEndEndOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd)!
            print("No cycle, week range: \(weekStart) to \(weekEndEndOfDay)")
            return (weekStart, weekEndEndOfDay)
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
        let currentWeekOffset = (daysSinceStart / 7)
        let weekStart = calendar.date(byAdding: .day, value: currentWeekOffset * 7, to: cycleStartDay)!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let weekEndEndOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd)!
        print("Cycle start: \(cycle.startDate), today: \(today), week range: \(weekStart) to \(weekEndEndOfDay), local timezone: \(TimeZone.current.identifier)")
        return (weekStart, weekEndEndOfDay)
    }

    func progressBarColor(for count: Int) -> Color {
        switch count {
        case 0..<3: return .blue
        case 3...5: return .green
        default: return .red
        }
    }

    func toggleCheck(item: Item) {
        // Determine the appropriate cycle ID for this date
        let today = Date()
        let currentCycleId: UUID?
        
        // If today is within a cycle's date range, use that cycle
        if let activeCycle = appData.cycles.first(where: { cycle in
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: today)
            let cycleStart = calendar.startOfDay(for: cycle.startDate)
            let cycleEnd = calendar.startOfDay(for: cycle.foodChallengeDate)
            return todayStart >= cycleStart && todayStart <= cycleEnd
        }) {
            currentCycleId = activeCycle.id
        } else {
            // For days between cycles, use the most recent cycle
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: today)
            
            currentCycleId = appData.cycles.filter {
                calendar.startOfDay(for: $0.startDate) <= todayStart
            }.max(by: {
                $0.startDate < $1.startDate
            })?.id
        }
        
        guard let cycleId = currentCycleId else {
            print("No cycle ID available, skipping toggleCheck for item \(item.id)")
            return
        }
        
        let isChecked = isItemCheckedToday(item)
        
        print("!!! DEBUG: toggleCheck CALLED for item \(item.id) (\(item.name)), isChecked: \(isChecked) !!!")
        
        if isChecked {
            // Unchecking an item
            if let log = appData.consumptionLog[cycleId]?[item.id]?.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                appData.removeConsumption(itemId: item.id, cycleId: cycleId, date: log.date)
                print("Unchecked item \(item.id), log removed for \(log.date)")
            }
            
            // When unchecking a treatment item, we do NOT start a timer
            // We only check if we need to stop a timer if this was the last logged item
            if item.category == .treatment {
                DispatchQueue.main.async {
                    // Check if timer should be stopped (if this was the last logged item)
                    let treatmentItems = self.currentItems().filter { $0.category == .treatment }
                    let checkedTreatmentItems = treatmentItems.filter { self.isItemCheckedToday($0) }
                    
                    // If there are no checked items left after unchecking, stop the timer
                    // This would happen if this was the only checked item
                    if checkedTreatmentItems.isEmpty {
                        print("Unchecked the last checked treatment item, stopping timer")
                        self.stopTreatmentTimer()
                    } else {
                        // Otherwise, we leave the timer state unchanged
                        print("Unchecked treatment item, but other items remain checked, leaving timer as is")
                    }
                }
            }
        } else {
            // Checking an item
            appData.logConsumption(itemId: item.id, cycleId: cycleId)
            print("Logged item \(item.id) for today in cycle \(cycleId)")
            
            if item.category == .treatment {
                DispatchQueue.main.async {
                    let treatmentItems = self.currentItems().filter { $0.category == .treatment }
                    let unloggedTreatmentItems = treatmentItems.filter { !self.isItemCheckedToday($0) }
                    
                    if unloggedTreatmentItems.isEmpty {
                        // This was the last treatment item, so stop timer
                        print("!!! DEBUG: Checked last treatment item \(item.id), STOPPING timer as no items remain !!!")
                        self.stopTreatmentTimer()
                    } else {
                        // There are still unlogged items, so start/continue timer
                        print("!!! DEBUG: Checking treatment item \(item.id), STARTING timer as \(unloggedTreatmentItems.count) items remain unlogged !!!")
                        self.startTreatmentTimer()
                    }
                }
            }
        }
        
        if let category = Category(rawValue: item.category.rawValue) {
            appData.setCategoryCollapsed(category, isCollapsed: isCategoryComplete(category))
        }
        forceRefreshID = UUID()
        appData.objectWillChange.send()
    }
    
    func startTreatmentTimer() {
        // Check if all treatment items are already logged
        if isCategoryComplete(.treatment) {
            stopTreatmentTimer()
            return
        }

        let now = Date()
        let duration = appData.currentUser?.treatmentTimerDuration ?? 900
        let endDate = now.addingTimeInterval(duration)
        
        stopTreatmentTimer() // Clear old timers before starting new one

        let notificationId = "treatment_timer_\(UUID().uuidString)"
        treatmentTimerId = notificationId
        appData.treatmentTimerId = notificationId
        
        // Set the countdown value directly (don't rely on appData.startTreatmentTimer)
        treatmentCountdown = duration
        
        // Only start the actual timer in AppData if notifications are enabled
        // This avoids the flickering issue with the timer display
        if appData.currentUser?.treatmentFoodTimerEnabled ?? false {
            appData.startTreatmentTimer(duration: duration)
            print("Starting timer with notifications, endDate: \(endDate), id: \(notificationId), duration: \(duration)")
            scheduleNotification(duration: duration)
        } else {
            print("Starting timer without notifications, endDate: \(endDate), id: \(notificationId), duration: \(duration)")
        }
    }

    func resumeTreatmentTimer() {
        guard let timer = appData.treatmentTimer, timer.isActive, timer.endTime > Date() else {
            print("No valid timer to resume")
            stopTreatmentTimer()
            return
        }
        
        let remaining = max(timer.endTime.timeIntervalSinceNow, 0)
        treatmentCountdown = remaining
        treatmentTimerId = appData.treatmentTimerId ?? "treatment_timer_\(UUID().uuidString)"
        appData.treatmentTimerId = treatmentTimerId
        
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                if let timerId = self.treatmentTimerId, !requests.contains(where: { $0.identifier.hasPrefix(timerId) }) {
                    print("Rescheduling notification, remaining: \(remaining)")
                    self.scheduleNotification(duration: remaining)
                }
            }
        }
    }
    func stopTreatmentTimer() {
        treatmentCountdown = nil
        showingTimerAlert = false

        if let timerId = treatmentTimerId {
            let notificationIds = (0..<4).map { "\(timerId)_repeat_\($0)" }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIds)
            print("Stopped timer and canceled notifications with IDs: \(notificationIds)")
        }

        treatmentTimerId = nil
        appData.setTreatmentTimerEnd(nil)
        appData.stopTreatmentTimer()
        appData.treatmentTimerId = nil
    }

    func handleConsumptionLogChange() {
        // Update treatment timer logic if enabled
        if appData.currentUser?.treatmentFoodTimerEnabled ?? false {
            let wasComplete = isCategoryComplete(.treatment)
            appData.setCategoryCollapsed(.treatment, isCollapsed: isCategoryComplete(.treatment))
            let isCompleteNow = isCategoryComplete(.treatment)
            if wasComplete && !isCompleteNow {
                print("Consumption changed, treatment incomplete, starting timer")
                startTreatmentTimer()
            } else if !wasComplete && isCompleteNow {
                print("Consumption changed, treatment complete, stopping timer")
                stopTreatmentTimer()
            }
        }

        // Always update recommendedWeeklyCounts, regardless of timer state
        if let cycleId = appData.currentCycleId() {
            let (weekStart, weekEnd) = currentWeekRange()
            let items = currentItems().filter { $0.category == .recommended }
            recommendedWeeklyCounts = items.reduce(into: [UUID: Int]()) { result, item in
                let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
                result[item.id] = logs.filter { $0.date >= weekStart && $0.date <= weekEnd }.count
                print("Recomputed weekly count for item \(item.id) (\(item.name)): \(result[item.id] ?? 0), logs: \(logs.map { $0.date })")
            }
            print("Consumption log changed, updated recommendedWeeklyCounts: \(recommendedWeeklyCounts)")
        }

        // Trigger UI refresh
        appData.objectWillChange.send()
        forceRefreshID = UUID()
    }

    func updateTreatmentCountdown() {
        // If notifications are enabled, use the timer from AppData
        if appData.currentUser?.treatmentFoodTimerEnabled ?? false {
            treatmentCountdown = appData.checkTimerStatus()
            
            // If timer just expired, show alert
            if let remaining = treatmentCountdown, remaining <= 1 && !showingTimerAlert && !isCategoryComplete(.treatment) {
                print("Timer expired, triggering alert")
                AudioPlayer.playAlarmSound()
                showingTimerAlert = true
            }
        } else if let countdown = treatmentCountdown {
            // If notifications are disabled but we have a countdown, decrement it manually
            treatmentCountdown = max(0, countdown - 1)
        }
        
        // Check if we need to stop/clear the timer when all items are logged
        if treatmentCountdown != nil && isCategoryComplete(.treatment) {
            treatmentCountdown = nil
        }
    }

    func handleTimerEndChange(_ newValue: Date?) {
        updateTreatmentCountdown()
        if let newEndDate = newValue, newEndDate > Date() {
            print("treatmentTimerEnd changed, resuming: \(newEndDate)")
            resumeTreatmentTimer()
        } else {
            print("treatmentTimerEnd cleared or expired: \(String(describing: newValue))")
            stopTreatmentTimer()
        }
    }

    private func handleSetupWizardChange(_ newValue: Bool) {
        if !newValue {
            print("Setup wizard dismissed, resetting states")
            isInitialSetupActive = false
            showingSetupWizard = false
            isNewCycleSetupActive = false
            UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkCycleEnd()
            }
        }
    }

    private func handleCycleEndDismiss() {
        if !isNewCycleSetupActive && !showingSetupWizard {
            showingCycleEndPopup = false
        }
    }

    func onAppearActions() {
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            isInitialSetupActive = true
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
        
        // Handle authentication state
        if authViewModel.authState == .signedIn, let authUser = authViewModel.currentUser {
            // Check if we need to link Firebase auth user with app user
            if appData.currentUser == nil {
                createUserFromAuth(authUser: authUser)
            }
        }
        
        initializeCollapsedState()
        checkSetupNeeded()
        checkNotificationPermissions()
        appData.checkAndResetIfNeeded()
        showingSyncError = appData.syncError != nil
        
        // Listen for sign out notifications
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UserDidSignOut"),
            object: nil,
            queue: .main
        ) { _ in
            isLoggedIn = false
            // Force app to show authentication view
            appData.currentUser = nil
            appData.currentRoomId = nil
        }

        if let cycleId = appData.currentCycleId() {
            let (weekStart, weekEnd) = currentWeekRange()
            let items = currentItems().filter { $0.category == .recommended }
            recommendedWeeklyCounts = items.reduce(into: [UUID: Int]()) { result, item in
                let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
                result[item.id] = logs.filter { $0.date >= weekStart && $0.date <= weekEnd }.count
            }
        }

        // Check for active timer and resume it if needed
        if let timer = appData.treatmentTimer, timer.isActive, timer.endTime > Date() {
            resumeTreatmentTimer()
        } else {
            stopTreatmentTimer()
        }
    }

    func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationPermissionDenied = settings.authorizationStatus == .denied
            }
        }
    }

    func formattedTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Function to create a user from Firebase Auth
        private func createUserFromAuth(authUser: AuthUser) {
            let userId = UUID()
            let displayName = authUser.displayName ?? "User"
            
            let newUser = User(
                id: userId,
                name: displayName,
                isAdmin: true
            )
            
            appData.addUser(newUser)
            appData.currentUser = newUser
            UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
            
            // Link user to Firebase Auth
            if let dbRef = appData.valueForDBRef() {
                dbRef.child("auth_mapping").child(authUser.uid).setValue(userId.uuidString)
                dbRef.child("users").child(userId.uuidString).child("authId").setValue(authUser.uid)
            }
            
            // Show initial setup
            isInitialSetupActive = true
        }

    func itemDisplayText(item: Item) -> String {
        if let dose = item.dose, let unit = item.unit {
            if dose == 1.0 {
                return "\(item.name) - 1 \(unit)"
            } else if let fraction = Fraction.fractionForDecimal(dose) {
                return "\(item.name) - \(fraction.displayString) \(unit)"
            } else if dose.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(item.name) - \(String(format: "%d", Int(dose))) \(unit)"
            }
            return "\(item.name) - \(String(format: "%.1f", dose)) \(unit)"
        } else if item.category == .treatment, let unit = item.unit {
            let week = currentWeekAndDay().week
            if let weeklyDose = item.weeklyDoses?[week] {
                if weeklyDose == 1.0 {
                    return "\(item.name) - 1 \(unit) (Week \(week))"
                } else if let fraction = Fraction.fractionForDecimal(weeklyDose) {
                    return "\(item.name) - \(fraction.displayString) \(unit) (Week \(week))"
                } else if weeklyDose.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(item.name) - \(String(format: "%d", Int(weeklyDose))) \(unit) (Week \(week))"
                }
                return "\(item.name) - \(String(format: "%.1f", weeklyDose)) \(unit) (Week \(week))"
            } else if let firstWeek = item.weeklyDoses?.keys.min(), let firstDose = item.weeklyDoses?[firstWeek] {
                if firstDose == 1.0 {
                    return "\(item.name) - 1 \(unit) (Week \(firstWeek))"
                } else if let fraction = Fraction.fractionForDecimal(firstDose) {
                    return "\(item.name) - \(fraction.displayString) \(unit) (Week \(firstWeek))"
                } else if firstDose.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(item.name) - \(String(format: "%d", Int(firstDose))) \(unit) (Week \(firstWeek))"
                }
                return "\(item.name) - \(String(format: "%.1f", firstDose)) \(unit) (Week \(firstWeek))"
            }
        }
        return item.name
    }

    func currentWeekAndDay() -> (cycle: Int, week: Int, day: Int) {
        guard let currentCycle = appData.cycles.last else { return (cycle: 1, week: 1, day: 1) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStartDay = calendar.startOfDay(for: currentCycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
        let week = (daysSinceStart / 7) + 1
        let day = (daysSinceStart % 7) + 1
        print("ContentView week calc: cycle start \(cycleStartDay), today \(today), daysSinceStart \(daysSinceStart), week \(week), day \(day)")
        return (cycle: currentCycle.number, week: week, day: day)
    }

    func initializeCollapsedState() {
        Category.allCases.forEach { category in
            if appData.categoryCollapsed[category.rawValue] == nil {
                appData.setCategoryCollapsed(category, isCollapsed: isCategoryComplete(category))
            }
        }
    }

    func timeOfDay(for category: Category) -> String {
        switch category {
        case .medicine, .maintenance: return "Morning"
        case .treatment: return "Evening"
        case .recommended: return "Anytime"
        }
    }

    func currentItems() -> [Item] {
        guard let cycleId = appData.currentCycleId() else { return [] }
        return (appData.cycleItems[cycleId] ?? []).sorted { $0.order < $1.order }
    }

    private func scheduleNotification(duration: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        let baseId = treatmentTimerId ?? UUID().uuidString

        for i in 0..<4 {
            let content = UNMutableNotificationContent()
            content.title = "Time for the next treatment food"
            content.body = "Your \(Int(duration / 60)) minute treatment food timer has ended."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = "TREATMENT_TIMER"
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "treatment-timer-thread-\(baseId)"

            let delay = max(duration, 1) + Double(i)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: "\(baseId)_repeat_\(i)", content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification repeat \(i): \(error.localizedDescription)")
                } else {
                    print("Scheduled notification repeat \(i) for \(delay)s, id: \(request.identifier)")
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appData: AppData())
            .preferredColorScheme(.dark) // Preview in dark mode
    }
}
// Add this PullToRefresh view structure
struct PullToRefresh: View {
    var coordinateSpaceName: String
    var onRefresh: () -> Void
    @Binding var isRefreshing: Bool
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            if offset > 30 && !isRefreshing {
                Spacer()
                    .onAppear {
                        isRefreshing = true
                        onRefresh()
                    }
            }
            
            HStack {
                Spacer()
                VStack {
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "arrow.down")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                            .rotationEffect(.degrees(offset > 15 ? 180 : 0))
                            .animation(.easeInOut, value: offset > 15)
                            .foregroundColor(.secondary)
                        Text(offset > 15 ? "Release to refresh" : "Pull to refresh")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .frame(height: 40)
            .offset(y: -40 + max(offset, 0))
            .onChange(of: geo.frame(in: .named(coordinateSpaceName)).minY) { value in
                offset = value
            }
        }
        .frame(height: 0)
    }
}


