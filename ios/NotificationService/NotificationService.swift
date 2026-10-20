import UserNotifications
import CloudKit

// Omskriver CloudKits generelle notifikation ("Der er kommet noget nyt …") til fx
// "Sheila har tilføjet et højdepunkt for Theo", før den vises.
//  • Henter kun de ændrede records siden sidst (tekstfelter, aldrig billeder).
//  • Ændringer man selv har lavet vises ikke (tom notifikation = vises ikke).
//  • Går noget galt eller tiden løber ud, vises den oprindelige tekst — intet går tabt.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var original: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        original = content

        guard let note = CKNotification(fromRemoteNotificationDictionary: request.content.userInfo)
                as? CKDatabaseNotification else {
            contentHandler(content)
            return
        }

        Task {
            let records = await ChangeFeed.changes(scope: note.databaseScope)
            let result = Self.describe(records)
            switch result {
            case .text(let body, let newest):
                content.body = body
                // Gem den i loggen til klokken på Hjem, så man kan finde den igen og trykke ind på den.
                NotificationLog.append(NotificationLogEntry(
                    id: newest.recordID.recordName + "_" + String(Int((newest.modificationDate ?? Date()).timeIntervalSince1970)),
                    date: newest.modificationDate ?? Date(),
                    title: content.title,
                    body: body,
                    kind: newest.recordType,
                    recordId: newest.recordID.recordName,
                    childId: (newest["childRef"] as? CKRecord.Reference)?.recordID.recordName,
                    info: ["galleryKind": newest["kind"] as? String ?? ""]))
                contentHandler(content)
            case .onlyOwnChanges:
                contentHandler(UNNotificationContent())   // tom = vises ikke
            case .unknown:
                contentHandler(content)
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let original { contentHandler(original) }
    }

    // MARK: Tekst

    enum Description { case text(String, CKRecord), onlyOwnChanges, unknown }

    private static func describe(_ records: [CKRecord]) -> Description {
        // Kun indhold — ikke delings-/navne-/familie-records.
        let content = records.filter { what($0) != nil }
        guard !content.isEmpty else { return .unknown }

        let others = content.filter { author($0) != CKCurrentUserDefaultName }
        guard let newest = others.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) })
        else { return .onlyOwnChanges }

        let who = SharedNames.members[author(newest) ?? ""] ?? "Den anden forælder"
        let isNew = abs((newest.creationDate ?? .distantPast).timeIntervalSince(newest.modificationDate ?? .distantPast)) < 5
        let verb = isNew ? "har tilføjet" : "har opdateret"
        var text = "\(who) \(verb) \(what(newest) ?? "noget")"
        if let childId = (newest["childRef"] as? CKRecord.Reference)?.recordID.recordName,
           let child = SharedNames.children[childId] {
            text += " for \(child)"
        }
        if others.count > 1 { text += " (og \(others.count - 1) mere)" }
        return .text(text, newest)
    }

    private static func author(_ record: CKRecord) -> String? {
        (record.lastModifiedUserRecordID ?? record.creatorUserRecordID)?.recordName
    }

    private static func what(_ record: CKRecord) -> String? {
        switch record.recordType {
        case "Highlight": return "et højdepunkt"
        case "Diary": return "et dagbogsindlæg"
        case "GalleryItem":
            return (record["kind"] as? String) == "belly" ? "et mavebillede" : "et månedsbillede"
        case "Milestone":
            return (record["key"] as? String)?.hasPrefix("vac_") == true ? "en vaccination" : "en milepæl"
        case "Answer": return "et svar i Om dig"
        case "Event": return "en begivenhed"
        case "Vacation": return "en rejse"
        case "Birthday": return "en fødselsdag"
        case "Letter": return "et brev"
        case "Measurement": return "en måling"
        case "Child": return "et barn"
        case "Memory": return "et minde"
        case "Recipe": return "en opskrift"
        case "Tradition": return "en tradition"
        case "Person": return "en person i stamtræet"
        case "Interview": return "et svar i det årlige interview"
        default: return nil    // Family, Member, cloudkit.share …
        }
    }
}
