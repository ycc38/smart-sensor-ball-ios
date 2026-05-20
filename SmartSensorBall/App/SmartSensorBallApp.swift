import SwiftUI

@main
struct SmartSensorBallApp: App {
    @StateObject private var bluetoothManager = SensorBallBluetoothManager()
    @StateObject private var trainingManager = TrainingManager()
    @StateObject private var cloudStore = CloudStore()
    @StateObject private var soundEffectManager = SoundEffectManager()
    @StateObject private var speechCueService = SpeechCueService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
                .environmentObject(trainingManager)
                .environmentObject(cloudStore)
                .environmentObject(soundEffectManager)
                .environmentObject(speechCueService)
                .onAppear {
                    trainingManager.attach(
                        bluetoothManager: bluetoothManager,
                        soundEffectManager: soundEffectManager,
                        speechCueService: speechCueService
                    )
                }
        }
    }
}
