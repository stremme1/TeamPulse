import Foundation
import HealthKit
import Combine

// MARK: - Workout Types

enum WorkoutType: String, CaseIterable, Identifiable {
    case running = "running"
    case cycling = "cycling"
    case functionalStrengthTraining = "functional_strength_training"
    case highIntensityIntervalTraining = "high_intensity_interval_training"
    case mixedCardio = "mixed_cardio"
    case hiking = "hiking"
    case rowing = "rowing"
    case elliptical = "elliptical"
    case yoga = "yoga"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running: return "Run"
        case .cycling: return "Bike"
        case .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .mixedCardio: return "Mixed Cardio"
        case .hiking: return "Hike"
        case .rowing: return "Row"
        case .elliptical: return "Elliptical"
        case .yoga: return "Yoga"
        }
    }

    var hkWorkoutActivityType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .cycling: return .cycling
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .mixedCardio: return .mixedCardio
        case .hiking: return .hiking
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .yoga: return .yoga
        }
    }

    var systemImageName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .functionalStrengthTraining: return "dumbbell.fill"
        case .highIntensityIntervalTraining: return "bolt.heart.fill"
        case .mixedCardio: return "figure.mixed.cardio"
        case .hiking: return "figure.hiking"
        case .rowing: return " rowing.machine"
        case .elliptical: return "figure.elliptical"
        case .yoga: return "figure.yoga"
        }
    }
}

// MARK: - Workout State

enum WorkoutState: Equatable {
    case idle
    case countdown
    case running
    case paused
    case ended
}

// MARK: - Workout Data Point

struct WorkoutDataPoint: Codable {
    let timestamp: String
    let heartRate: Int
    let zone: String
    let calories: Double
    let distance: Double
    let deviceStatus: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case heartRate = "heart_rate"
        case zone
        case calories
        case distance
        case deviceStatus = "device_status"
    }

    static func from(heartRate: Int, calories: Double, distance: Double) -> WorkoutDataPoint {
        let zone = Self.computeZone(heartRate: heartRate)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return WorkoutDataPoint(
            timestamp: formatter.string(from: Date()),
            heartRate: heartRate,
            zone: zone,
            calories: calories,
            distance: distance,
            deviceStatus: "watch"
        )
    }

    private static func computeZone(heartRate: Int) -> String {
        switch heartRate {
        case ..<114: return "zone_1"
        case 114..<133: return "zone_2"
        case 133..<152: return "zone_3"
        case 152..<171: return "zone_4"
        default: return "zone_5"
        }
    }
}

// MARK: - Activity Ring Data

struct ActivityRingData {
    let moveCalories: Double      // calories burned
    let moveGoal: Double          // move goal in kcal
    let exerciseMinutes: Int      // minutes of exercise
    let exerciseGoal: Int         // exercise goal in minutes
    let standHours: Int           // hours stood
    let standGoal: Int            // stand goal in hours

    var moveProgress: Double {
        moveGoal > 0 ? min(1.0, moveCalories / moveGoal) : 0
    }

    var exerciseProgress: Double {
        exerciseGoal > 0 ? min(1.0, Double(exerciseMinutes) / Double(exerciseGoal)) : 0
    }

    var standProgress: Double {
        standGoal > 0 ? min(1.0, Double(standHours) / Double(standGoal)) : 0
    }
}

// MARK: - Workout Manager

final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    // MARK: - Published Properties

    @Published private(set) var workoutState: WorkoutState = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var currentHeartRate: Int = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distance: Double = 0
    @Published private(set) var currentZone: String = "zone_1"
    @Published private(set) var averageHeartRate: Int = 0
    @Published private(set) var maxHeartRate: Int = 0
    @Published private(set) var selectedWorkoutType: WorkoutType = .running
    @Published private(set) var activityRings: ActivityRingData?

    // MARK: - Session Data

    private(set) var sessionId: String = ""
    private(set) var athleteId: String = ""
    private var sessionStartDate: Date?

    // MARK: - HealthKit

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutConfiguration: HKWorkoutConfiguration?

    // MARK: - Data Streaming

    private var dataStreamTimer: Timer?
    private var heartRateSamples: [Int] = []
    private var lastSyncedCalorie: Double = 0
    private var lastSyncedDistance: Double = 0
    private var lastComplicationUpdateSeconds: Int = 0

    // MARK: - Delegates

    private let connectivityManager = WatchConnectivityManager.shared
    private let webSocketClient = WebSocketClient.shared

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw WorkoutError.healthDataNotAvailable
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.activitySummaryType(),
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    // MARK: - Workout Session Control

    func startCountdown(athleteId: String) {
        guard workoutState == .idle else { return }
        workoutState = .countdown
    }

    func startWorkout(athleteId: String) async throws {
        guard workoutState == .idle || workoutState == .countdown else { return }

        // Generate session ID
        sessionId = UUID().uuidString
        self.athleteId = athleteId

        // Configure workout
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = selectedWorkoutType.hkWorkoutActivityType
        configuration.locationType = .outdoor

        // HKWorkoutSession is only supported on physical Watch hardware, not Watch Simulator
        #if targetEnvironment(simulator)
        print("WorkoutManager: Running on Watch Simulator — skipping HKWorkoutSession")
        #else
        // Create workout session
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            throw WorkoutError.cannotCreateSession(error)
        }
        #endif

        workoutBuilder = workoutSession?.associatedWorkoutBuilder()
        workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        // Set delegates
        workoutSession?.delegate = self
        workoutBuilder?.delegate = self

        // Start session
        sessionStartDate = Date()
        try workoutSession?.startActivity(with: sessionStartDate!)

        // Begin collecting data
        let predicate = HKQuery.predicateForSamples(
            withStart: sessionStartDate,
            end: nil,
            options: .strictStartDate
        )

        try await workoutBuilder?.beginCollection(at: sessionStartDate!)

        // Fetch today's activity rings (includes today's workout contribution)
        await fetchTodayActivityRings()

        // Start data streaming timer (simulates real-time polling)
        await MainActor.run {
            startDataStreamTimer()
            workoutState = .running
        }

        // Notify iPhone via WatchConnectivity
        connectivityManager.sendSessionStarted(
            sessionId: sessionId,
            athleteId: athleteId,
            workoutType: selectedWorkoutType.rawValue,
            startDate: sessionStartDate!
        )

        // Connect WebSocket to backend
        await webSocketClient.connect(athleteId: athleteId)
        webSocketClient.subscribe(sessionId: sessionId)
    }

    func pauseWorkout() {
        guard workoutState == .running else { return }
        workoutSession?.pause()
        stopDataStreamTimer()
        workoutState = .paused
        connectivityManager.sendWorkoutPaused(sessionId: sessionId)
    }

    func resumeWorkout() {
        guard workoutState == .paused else { return }
        workoutSession?.resume()
        startDataStreamTimer()
        workoutState = .running
        connectivityManager.sendWorkoutResumed(sessionId: sessionId)
    }

    func endWorkout() async throws {
        guard workoutState == .running || workoutState == .paused else { return }

        workoutState = .ended
        stopDataStreamTimer()

        let endDate = Date()

        // End the HK workout
        try await workoutBuilder?.endCollection(at: endDate)

        let workout = try await workoutBuilder?.finishWorkout()

        // Calculate duration
        let duration = workoutSession?.endDate.map { Int($0.timeIntervalSince(sessionStartDate ?? endDate)) } ?? elapsedSeconds

        // Notify iPhone
        connectivityManager.sendWorkoutEnded(
            sessionId: sessionId,
            athleteId: athleteId,
            endDate: endDate,
            duration: duration,
            totalCalories: activeCalories,
            totalDistance: distance
        )

        // Send final summary to backend
        try await sendWorkoutSummary(
            sessionId: sessionId,
            athleteId: athleteId,
            duration: duration,
            totalCalories: activeCalories,
            totalDistance: distance,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate
        )

        // Disconnect WebSocket
        webSocketClient.disconnect()

        // Reset state
        resetState()
    }

    // MARK: - Data Streaming Timer

    private func startDataStreamTimer() {
        stopDataStreamTimer()
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.streamDataPoint()
            }
        }
    }

    private func stopDataStreamTimer() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }

    private func streamDataPoint() {
        guard workoutState == .running, currentHeartRate > 0 else { return }

        elapsedSeconds += 1

        // Track stats
        heartRateSamples.append(currentHeartRate)
        if heartRateSamples.count > 0 {
            averageHeartRate = heartRateSamples.reduce(0, +) / heartRateSamples.count
        }
        maxHeartRate = max(maxHeartRate, currentHeartRate)

        // Compute zone
        currentZone = Self.computeZone(heartRate: currentHeartRate)

        // Build data point
        let dataPoint = WorkoutDataPoint.from(
            heartRate: currentHeartRate,
            calories: activeCalories,
            distance: distance
        )

        // Send via WebSocket to backend
        webSocketClient.sendHeartRateData(
            athleteId: athleteId,
            sessionId: sessionId,
            dataPoint: dataPoint
        )

        // Also sync to iPhone via WatchConnectivity (for guaranteed delivery)
        connectivityManager.sendHeartRateData(
            sessionId: sessionId,
            dataPoint: dataPoint
        )

        // Update complication context every 30 seconds so iPhone gets live data
        if elapsedSeconds - lastComplicationUpdateSeconds >= 30 {
            lastComplicationUpdateSeconds = elapsedSeconds
            connectivityManager.updateComplicationContext(
                sessionId: sessionId,
                athleteId: athleteId,
                workoutType: selectedWorkoutType.rawValue,
                heartRate: currentHeartRate,
                elapsed: elapsedSeconds
            )
        }

        // Refresh activity rings every 60 seconds
        if elapsedSeconds - lastActivityRingFetchSeconds >= 60 {
            lastActivityRingFetchSeconds = elapsedSeconds
            Task {
                await self.fetchTodayActivityRings()
            }
        }
    }

    // MARK: - Heart Rate Zone Calculation

    private static func computeZone(heartRate: Int) -> String {
        switch heartRate {
        case ..<114: return "zone_1"
        case 114..<133: return "zone_2"
        case 133..<152: return "zone_3"
        case 152..<171: return "zone_4"
        default: return "zone_5"
        }
    }

    // MARK: - Activity Ring Data

    func fetchTodayActivityRings() async {
        let calendar = Calendar.current
        let now = Date()
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0
        guard let startDate = calendar.date(from: startComponents) else { return }
        let endDate = now

        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery { [weak self] _, summaries, error in
                guard error == nil, let summaries = summaries, !summaries.isEmpty else {
                    continuation.resume()
                    return
                }

                var moveCal: Double = 0
                var moveGoal: Double = 0
                var exerciseMin: Int = 0
                var exerciseGoal: Int = 0
                var standHr: Int = 0
                var standGoal: Int = 0

                for summary in summaries {
                    moveCal += summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                    moveGoal += summary.activeEnergyGoal.doubleValue(for: .kilocalorie())
                    exerciseMin += Int(summary.appleExerciseTime.doubleValue(for: .minute()))
                    exerciseGoal += Int(summary.appleExerciseGoal.doubleValue(for: .minute()))
                    standHr += Int(summary.appleStandHours.doubleValue(for: .hour()))
                    standGoal += Int(summary.appleStandGoal.doubleValue(for: .hour()))
                }

                let data = ActivityRingData(
                    moveCalories: moveCal,
                    moveGoal: moveGoal,
                    exerciseMinutes: exerciseMin,
                    exerciseGoal: exerciseGoal,
                    standHours: standHr,
                    standGoal: standGoal
                )

                DispatchQueue.main.async {
                    self?.activityRings = data
                }
                continuation.resume()
            }

            query.startDate = startDate
            query.endDate = endDate
            self.healthStore.execute(query)
        }
    }

    private var lastActivityRingFetchSeconds: Int = 0

    private func sendWorkoutSummary(
        sessionId: String,
        athleteId: String,
        duration: Int,
        totalCalories: Double,
        totalDistance: Double,
        averageHeartRate: Int,
        maxHeartRate: Int
    ) async throws {
        guard let url = URL(string: "http://localhost:8000/api/sessions/\(sessionId)/end") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "athlete_id": athleteId,
            "session_id": sessionId,
            "duration_seconds": duration,
            "total_calories": totalCalories,
            "total_distance": totalDistance,
            "avg_hr": averageHeartRate,
            "max_hr": maxHeartRate
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed to send workout summary: \(httpResponse.statusCode)")
        }
    }

    // MARK: - State Reset

    private func resetState() {
        elapsedSeconds = 0
        currentHeartRate = 0
        activeCalories = 0
        distance = 0
        currentZone = "zone_1"
        averageHeartRate = 0
        maxHeartRate = 0
        heartRateSamples = []
        lastSyncedCalorie = 0
        lastSyncedDistance = 0
        lastComplicationUpdateSeconds = 0
        lastActivityRingFetchSeconds = 0
        sessionId = ""
        workoutSession = nil
        workoutBuilder = nil
        workoutConfiguration = nil
        workoutState = .idle
    }

    // MARK: - Workout Type Selection

    func selectWorkoutType(_ type: WorkoutType) {
        guard workoutState == .idle else { return }
        selectedWorkoutType = type
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                if fromState == .paused {
                    workoutState = .running
                    startDataStreamTimer()
                }
            case .paused:
                workoutState = .paused
                stopDataStreamTimer()
            case .ended:
                workoutState = .ended
                stopDataStreamTimer()
            default:
                break
            }
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            print("Workout session failed: \(error.localizedDescription)")
            workoutState = .idle
            stopDataStreamTimer()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events (pause, resume, lap markers, etc.)
    }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            let statistics = workoutBuilder.statistics(for: quantityType)

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                    if let quantity = statistics?.mostRecentQuantity() {
                        let hr = Int(quantity.doubleValue(for: heartRateUnit))
                        self.currentHeartRate = hr
                    }

                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    let energyUnit = HKUnit.kilocalorie()
                    if let quantity = statistics?.sumQuantity() {
                        self.activeCalories = quantity.doubleValue(for: energyUnit)
                    }

                case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
                     HKQuantityType.quantityType(forIdentifier: .distanceCycling):
                    let distanceUnit = HKUnit.meter()
                    if let quantity = statistics?.sumQuantity() {
                        self.distance = quantity.doubleValue(for: distanceUnit)
                    }

                default:
                    break
                }
            }
        }
    }
}

// MARK: - Workout Errors

enum WorkoutError: LocalizedError {
    case healthDataNotAvailable
    case cannotCreateSession(Error)
    case cannotStartWorkout(Error)
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "Health data is not available on this device."
        case .cannotCreateSession(let error):
            return "Cannot create workout session: \(error.localizedDescription)"
        case .cannotStartWorkout(let error):
            return "Cannot start workout: \(error.localizedDescription)"
        case .authorizationDenied:
            return "HealthKit authorization was denied."
        }
    }
}
