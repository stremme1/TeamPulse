import Foundation
import HealthKit
import Combine

// MARK: - HealthKitManager

final class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()

    // MARK: - Published

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: [String: HKAuthorizationStatus] = [:]

    // Latest recovery metrics
    @Published var latestSleepHours: Double?
    @Published var latestSpO2Avg: Double?
    @Published var latestRestingHR: Int?
    @Published var latestHRVAvg: Int?
    @Published var latestVo2Max: Double?

    // MARK: - HealthKit Store

    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var backgroundDeliveryEnabled = false

    // MARK: - Types to Read

    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []

        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(spo2)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let vo2Max = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            types.insert(vo2Max)
        }
        if let workout = HKObjectType.workoutType() as? HKObjectType {
            types.insert(workout)
        }
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }

        return types
    }()

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
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)

        await MainActor.run {
            isAuthorized = true
            updateAuthorizationStatus()
        }

        // Enable background delivery
        try await enableBackgroundDelivery()
    }

    private func updateAuthorizationStatus() {
        for type in readTypes {
            let status = healthStore.authorizationStatus(for: type)
            let key = type.identifier
            authorizationStatus[key] = status
        }
    }

    // MARK: - Background Delivery

    private func enableBackgroundDelivery() async throws {
        guard !backgroundDeliveryEnabled else { return }

        for type in readTypes {
            guard let sampleType = type as? HKSampleType else { continue }

            try await healthStore.enableBackgroundDelivery(
                for: sampleType,
                frequency: .immediate
            )
        }

        backgroundDeliveryEnabled = true
        setupObserverQueries()
    }

    private func setupObserverQueries() {
        // Observer queries fire when new health data arrives
        for type in readTypes {
            guard let sampleType = type as? HKSampleType else { continue }

            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                if let error = error {
                    print("HKObserverQuery error: \(error.localizedDescription)")
                    completionHandler()
                    return
                }

                // New data arrived — sync it
                self?.syncNewData(for: type)

                completionHandler()
            }

            healthStore.execute(query)
            observerQueries.append(query)
        }
    }

    private func syncNewData(for type: HKObjectType) {
        guard let quantityType = type as? HKQuantityType else { return }

        switch quantityType.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            Task { await fetchLatestHeartRate() }
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            Task { await fetchLatestHRV() }
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            Task { await fetchLatestRestingHR() }
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            Task { await fetchLatestSpO2() }
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            Task { await fetchLatestVo2Max() }
        default:
            break
        }
    }

    // MARK: - Fetch Latest Metrics

    func fetchLatestHeartRate() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestRestingHR = Int(metric)
            }
        }
    }

    func fetchLatestHRV() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestHRVAvg = Int(metric)
            }
        }
    }

    func fetchLatestRestingHR() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestRestingHR = Int(metric)
            }
        }
    }

    func fetchLatestSpO2() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestSpO2Avg = metric
            }
        }
    }

    func fetchLatestVo2Max() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestVo2Max = metric
            }
        }
    }

    private func fetchLatestQuantity(_ type: HKQuantityType) async -> Double? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-86400), // last 24 hours
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil,
                      let sample = samples?.first as? HKQuantity else {
                    continuation.resume(returning: nil)
                    return
                }

                let value = sample.doubleValue(for: self.unit(for: type))
                continuation.resume(returning: value)
            }

            self.healthStore.execute(query)
        }
    }

    private func unit(for type: HKQuantityType) -> HKUnit {
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return .secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return .count().unitDivided(by: .count())
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            return .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .second().unitMultiplied(by: .minute())))
        default:
            return .count()
        }
    }

    // MARK: - Sleep Data

    func fetchSleepData(for date: Date) async -> SleepData? {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard error == nil, let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                var totalSleep: TimeInterval = 0
                var deepSleep: TimeInterval = 0
                var remSleep: TimeInterval = 0
                var awake: TimeInterval = 0

                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        totalSleep += duration
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        totalSleep += duration
                        deepSleep += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        totalSleep += duration
                        remSleep += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += duration
                    default:
                        break
                    }
                }

                let result = SleepData(
                    totalHours: totalSleep / 3600,
                    deepHours: deepSleep / 3600,
                    remHours: remSleep / 3600,
                    awakeMinutes: Int(awake / 60)
                )
                continuation.resume(returning: result)
            }

            self.healthStore.execute(query)
        }
    }

    // MARK: - Recovery Metrics Sync

    func syncRecoveryMetrics(athleteId: String, sessionId: String?, for date: Date) async {
        let sleep = await fetchSleepData(for: date)

        await fetchLatestHeartRate()
        await fetchLatestHRV()
        await fetchLatestRestingHR()
        await fetchLatestSpO2()
        await fetchLatestVo2Max()

        await MainActor.run {
            let recoveryScore = Self.computeRecoveryScore(
                hrv: self.latestHRVAvg ?? 50,
                restingHR: self.latestRestingHR ?? 70,
                sleepHours: sleep?.totalHours ?? 0
            )
            let fatigueScore = Self.computeFatigueScore(
                sleepHours: sleep?.totalHours ?? 0,
                restingHR: self.latestRestingHR ?? 70,
                hrv: self.latestHRVAvg ?? 50
            )
            let readinessScore = Self.computeReadinessScore(
                recoveryScore: recoveryScore,
                fatigueScore: fatigueScore
            )

            // Send to backend
            BackendSyncService.shared.syncRecoveryMetrics(
                athleteId: athleteId,
                sessionId: sessionId,
                date: date,
                sleepHours: sleep?.totalHours,
                sleepDeepHours: sleep?.deepHours,
                sleepRemHours: sleep?.remHours,
                sleepAwakeMinutes: sleep?.awakeMinutes,
                spo2Avg: self.latestSpO2Avg,
                spo2Min: nil,
                restingHR: self.latestRestingHR,
                hrvAvg: self.latestHRVAvg,
                vo2Max: self.latestVo2Max,
                recoveryScore: recoveryScore,
                fatigueScore: fatigueScore,
                readinessScore: readinessScore
            )
        }
    }

    // MARK: - Score Calculations

    private static func computeRecoveryScore(hrv: Int, restingHR: Int, sleepHours: Double) -> Double {
        // Simple baseline recovery score (0-100)
        // HRV contribution: higher is better (normalized to 0-50 range)
        let hrvScore = min(Double(hrv) / 100.0 * 50, 50)
        // Resting HR contribution: lower is better
        let hrScore = max(0, (80 - Double(restingHR)) / 80.0 * 25)
        // Sleep contribution: 7-9 hours is optimal
        let optimalSleep = min(sleepHours, 9) / 9.0
        let sleepScore = optimalSleep * 25

        return min(hrvScore + hrScore + sleepScore, 100)
    }

    private static func computeFatigueScore(sleepHours: Double, restingHR: Int, hrv: Int) -> Double {
        // Fatigue is inverse of recovery
        let recovery = computeRecoveryScore(hrv: hrv, restingHR: restingHR, sleepHours: sleepHours)
        return 100 - recovery
    }

    private static func computeReadinessScore(recoveryScore: Double, fatigueScore: Double) -> Double {
        return (recoveryScore + (100 - fatigueScore)) / 2.0
    }

    // MARK: - Background Task

    func scheduleBackgroundRefresh(athleteId: String) {
        // Use BGAppRefreshTask for periodic HealthKit sync
        // This is registered in Info.plist under BGTaskSchedulerPermittedIdentifiers
    }
}

// MARK: - Supporting Types

struct SleepData {
    let totalHours: Double
    let deepHours: Double
    let remHours: Double
    let awakeMinutes: Int
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .notAuthorized:
            return "HealthKit access was not authorized."
        }
    }
}
