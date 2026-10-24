import Foundation
import FirebaseFirestore

/// One shot in the recommended childhood schedule.
struct VaccineDose: Identifiable, Hashable {
    let id: String
    /// Short name, like "DTaP".
    let short: String
    /// What it protects against.
    let protects: String
    let dose: String
    var note: String? = nil
}

/// A well-child visit age and the shots usually given then.
struct VaccineVisit: Identifiable {
    let id: String
    let title: String
    /// Age range in months when these doses are given.
    let fromMonths: Double
    let toMonths: Double
    let doses: [VaccineDose]
}

/// The routine schedule from birth to 6 years, following the American Academy of Pediatrics'
/// recommended schedule. Pediatricians sometimes adjust timing or brands, so it's a guide.
enum VaccineSchedule {
    private static func d(_ id: String, _ short: String, _ protects: String, _ dose: String, _ note: String? = nil) -> VaccineDose {
        VaccineDose(id: id, short: short, protects: protects, dose: dose, note: note)
    }

    static let visits: [VaccineVisit] = [
        VaccineVisit(id: "birth", title: "Birth", fromMonths: 0, toMonths: 1, doses: [
            d("hepb-1", "Hep B", "Hepatitis B", "Dose 1 of 3", "Within 24 hours of birth"),
            d("rsv-1", "RSV antibody", "RSV", "1 dose", "If born before or during RSV season (October to March) and mom didn't get the RSV vaccine in pregnancy"),
        ]),
        VaccineVisit(id: "1m", title: "1 to 2 months", fromMonths: 1, toMonths: 2, doses: [
            d("hepb-2", "Hep B", "Hepatitis B", "Dose 2 of 3"),
        ]),
        VaccineVisit(id: "2m", title: "2 months", fromMonths: 2, toMonths: 3, doses: [
            d("dtap-1", "DTaP", "Diphtheria, tetanus, whooping cough", "Dose 1 of 5"),
            d("hib-1", "Hib", "Haemophilus influenzae type b", "Dose 1"),
            d("ipv-1", "Polio (IPV)", "Polio", "Dose 1 of 4"),
            d("pcv-1", "Pneumococcal (PCV)", "Pneumococcal disease", "Dose 1 of 4"),
            d("rv-1", "Rotavirus", "Rotavirus (by mouth)", "Dose 1"),
        ]),
        VaccineVisit(id: "4m", title: "4 months", fromMonths: 4, toMonths: 5, doses: [
            d("dtap-2", "DTaP", "Diphtheria, tetanus, whooping cough", "Dose 2 of 5"),
            d("hib-2", "Hib", "Haemophilus influenzae type b", "Dose 2"),
            d("ipv-2", "Polio (IPV)", "Polio", "Dose 2 of 4"),
            d("pcv-2", "Pneumococcal (PCV)", "Pneumococcal disease", "Dose 2 of 4"),
            d("rv-2", "Rotavirus", "Rotavirus (by mouth)", "Dose 2"),
        ]),
        VaccineVisit(id: "6m", title: "6 months", fromMonths: 6, toMonths: 7, doses: [
            d("dtap-3", "DTaP", "Diphtheria, tetanus, whooping cough", "Dose 3 of 5"),
            d("hib-3", "Hib", "Haemophilus influenzae type b", "Dose 3", "Only needed with some brands"),
            d("pcv-3", "Pneumococcal (PCV)", "Pneumococcal disease", "Dose 3 of 4"),
            d("rv-3", "Rotavirus", "Rotavirus (by mouth)", "Dose 3", "Only needed with some brands"),
            d("hepb-3", "Hep B", "Hepatitis B", "Dose 3 of 3", "Anytime from 6 to 18 months"),
            d("ipv-3", "Polio (IPV)", "Polio", "Dose 3 of 4", "Anytime from 6 to 18 months"),
            d("flu-1", "Flu", "Influenza", "First flu season, dose 1", "Every fall from 6 months on"),
            d("flu-2", "Flu", "Influenza", "First flu season, dose 2", "4 weeks after the first flu shot"),
            d("covid-1", "COVID-19", "COVID-19", "First series", "Ask your pediatrician which brand and how many doses"),
        ]),
        VaccineVisit(id: "12m", title: "12 to 15 months", fromMonths: 12, toMonths: 16, doses: [
            d("hib-4", "Hib", "Haemophilus influenzae type b", "Booster"),
            d("pcv-4", "Pneumococcal (PCV)", "Pneumococcal disease", "Dose 4 of 4"),
            d("mmr-1", "MMR", "Measles, mumps, rubella", "Dose 1 of 2"),
            d("var-1", "Chickenpox", "Varicella", "Dose 1 of 2"),
            d("hepa-1", "Hep A", "Hepatitis A", "Dose 1 of 2", "Anytime from 12 to 23 months"),
        ]),
        VaccineVisit(id: "15m", title: "15 to 18 months", fromMonths: 15, toMonths: 19, doses: [
            d("dtap-4", "DTaP", "Diphtheria, tetanus, whooping cough", "Dose 4 of 5"),
        ]),
        VaccineVisit(id: "18m", title: "18 to 23 months", fromMonths: 18, toMonths: 24, doses: [
            d("hepa-2", "Hep A", "Hepatitis A", "Dose 2 of 2", "At least 6 months after the first"),
        ]),
        VaccineVisit(id: "4y", title: "4 to 6 years", fromMonths: 48, toMonths: 73, doses: [
            d("dtap-5", "DTaP", "Diphtheria, tetanus, whooping cough", "Dose 5 of 5"),
            d("ipv-4", "Polio (IPV)", "Polio", "Dose 4 of 4"),
            d("mmr-2", "MMR", "Measles, mumps, rubella", "Dose 2 of 2"),
            d("var-2", "Chickenpox", "Varicella", "Dose 2 of 2"),
        ]),
    ]

    /// Doses that depend on the season, brand or a talk with the pediatrician; they don't count as "due".
    static let optionalIDs: Set<String> = ["rsv-1", "hib-3", "rv-3", "covid-1"]

    static func ageInMonths(birthDate: Date, on date: Date = Date()) -> Double {
        max(0, date.timeIntervalSince(birthDate) / (30.4375 * 86_400))
    }
}

/// A dose someone checked off. Stored at babies/{babyId}/vaccines/{doseId}.
struct VaccineRecord: Identifiable, Codable, Equatable {
    @DocumentID var id: String? = nil
    var givenOn: Date
    var checkedByUid: String
    var checkedByName: String
}

enum VaccineRepository {
    static func collection(_ babyID: String) -> CollectionReference {
        Firestore.firestore().collection("babies").document(babyID).collection("vaccines")
    }

    static func markGiven(_ dose: VaccineDose, on date: Date, babyID: String, auth: AuthService) {
        let record = VaccineRecord(givenOn: date, checkedByUid: auth.uid, checkedByName: auth.displayName)
        try? collection(babyID).document(dose.id).setData(from: record)
    }

    static func unmark(_ dose: VaccineDose, babyID: String) {
        collection(babyID).document(dose.id).delete()
    }
}

/// Live list of a baby's checked-off doses, keyed by dose id.
@Observable
final class VaccinesListener {
    private(set) var given: [String: VaccineRecord] = [:]
    private(set) var hasLoaded = false

    @ObservationIgnored private var listener: ListenerRegistration?

    func listen(babyID: String) {
        stop()
        if DesignPreview.isOn {
            given = DemoData.vaccines
            hasLoaded = true
            return
        }
        listener = VaccineRepository.collection(babyID).addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            var given: [String: VaccineRecord] = [:]
            for document in snapshot?.documents ?? [] {
                if let record = try? document.data(as: VaccineRecord.self) { given[document.documentID] = record }
            }
            self.given = given
            self.hasLoaded = true
        }
    }

    /// Checks a dose off (or back on) right away, before the server answers.
    func setLocally(_ doseID: String, _ record: VaccineRecord?) {
        given[doseID] = record
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    deinit { listener?.remove() }
}
