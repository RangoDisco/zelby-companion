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

struct WorkoutData: Codable {
    var name: String?
    var kcalBurned: Int
    var activityType: String
    var duration: Int
}

class HealthManager: ObservableObject {
    
    let healthStore = HKHealthStore()
    
    init() {
        // Define all permissions needed
        let steps = HKQuantityType(.stepCount)
        let burntCalories = HKQuantityType(.activeEnergyBurned)
        let consumedCalories = HKQuantityType(.dietaryEnergyConsumed)
        let waterDrank = HKQuantityType(.dietaryWater)
        let sessions = HKObjectType.workoutType()
        
        let healthTypes: Set = [steps, burntCalories, consumedCalories, waterDrank, sessions]
        
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
        var steps: Int = 0
        var burntKcal: Int = 0
        var water: Int = 0
        var consumedKcal: Int = 0
        var workouts: Data?
        let group = DispatchGroup()
        
        // Fetch steps
        group.enter()
        fetchCountableData(type: HKQuantityType(.stepCount), countType: .count()) { count, error in
            steps = count
            group.leave()
        }
        
        // Fetch burnt kcal
        group.enter()
        fetchCountableData(type: HKQuantityType(.activeEnergyBurned), countType: .kilocalorie()) { count, error in
            burntKcal = count
            group.leave()
        }
        
        // Fetch consumed kcal
        group.enter()
        fetchCountableData(type: HKQuantityType(.dietaryEnergyConsumed), countType: .kilocalorie()) { count, error in
            consumedKcal = count
            group.leave()
        }
        
        // Fetch water drank
        group.enter()
        fetchCountableData(type: HKQuantityType(.dietaryWater), countType: .literUnit(with: .milli)) { count, error in
            water = count
            group.leave()
        }
        
        // Fetch sessions
        group.enter()
        fetchSessions { sessions, error in
            if let sessions = sessions {
                workouts = sessions
            }
            group.leave()
        }
        
        // Log everything
        group.notify(queue: .main) {
            let metrics: [[String: Any]] = [
                ["type": "KCAL_BURNED", "value": burntKcal],
                ["type": "KCAL_CONSUMED", "value": consumedKcal],
                ["type": "MILLILITER_DRANK", "value": water],
                ["type": "STEPS", "value": steps]
            ]
            
            let body: [String: Any] = [
                "metrics": metrics,
                "workouts": workouts != nil ? try! JSONSerialization.jsonObject(with: workouts!) : []
            ]
            
            do {
                let jsonBody = try JSONSerialization.data(withJSONObject: body, options: [])
                if let jsonString = String(data: jsonBody, encoding: .utf8) {
                    print(jsonString)
                }
                
                self.sendMetrics(data: jsonBody)
            } catch {
                print("Error serializing JSON:", error)
            }
        }
    }
    
    // Can fetch all countable data (steps, kcal etc...)
    func fetchCountableData(type: HKQuantityType, countType: HKUnit, completion: @escaping (Int, Error?) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: .startOfDay, end: Date())
        
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate) { _, result, error in
            guard let quantity = result?.sumQuantity(), error == nil else {
                // TODO: handle custom error
                print ("error fetching data")
                completion(0, NSError(domain: "com.example.HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data returned"]))
                return
            }
            let count = Int(quantity.doubleValue(for: countType))
            completion(count, nil)
        }
        
        healthStore.execute(query)
    }
    
    func fetchSessions(completion: @escaping (Data?, String?) -> Void) {
        let sessions = HKObjectType.workoutType()
        let predicate = NSPredicate(format: "startDate >= %@ AND startDate <= %@", argumentArray: [.startOfDay, Date()])
        
        // Fetch all workouts for today
        let query = HKSampleQuery(sampleType: sessions, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (_, samples, error) in
            guard let workouts = samples as? [HKWorkout], error == nil else {
                print("error fetching workouts")
                return
            }
            
            var parsedWorkouts = [WorkoutData]()
            
            // Loop and create new Object based on data needed for the bot
            for workout in workouts {
                print(workout)
                let name = workout.metadata?["HKWorkoutBrandName"] as? String
                let kcal = Int(workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0)
                let type = workout.workoutActivityType.activityName
                
                let parsedWorkout = WorkoutData(name: name, kcalBurned: kcal, activityType: type, duration: Int(workout.duration))
                parsedWorkouts.append(parsedWorkout)
            }
            do {
                // Convert WorkoutData objects to JSON
                let jsonData = try JSONEncoder().encode(parsedWorkouts)
                completion(jsonData, nil)
            } catch {
                print("Error encoding JSON:", error)
                completion(nil, "error")
            }
        }
        healthStore.execute(query)
    }
    
    func sendMetrics(data: Data) {
        // Call API to store the metrics
        guard let url = URL(string: Env.baseUrl + "/api/summaries") else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Env.apiKey, forHTTPHeaderField: "X-API-KEY")
        request.httpBody = data
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Client error:", error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("Server error")
                return
            }
            
            if let data = data, let dataString = String(data: data, encoding: .utf8) {
                print("Response data string:\n \(dataString)")
            }
        }
        task.resume()
    }
}
