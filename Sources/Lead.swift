import Foundation

/// The structured fact-find a producer gathers on the call — the "discovery"
/// behind the numbers. Stored as jsonb in Insforge.
struct FactFind: Codable {
    var motive: String?            // which of the 3 reasons / why they want coverage
    var dependents: String?        // spouse, kids, who relies on their income
    var debt: String?              // DIME
    var income: String?
    var mortgage: String?
    var education: String?
    var existingCoverage: String?  // work/other policies they already have
    var tobacco: String?           // yes/no + detail
    var healthConditions: String?  // knockouts: heart/cancer/stroke/diabetes/meds
    var heightWeight: String?
    var recommendedProduct: String? // what Jordan steered them to and why
    var objections: String?        // what they pushed back on

    enum CodingKeys: String, CodingKey {
        case motive, dependents, debt, income, mortgage, education, tobacco, objections
        case existingCoverage = "existing_coverage"
        case healthConditions = "health_conditions"
        case heightWeight = "height_weight"
        case recommendedProduct = "recommended_product"
    }
}

/// A qualified lead, as stored in Insforge.
struct Lead: Codable, Identifiable {
    var id: String?
    var name: String?
    var age: Int?
    var coverageType: String?
    var coverageAmount: String?
    var monthlyBudget: String?
    var outcome: String?
    var email: String?
    var phone: String?
    var callbackAt: String?
    var callbackStatus: String?
    var transcript: String?
    var summary: String?
    var factFind: FactFind?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, age, outcome, email, phone, transcript, summary
        case coverageType = "coverage_type"
        case coverageAmount = "coverage_amount"
        case monthlyBudget = "monthly_budget"
        case callbackAt = "callback_at"
        case callbackStatus = "callback_status"
        case factFind = "fact_find"
        case createdAt = "created_at"
    }
}
