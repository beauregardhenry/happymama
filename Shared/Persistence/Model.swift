import CoreData

/// The Core Data model, built in code so there is no .xcdatamodeld to keep in sync.
/// Everything is optional or defaulted, as CloudKit mirroring requires.
enum HappyMamaModel {
    static let shared: NSManagedObjectModel = build()

    private static func build() -> NSManagedObjectModel {
        let household = entity(Household.self, [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("parentCode", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
        ])
        let member = entity(Member.self, [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("roleRaw", .stringAttributeType, "kid"),
            attr("emoji", .stringAttributeType),
            attr("colorIndex", .integer16AttributeType, 0),
            attr("appleUserID", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("goalRewardID", .UUIDAttributeType),
        ])
        let chore = entity(Chore.self, [
            attr("id", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("notes", .stringAttributeType),
            attr("points", .integer32AttributeType, 0),
            attr("statusRaw", .stringAttributeType, "todo"),
            attr("dueDate", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("recurrenceRaw", .stringAttributeType, "none"),
            attr("weekdayMask", .integer16AttributeType, 0),
            attr("completedAt", .dateAttributeType),
            attr("completionNote", .stringAttributeType),
            attr("photo", .binaryDataAttributeType, external: true),
            attr("reviewedAt", .dateAttributeType),
            attr("reviewedByName", .stringAttributeType),
            attr("reviewNote", .stringAttributeType),
            attr("awardedPoints", .integer32AttributeType, 0),
            attr("sourceChoreID", .UUIDAttributeType),
            attr("rotationRaw", .stringAttributeType),
        ])
        let reward = entity(Reward.self, [
            attr("id", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("emoji", .stringAttributeType),
            attr("cost", .integer32AttributeType, 0),
            attr("isActive", .booleanAttributeType, true),
            attr("createdAt", .dateAttributeType),
        ])
        let redemption = entity(Redemption.self, [
            attr("id", .UUIDAttributeType),
            attr("rewardTitle", .stringAttributeType),
            attr("rewardEmoji", .stringAttributeType),
            attr("cost", .integer32AttributeType, 0),
            attr("statusRaw", .stringAttributeType, "requested"),
            attr("requestedAt", .dateAttributeType),
            attr("decidedAt", .dateAttributeType),
            attr("decidedByName", .stringAttributeType),
        ])
        let entry = entity(PointEntry.self, [
            attr("id", .UUIDAttributeType),
            attr("amount", .integer32AttributeType, 0),
            attr("reason", .stringAttributeType),
            attr("kindRaw", .stringAttributeType, "chore"),
            attr("date", .dateAttributeType),
            attr("choreID", .UUIDAttributeType),
            attr("redemptionID", .UUIDAttributeType),
        ])

        // Household owns everything; deleting it (or a member) cascades.
        link(household, member, oneSide: "household", manySide: "members")
        link(household, chore, oneSide: "household", manySide: "chores")
        link(household, reward, oneSide: "household", manySide: "rewards")
        link(household, redemption, oneSide: "household", manySide: "redemptions")
        link(household, entry, oneSide: "household", manySide: "entries")
        link(member, chore, oneSide: "assignee", manySide: "assignedChores")
        link(member, redemption, oneSide: "member", manySide: "redemptions")
        link(member, entry, oneSide: "member", manySide: "entries")

        let model = NSManagedObjectModel()
        model.entities = [household, member, chore, reward, redemption, entry]
        return model
    }

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        _ defaultValue: Any? = nil,
        external: Bool = false
    ) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = true
        a.defaultValue = defaultValue
        a.allowsExternalBinaryDataStorage = external
        return a
    }

    private static func entity(_ cls: NSManagedObject.Type, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = String(describing: cls)
        e.managedObjectClassName = NSStringFromClass(cls)
        e.properties = attributes
        return e
    }

    /// Adds a to-many relationship on `one` (cascade) and its to-one inverse on `many`.
    private static func link(_ one: NSEntityDescription, _ many: NSEntityDescription, oneSide: String, manySide: String) {
        let toMany = NSRelationshipDescription()
        toMany.name = manySide
        toMany.destinationEntity = many
        toMany.isOptional = true
        toMany.minCount = 0
        toMany.maxCount = 0
        toMany.deleteRule = .cascadeDeleteRule

        let toOne = NSRelationshipDescription()
        toOne.name = oneSide
        toOne.destinationEntity = one
        toOne.isOptional = true
        toOne.minCount = 0
        toOne.maxCount = 1
        toOne.deleteRule = .nullifyDeleteRule

        toMany.inverseRelationship = toOne
        toOne.inverseRelationship = toMany
        one.properties.append(toMany)
        many.properties.append(toOne)
    }
}
