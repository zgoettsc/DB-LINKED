import SwiftUI

struct TreatmentFoodTimerView: View {
    @ObservedObject var appData: AppData
    @State private var timerDurationInMinutes: Double
    
    init(appData: AppData) {
        self.appData = appData
        _timerDurationInMinutes = State(initialValue: (appData.currentUser?.treatmentTimerDuration ?? 900) / 60.0)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Treatment Food Timer")) {
                Toggle("Enable Notification", isOn: Binding(
                    get: { appData.currentUser?.treatmentFoodTimerEnabled ?? false },
                    set: { newValue in
                        appData.setTreatmentFoodTimerEnabled(newValue)
                        if !newValue {
                            cancelAllTreatmentTimers()
                        }
                    }
                ))
                
                Slider(
                    value: $timerDurationInMinutes,
                    in: 1...30,
                    step: 1,
                    minimumValueLabel: Text("1 min"),
                    maximumValueLabel: Text("30 min")
                ) {
                    Text("Duration")
                }
                .disabled(!(appData.currentUser?.treatmentFoodTimerEnabled ?? false))
                .onChange(of: timerDurationInMinutes) { newValue in
                    let durationInSeconds = newValue * 60.0
                    appData.setTreatmentTimerDuration(durationInSeconds)
                    print("Slider set duration to: \(durationInSeconds) seconds")
                }
                
                Text("Current Duration: \(Int(timerDurationInMinutes)) minutes")
                    .foregroundColor(.gray)
                
                Text("15 minutes is the recommended time between treatment doses.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Text("When enabled, a notification will be sent after the set duration following each Treatment Food logged, until all are logged for the day.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .navigationTitle("Treatment Food Timer")
    }
    
    func cancelAllTreatmentTimers() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

struct TreatmentFoodTimerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TreatmentFoodTimerView(appData: AppData())
        }
    }
}
