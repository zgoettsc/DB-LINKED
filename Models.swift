import Foundation

struct LogEntry: Equatable, Codable, Hashable, Identifiable {
    let id = UUID() // Local identifier, not used for uniqueness in Set
    let date: Date
    let userId: UUID
    
    enum CodingKeys: String, CodingKey {
        case date = "timestamp"
        case userId
        // 'id' is not included in CodingKeys since it's not stored in Firebase
    }
    
    init(date: Date, userId: UUID) {
        self.date = date
        self.userId = userId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dateString = try container.decode(String.self, forKey: .date)
        guard let decodedDate = ISO8601DateFormatter().date(from: dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Invalid ISO8601 date string")
        }
        self.date = decodedDate
        self.userId = try container.decode(UUID.self, forKey: .userId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let dateString = ISO8601DateFormatter().string(from: date)
        try container.encode(dateString, forKey: .date)
        try container.encode(userId, forKey: .userId)
    }
    
    // Hashable conformance: Ignore id, use only date and userId
    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        return lhs.date == rhs.date && lhs.userId == rhs.userId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(userId)
    }
}

// Cycle conforms to Equatable and Codable
struct Cycle: Equatable, Codable {
    let id: UUID
    let number: Int
    let patientName: String
    let startDate: Date
    let foodChallengeDate: Date
    
    init(id: UUID = UUID(), number: Int, patientName: String, startDate: Date, foodChallengeDate: Date) {
        self.id = id
        self.number = number
        self.patientName = patientName
        self.startDate = startDate
        self.foodChallengeDate = foodChallengeDate
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let number = dictionary["number"] as? Int,
              let patientName = dictionary["patientName"] as? String,
              let startDateStr = dictionary["startDate"] as? String,
              let startDate = ISO8601DateFormatter().date(from: startDateStr),
              let foodChallengeDateStr = dictionary["foodChallengeDate"] as? String,
              let foodChallengeDate = ISO8601DateFormatter().date(from: foodChallengeDateStr) else { return nil }
        self.id = id
        self.number = number
        self.patientName = patientName
        self.startDate = startDate
        self.foodChallengeDate = foodChallengeDate
    }
    
    func toDictionary() -> [String: Any] {
        [
            "id": id.uuidString,
            "number": number,
            "patientName": patientName,
            "startDate": ISO8601DateFormatter().string(from: startDate),
            "foodChallengeDate": ISO8601DateFormatter().string(from: foodChallengeDate)
        ]
    }
    
    static func == (lhs: Cycle, rhs: Cycle) -> Bool {
        return lhs.id == rhs.id &&
               lhs.number == rhs.number &&
               lhs.patientName == rhs.patientName &&
               lhs.startDate == rhs.startDate &&
               lhs.foodChallengeDate == rhs.foodChallengeDate
    }
    
    enum CodingKeys: String, CodingKey {
        case id, number, patientName, startDate, foodChallengeDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        patientName = try container.decode(String.self, forKey: .patientName)
        let startDateString = try container.decode(String.self, forKey: .startDate)
        guard let decodedStartDate = ISO8601DateFormatter().date(from: startDateString) else {
            throw DecodingError.dataCorruptedError(forKey: .startDate, in: container, debugDescription: "Invalid ISO8601 date string")
        }
        startDate = decodedStartDate
        let foodChallengeDateString = try container.decode(String.self, forKey: .foodChallengeDate)
        guard let decodedFoodChallengeDate = ISO8601DateFormatter().date(from: foodChallengeDateString) else {
            throw DecodingError.dataCorruptedError(forKey: .foodChallengeDate, in: container, debugDescription: "Invalid ISO8601 date string")
        }
        foodChallengeDate = decodedFoodChallengeDate
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(patientName, forKey: .patientName)
        try container.encode(ISO8601DateFormatter().string(from: startDate), forKey: .startDate)
        try container.encode(ISO8601DateFormatter().string(from: foodChallengeDate), forKey: .foodChallengeDate)
    }
}

// Item conforms to Identifiable and Codable
struct Item: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: Category
    let dose: Double?
    let unit: String?
    let weeklyDoses: [Int: Double]?
    let order: Int
    
    init(id: UUID = UUID(), name: String, category: Category, dose: Double? = nil, unit: String? = nil, weeklyDoses: [Int: Double]? = nil, order: Int = 0) {
        self.id = id
        self.name = name
        self.category = category
        self.dose = dose
        self.unit = unit
        self.weeklyDoses = weeklyDoses
        self.order = order
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String,
              let categoryStr = dictionary["category"] as? String,
              let category = Category(rawValue: categoryStr) else { return nil }
        self.id = id
        self.name = name
        self.category = category
        self.dose = dictionary["dose"] as? Double
        self.unit = dictionary["unit"] as? String
        
        // More robust weekly doses parsing
        if let weeklyDosesDict = dictionary["weeklyDoses"] as? [String: Any] {
            // Try parsing as dictionary with multiple possible value types
            var parsedDoses: [Int: Double] = [:]
            for (key, value) in weeklyDosesDict {
                if let weekNum = Int(key) {
                    if let doseValue = value as? Double {
                        parsedDoses[weekNum] = doseValue
                    } else if let doseValueStr = value as? String, let doseValue = Double(doseValueStr) {
                        // Try parsing string values as doubles
                        parsedDoses[weekNum] = doseValue
                    } else if let doseValueNum = value as? NSNumber {
                        // Try parsing as NSNumber (Firebase sometimes uses this)
                        parsedDoses[weekNum] = doseValueNum.doubleValue
                    }
                }
            }
            self.weeklyDoses = parsedDoses.isEmpty ? nil : parsedDoses
        } else {
            self.weeklyDoses = nil
        }
        
        self.order = dictionary["order"] as? Int ?? 0
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "category": category.rawValue,
            "order": order
        ]
        if let dose = dose { dict["dose"] = dose }
        if let unit = unit { dict["unit"] = unit }
        if let weeklyDoses = weeklyDoses {
            let stringKeyedDoses = weeklyDoses.mapKeys { String($0) }
            dict["weeklyDoses"] = stringKeyedDoses
        }
        return dict
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, dose, unit, weeklyDoses, order
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let categoryString = try container.decode(String.self, forKey: .category)
        guard let decodedCategory = Category(rawValue: categoryString) else {
            throw DecodingError.dataCorruptedError(forKey: .category, in: container, debugDescription: "Invalid category value")
        }
        category = decodedCategory
        dose = try container.decodeIfPresent(Double.self, forKey: .dose)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        if let weeklyDosesDict = try container.decodeIfPresent([String: Double].self, forKey: .weeklyDoses) {
            weeklyDoses = weeklyDosesDict.reduce(into: [Int: Double]()) { result, pair in
                if let week = Int(pair.key) {
                    result[week] = pair.value
                }
            }
        } else {
            weeklyDoses = nil
        }
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category.rawValue, forKey: .category)
        try container.encodeIfPresent(dose, forKey: .dose)
        try container.encodeIfPresent(unit, forKey: .unit)
        if let weeklyDoses = weeklyDoses {
            let stringKeyedDoses = weeklyDoses.mapKeys { String($0) }
            try container.encode(stringKeyedDoses, forKey: .weeklyDoses)
        }
        try container.encode(order, forKey: .order)
    }
}

// Unit conforms to Hashable, Identifiable, and Codable
struct Unit: Hashable, Identifiable, Codable {
    let id: UUID
    let name: String
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String else { return nil }
        self.id = id
        self.name = name
    }
    
    func toDictionary() -> [String: Any] {
        ["id": id.uuidString, "name": name]
    }
    
    static func == (lhs: Unit, rhs: Unit) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}

// User conforms to Identifiable, Equatable, and Codable
struct User: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    var isAdmin: Bool  // Changed from 'let' to 'var' to make it mutable
    var remindersEnabled: [Category: Bool] // Per-user reminders enabled
    var reminderTimes: [Category: Date]   // Per-user reminder times
    var treatmentFoodTimerEnabled: Bool   // Per-user timer enabled
    var treatmentTimerDuration: TimeInterval // Per-user timer duration
    
    init(id: UUID = UUID(), name: String, isAdmin: Bool = false,
         remindersEnabled: [Category: Bool] = [:],
         reminderTimes: [Category: Date] = [:],
         treatmentFoodTimerEnabled: Bool = false,
         treatmentTimerDuration: TimeInterval = 900) {
        self.id = id
        self.name = name
        self.isAdmin = isAdmin
        self.remindersEnabled = remindersEnabled
        self.reminderTimes = reminderTimes
        self.treatmentFoodTimerEnabled = treatmentFoodTimerEnabled
        self.treatmentTimerDuration = treatmentTimerDuration
    }
    
    // Rest of the implementation remains the same
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String,
              let isAdmin = dictionary["isAdmin"] as? Bool else { return nil }
        self.id = id
        self.name = name
        self.isAdmin = isAdmin
        
        if let remindersEnabledDict = dictionary["remindersEnabled"] as? [String: Bool] {
            self.remindersEnabled = remindersEnabledDict.reduce(into: [Category: Bool]()) { result, pair in
                if let category = Category(rawValue: pair.key) {
                    result[category] = pair.value
                }
            }
        } else {
            self.remindersEnabled = [:]
        }
        
        if let reminderTimesDict = dictionary["reminderTimes"] as? [String: String] {
            self.reminderTimes = reminderTimesDict.reduce(into: [Category: Date]()) { result, pair in
                if let category = Category(rawValue: pair.key),
                   let date = ISO8601DateFormatter().date(from: pair.value) {
                    result[category] = date
                }
            }
        } else {
            self.reminderTimes = [:]
        }
        
        self.treatmentFoodTimerEnabled = dictionary["treatmentFoodTimerEnabled"] as? Bool ?? false
        self.treatmentTimerDuration = dictionary["treatmentTimerDuration"] as? Double ?? 900
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "isAdmin": isAdmin,
            "treatmentFoodTimerEnabled": treatmentFoodTimerEnabled,
            "treatmentTimerDuration": treatmentTimerDuration
        ]
        if !remindersEnabled.isEmpty {
            dict["remindersEnabled"] = remindersEnabled.mapKeys { $0.rawValue }
        }
        if !reminderTimes.isEmpty {
            dict["reminderTimes"] = reminderTimes.mapKeys { $0.rawValue }.mapValues { ISO8601DateFormatter().string(from: $0) }
        }
        return dict
    }
    
    static func == (lhs: User, rhs: User) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.isAdmin == rhs.isAdmin &&
               lhs.remindersEnabled == rhs.remindersEnabled &&
               lhs.reminderTimes == rhs.reminderTimes &&
               lhs.treatmentFoodTimerEnabled == rhs.treatmentFoodTimerEnabled &&
               lhs.treatmentTimerDuration == rhs.treatmentTimerDuration
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, isAdmin, remindersEnabled, reminderTimes, treatmentFoodTimerEnabled, treatmentTimerDuration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isAdmin = try container.decode(Bool.self, forKey: .isAdmin)
        if let remindersEnabledDict = try container.decodeIfPresent([String: Bool].self, forKey: .remindersEnabled) {
            remindersEnabled = remindersEnabledDict.reduce(into: [Category: Bool]()) { result, pair in
                if let category = Category(rawValue: pair.key) {
                    result[category] = pair.value
                }
            }
        } else {
            remindersEnabled = [:]
        }
        if let reminderTimesDict = try container.decodeIfPresent([String: String].self, forKey: .reminderTimes) {
            reminderTimes = reminderTimesDict.reduce(into: [Category: Date]()) { result, pair in
                if let category = Category(rawValue: pair.key),
                   let date = ISO8601DateFormatter().date(from: pair.value) {
                    result[category] = date
                }
            }
        } else {
            reminderTimes = [:]
        }
        treatmentFoodTimerEnabled = try container.decodeIfPresent(Bool.self, forKey: .treatmentFoodTimerEnabled) ?? false
        treatmentTimerDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .treatmentTimerDuration) ?? 900
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isAdmin, forKey: .isAdmin)
        try container.encode(remindersEnabled.mapKeys { (key: Category) in key.rawValue }, forKey: .remindersEnabled)
        try container.encode(reminderTimes.mapKeys { (key: Category) in key.rawValue }.mapValues { ISO8601DateFormatter().string(from: $0) }, forKey: .reminderTimes)
        try container.encode(treatmentFoodTimerEnabled, forKey: .treatmentFoodTimerEnabled)
        try container.encode(treatmentTimerDuration, forKey: .treatmentTimerDuration)
    }
}

enum Category: String, CaseIterable {
    case medicine = "Medicine"
    case maintenance = "Maintenance"
    case treatment = "Treatment"
    case recommended = "Recommended"
}

// GroupedItem for combining items within a category
struct GroupedItem: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: Category
    let itemIds: [UUID] // IDs of Items in this group
    
    init(id: UUID = UUID(), name: String, category: Category, itemIds: [UUID]) {
        self.id = id
        self.name = name
        self.category = category
        self.itemIds = itemIds
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String,
              let categoryStr = dictionary["category"] as? String,
              let category = Category(rawValue: categoryStr),
              let itemIdsArray = dictionary["itemIds"] as? [String] else { return nil }
        self.id = id
        self.name = name
        self.category = category
        self.itemIds = itemIdsArray.compactMap { UUID(uuidString: $0) }
    }
    
    func toDictionary() -> [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "category": category.rawValue,
            "itemIds": itemIds.map { $0.uuidString }
        ]
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, itemIds
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let categoryString = try container.decode(String.self, forKey: .category)
        guard let decodedCategory = Category(rawValue: categoryString) else {
            throw DecodingError.dataCorruptedError(forKey: .category, in: container, debugDescription: "Invalid category value")
        }
        category = decodedCategory
        itemIds = try container.decode([UUID].self, forKey: .itemIds)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(itemIds, forKey: .itemIds)
    }
}

struct Fraction: Identifiable, Codable, Hashable { // Add Hashable conformance
    let id = UUID()
    let numerator: Int
    let denominator: Int
    
    var decimalValue: Double {
        Double(numerator) / Double(denominator)
    }
    
    var displayString: String {
        "\(numerator)/\(denominator)"
    }
    
    static let commonFractions: [Fraction] = [
        Fraction(numerator: 1, denominator: 8),  // 0.125
        Fraction(numerator: 1, denominator: 4),  // 0.25
        Fraction(numerator: 1, denominator: 3),  // ~0.333
        Fraction(numerator: 1, denominator: 2),  // 0.5
        Fraction(numerator: 2, denominator: 3),  // ~0.666
        Fraction(numerator: 3, denominator: 4),  // 0.75
    ]
    
    static func fractionForDecimal(_ decimal: Double, tolerance: Double = 0.01) -> Fraction? {
        commonFractions.first { abs($0.decimalValue - decimal) < tolerance }
    }
    
    // Hashable conformance
    static func ==(lhs: Fraction, rhs: Fraction) -> Bool {
        lhs.numerator == rhs.numerator && lhs.denominator == rhs.denominator
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(numerator)
        hasher.combine(denominator)
    }
}

// Helper extension to transform dictionary keys
extension Dictionary {
    func mapKeys<T>(transform: (Key) -> T) -> [T: Value] {
        return reduce(into: [T: Value]()) { result, pair in
            result[transform(pair.key)] = pair.value
        }
    }
}

struct TreatmentTimer: Codable, Equatable {
    let id: String
    let isActive: Bool
    let endTime: Date
    let associatedItemIds: [UUID]?
    let notificationIds: [String]?
    
    init(id: String = UUID().uuidString,
         isActive: Bool = true,
         endTime: Date,
         associatedItemIds: [UUID]? = nil,
         notificationIds: [String]? = nil) {
        self.id = id
        self.isActive = isActive
        self.endTime = endTime
        self.associatedItemIds = associatedItemIds
        self.notificationIds = notificationIds
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "isActive": isActive,
            "endTime": ISO8601DateFormatter().string(from: endTime)
        ]
        
        if let associatedItemIds = associatedItemIds {
            dict["associatedItemIds"] = associatedItemIds.map { $0.uuidString }
        }
        
        if let notificationIds = notificationIds {
            dict["notificationIds"] = notificationIds
        }
        
        return dict
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> TreatmentTimer? {
        guard let id = dict["id"] as? String,
              let isActive = dict["isActive"] as? Bool,
              let endTimeStr = dict["endTime"] as? String,
              let endTime = ISO8601DateFormatter().date(from: endTimeStr) else {
            return nil
        }
        
        var associatedItemIds: [UUID]? = nil
        if let itemIdStrings = dict["associatedItemIds"] as? [String] {
            associatedItemIds = itemIdStrings.compactMap { UUID(uuidString: $0) }
        }
        
        var notificationIds: [String]? = nil
        if let ids = dict["notificationIds"] as? [String] {
            notificationIds = ids
        }
        
        return TreatmentTimer(
            id: id,
            isActive: isActive,
            endTime: endTime,
            associatedItemIds: associatedItemIds,
            notificationIds: notificationIds
        )
    }
}

