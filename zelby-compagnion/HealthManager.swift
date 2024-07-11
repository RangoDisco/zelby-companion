//
//  HealthManager.swift
//  zelby-compagnion
//
//  Created by Maxime Dias on 11/07/2024.
//

import Foundation
import HealthKit

extension Date {
    static var startOfDay: Date {
        Calendar.current.startOfDay(for: Date())
    }
}

extension HKWorkoutActivityType {
    init?(rawValue: UInt) {
        self.init(rawValue: rawValue)
    }
    
    var activityName: String {
        switch self {
        case .traditionalStrengthTraining:
            return "strength"
        case .walking:
            return "walk"
        case .running:
            return "running"
        case .cycling:
            return "cycling"
        default:
            return "unknown"
        }
    }
}

struct WorkoutData {
    var name: String?
    var kcalBurned: Double
    var activityType: String
    var duration: TimeInterval
}

class HealthManager: ObservableObject {
    
    let healthStore = HKHealthStore()
    
    init() {
        // Define all permissions needed
        let steps = HKQuantityType(.stepCount)
        let burntCalories = HKQuantityType(.activeEnergyBurned)
        let consumedCalories = HKQuantityType(.dietaryEnergyConsumed)
        let sessions = HKObjectType.workoutType()
        
        let healthTypes: Set = [steps, burntCalories, consumedCalories, sessions]
        
        // Ask all permissions
        Task {
            do {
                try await healthStore.requestAuthorization(toShare:[], read:healthTypes)
            } catch {
                print("error fetching health data")
            }
        }
    }
    
    
    // Main function that fetches everything needed for the bot
    func fetchHealthData() {
        // Declare needed variables
        var steps: Double = 0
        var burntKcal: Double = 0
        var consumedKcal: Double = 0
        var workouts: [WorkoutData] = []
        let group = DispatchGroup()
        
        // Fetch steps
        group.enter()
        fetchCountableData(type: HKQuantityType(.stepCount), countType: .count()) { count in
            steps = count
            group.leave()
        }
        
        // Fetch burnt kcal
        group.enter()
        fetchCountableData(type: HKQuantityType(.activeEnergyBurned), countType: .kilocalorie()) {count in
            burntKcal = count
            group.leave()
        }
        
        // Fetch consumed kcal
        group.enter()
        fetchCountableData(type: HKQuantityType(.dietaryEnergyConsumed), countType: .kilocalorie()) {count in
            consumedKcal = count
            group.leave()
        }
        
        // Fetch sessions
        group.enter()
        fetchSessions(){sessions in
            workouts = sessions
            group.leave()
        }
        
        
        // Log everything
        group.notify(queue: .main) {
            print("Steps: \(steps)")
            print("Kcal burnt: \(burntKcal)")
            print("Kcal consumed: \(consumedKcal)")
            print("Workouts: \(workouts)")
        }
    }
    
    // Can fetch all countable data (steps, kcal etc...)
    func fetchCountableData(type: HKQuantityType, countType: HKUnit, completion: @escaping (Double) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: .startOfDay, end: Date())
        
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate) { _, result, error in
            guard let quantity = result?.sumQuantity(), error == nil else {
                // TODO: handle custom error
                print ("error fetching data")
                return
            }
            let count = quantity.doubleValue(for: countType)
            completion(count)
        }
        
        healthStore.execute(query)
    }
    
    func fetchSessions(completion: @escaping ([WorkoutData]) -> Void) {
        let sessions = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: .startOfDay, end: Date())
        
        // Fetch all workouts for today
        let query = HKSampleQuery(sampleType: sessions, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            guard let workouts = samples as? [HKWorkout], error == nil else {
                print("error fetching workouts")
                return
            }
            
            var parsedWorkouts = [WorkoutData]()
            
            // Loop and create new Object based on data needed for the bot
            for workout in workouts {
                let name = workout.metadata?["HKWorkoutBrandName"] as? String
                let kcal = workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                let type = workout.workoutActivityType.activityName
                
                let parsedWorkout = WorkoutData(name: name, kcalBurned: kcal, activityType: type, duration: workout.duration)
                parsedWorkouts.append(parsedWorkout)
                
            }
            
            completion(parsedWorkouts)
            
        }
        healthStore.execute(query)
    }
}
