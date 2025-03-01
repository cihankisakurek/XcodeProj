import Foundation
import PathKit

/// Represents a .pbxproj file
public final class PBXProj: Decodable {
    // MARK: - Properties

    let objects: PBXObjects

    /// Project archive version.
    public var archiveVersion: UInt

    /// Project object version.
    public var objectVersion: UInt

    /// Project classes.
    public var classes: [String: Any]

    /// Project root object.
    var rootObjectReference: PBXObjectReference?

    /// Project root object.
    public var rootObject: PBXProject? {
        set {
            rootObjectReference = newValue?.reference
        }
        get {
            rootObjectReference?.getObject()
        }
    }

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - rootObject: project root object.
    ///   - objectVersion: project object version.
    ///   - archiveVersion: project archive version.
    ///   - classes: project classes.
    ///   - objects: project objects
    public init(rootObject: PBXProject? = nil,
                objectVersion: UInt = Xcode.LastKnown.objectVersion,
                archiveVersion: UInt = Xcode.LastKnown.archiveVersion,
                classes: [String: Any] = [:],
                objects: [PBXObject] = []) {
        self.archiveVersion = archiveVersion
        self.objectVersion = objectVersion
        self.classes = classes
        rootObjectReference = rootObject?.reference
        self.objects = PBXObjects(objects: objects)
        if let rootGroup = try? rootGroup() {
            rootGroup.assignParentToChildren()
        }
    }

    /// Initializes the project with a path to the pbxproj file.
    ///
    /// - Parameters:
    ///   - path: Path to a pbxproj file.
    public convenience init(path: Path) throws {
        let pbxproj: PBXProj = try PBXProj.createPBXProj(path: path)
        self.init(
            rootObject: pbxproj.rootObject,
            objectVersion: pbxproj.objectVersion,
            archiveVersion: pbxproj.archiveVersion,
            classes: pbxproj.classes,
            objects: pbxproj.objects
        )
    }

    /// Initializes the project with a path to the pbxproj file.
    ///
    /// - Parameters:
    ///   - data: Data represantation of a pbxproj file.
    public convenience init(data: Data) throws {
        let pbxproj: PBXProj = try PBXProj.createPBXProj(data: data)
        self.init(
            rootObject: pbxproj.rootObject,
            objectVersion: pbxproj.objectVersion,
            archiveVersion: pbxproj.archiveVersion,
            classes: pbxproj.classes,
            objects: pbxproj.objects
        )
    }

    private init(
        rootObject: PBXProject? = nil,
        objectVersion: UInt = Xcode.LastKnown.objectVersion,
        archiveVersion: UInt = Xcode.LastKnown.archiveVersion,
        classes: [String: Any] = [:],
        objects: PBXObjects
    ) {
        self.archiveVersion = archiveVersion
        self.objectVersion = objectVersion
        self.classes = classes
        rootObjectReference = rootObject?.reference
        self.objects = objects
    }

    // MARK: - Decodable

    fileprivate enum CodingKeys: String, CodingKey {
        case archiveVersion
        case objectVersion
        case classes
        case objects
        case rootObject
    }

    public required init(from decoder: Decoder) throws {
        let objects = decoder.context.objects
        let objectReferenceRepository = decoder.context.objectReferenceRepository
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rootObjectReference: String = try container.decode(.rootObject)
        self.rootObjectReference = objectReferenceRepository.getOrCreate(reference: rootObjectReference, objects: objects)
        objectVersion = try container.decodeIntIfPresent(.objectVersion) ?? 0
        archiveVersion = try container.decodeIntIfPresent(.archiveVersion) ?? 1
        classes = try container.decodeIfPresent([String: Any].self, forKey: .classes) ?? [:]
        let objectsDictionary: [String: Any] = try container.decodeIfPresent([String: Any].self, forKey: .objects) ?? [:]
        let objectsDictionaries: [String: [String: Any]] = (objectsDictionary as? [String: [String: Any]]) ?? [:]

        let parser = PBXObjectParser(
            userInfo: decoder.userInfo
        )
        try objectsDictionaries.enumerateKeysAndObjects(options: .concurrent) { key, obj, _ in
            // swiftlint:disable force_cast
            let reference = key as! String
            let dictionary = obj as! [String: Any]
            // swiftlint:enable force_cast
            let object = try parser.parse(
                reference: reference,
                dictionary: dictionary
            )
            objects.add(object: object)
        }
        self.objects = objects

        try rootGroup()?.assignParentToChildren()
    }

    // MARK: Static Methods

    private static func createPBXProj(path: Path) throws -> PBXProj {
        let (pbxProjData, pbxProjDictionary) = try PBXProj.readPBXProj(path: path)
        let context = ProjectDecodingContext(
            pbxProjValueReader: { key in
                pbxProjDictionary[key]
            }
        )

        let plistDecoder = XcodeprojPropertyListDecoder(context: context)
        let pbxproj: PBXProj = try plistDecoder.decode(PBXProj.self, from: pbxProjData)
        try pbxproj.updateProjectName(path: path)
        return pbxproj
    }

    private static func readPBXProj(path: Path) throws -> (Data, [String: Any]) {
        let plistXML = try Data(contentsOf: path.url)
        var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
        let serialized = try PropertyListSerialization.propertyList(
            from: plistXML,
            options: .mutableContainersAndLeaves,
            format: &propertyListFormat
        )
        // swiftlint:disable:next force_cast
        let pbxProjDictionary = serialized as! [String: Any]
        return (plistXML, pbxProjDictionary)
    }

    // Data override
    private static func createPBXProj(data: Data) throws -> PBXProj {
        let (pbxProjData, pbxProjDictionary) = try PBXProj.readPBXProj(data: data)
        let context = ProjectDecodingContext(
            pbxProjValueReader: { key in
                pbxProjDictionary[key]
            }
        )

        let plistDecoder = XcodeprojPropertyListDecoder(context: context)
        let pbxproj: PBXProj = try plistDecoder.decode(PBXProj.self, from: pbxProjData)
//        try pbxproj.updateProjectName(path: path)
        return pbxproj
    }

    private static func readPBXProj(data: Data) throws -> (Data, [String: Any]) {
        let plistXML = data
        var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
        let serialized = try PropertyListSerialization.propertyList(
            from: plistXML,
            options: .mutableContainersAndLeaves,
            format: &propertyListFormat
        )
        // swiftlint:disable:next force_cast
        let pbxProjDictionary = serialized as! [String: Any]
        return (plistXML, pbxProjDictionary)
    }
}

// MARK: - Public helpers

public extension PBXProj {
    // MARK: - Properties

    var projects: [PBXProject] { Array(objects.projects.values) }
    var referenceProxies: [PBXReferenceProxy] { Array(objects.referenceProxies.values) }

    // File elements
    var fileReferences: [PBXFileReference] { Array(objects.fileReferences.values) }
    var versionGroups: [XCVersionGroup] { Array(objects.versionGroups.values) }
    var variantGroups: [PBXVariantGroup] { Array(objects.variantGroups.values) }
    var groups: [PBXGroup] { Array(objects.groups.values) }

    // Configuration
    var buildConfigurations: [XCBuildConfiguration] { Array(objects.buildConfigurations.values) }
    var configurationLists: [XCConfigurationList] { Array(objects.configurationLists.values) }

    // Targets
    var legacyTargets: [PBXLegacyTarget] { Array(objects.legacyTargets.values) }
    var aggregateTargets: [PBXAggregateTarget] { Array(objects.aggregateTargets.values) }
    var nativeTargets: [PBXNativeTarget] { Array(objects.nativeTargets.values) }
    var targetDependencies: [PBXTargetDependency] { Array(objects.targetDependencies.values) }
    var containerItemProxies: [PBXContainerItemProxy] { Array(objects.containerItemProxies.values) }
    var buildRules: [PBXBuildRule] { Array(objects.buildRules.values) }

    // Build
    var buildFiles: [PBXBuildFile] { Array(objects.buildFiles.values) }
    var copyFilesBuildPhases: [PBXCopyFilesBuildPhase] { Array(objects.copyFilesBuildPhases.values) }
    var shellScriptBuildPhases: [PBXShellScriptBuildPhase] { Array(objects.shellScriptBuildPhases.values) }
    var resourcesBuildPhases: [PBXResourcesBuildPhase] { Array(objects.resourcesBuildPhases.values) }
    var frameworksBuildPhases: [PBXFrameworksBuildPhase] { Array(objects.frameworksBuildPhases.values) }
    var headersBuildPhases: [PBXHeadersBuildPhase] { Array(objects.headersBuildPhases.values) }
    var sourcesBuildPhases: [PBXSourcesBuildPhase] { Array(objects.sourcesBuildPhases.values) }
    var carbonResourcesBuildPhases: [PBXRezBuildPhase] { Array(objects.carbonResourcesBuildPhases.values) }
    var buildPhases: [PBXBuildPhase] { Array(objects.buildPhases.values) }

    /// Returns root project.
    func rootProject() throws -> PBXProject? {
        try rootObjectReference?.getThrowingObject()
    }

    /// Returns root project's root group.
    func rootGroup() throws -> PBXGroup? {
        let project = try rootProject()
        return try project?.mainGroupReference.getThrowingObject()
    }

    /// Adds a new object to the project.
    ///
    /// - Parameter object: object to be added.
    func add(object: PBXObject) {
        objects.add(object: object)
    }

    /// Deletes an object from the project.
    ///
    /// - Parameter object: object to be deleted.
    func delete(object: PBXObject) {
        objects.delete(reference: object.reference)
    }

    /// Returns all the targets with the given name.
    ///
    /// - Parameters:
    ///   - name: target name.
    /// - Returns: targets with the given name.
    func targets(named name: String) -> [PBXTarget] {
        objects.targets(named: name)
    }

    /// Invalidates all the objects UUIDs.
    /// Those UUIDs will be generated deterministically when the project is saved.
    func invalidateUUIDs() {
        objects.invalidateReferences()
    }

    /// Runs the given closure passing each of the objects that are part of the project.
    ///
    /// - Parameter closure: closure to be run.
    func forEach(_ closure: (PBXObject) -> Void) {
        objects.forEach(closure)
    }

    /// This is a helper method for quickly adding a large number of files.
    /// It is forbidden to add a file to a group one by one using the PBXGroup method addFile(...) while you are working with this class.
    ///
    /// - Parameters:
    ///     - sourceRoot: source root path.
    ///     - closure: closure in which you get the updater and can call the add method on it.
    func batchUpdate(sourceRoot: Path, closure: (PBXBatchUpdater) throws -> Void) throws {
        let fileBatchUpdater = PBXBatchUpdater(
            objects: objects,
            sourceRoot: sourceRoot
        )
        try closure(fileBatchUpdater)
    }
}

// MARK: - Internal helpers

extension PBXProj {
    /// Infers project name from Path and sets it as project name
    ///
    /// Project name is needed for certain comments when serializing PBXProj
    ///
    /// - Parameters:
    ///   - path: path to .xcodeproj directory.
    func updateProjectName(path: Path) throws {
        guard path.parent().extension == "xcodeproj" else {
            return
        }
        let projectName = path.parent().lastComponent.split(separator: ".").first
        try rootProject()?.name = projectName.map(String.init) ?? ""
    }
}

// MARK: - Equatable

extension PBXProj: Equatable {
    public static func == (lhs: PBXProj, rhs: PBXProj) -> Bool {
        let equalClasses = NSDictionary(dictionary: lhs.classes).isEqual(to: rhs.classes)
        return lhs.archiveVersion == rhs.archiveVersion &&
            lhs.objectVersion == rhs.objectVersion &&
            equalClasses &&
            lhs.objects == rhs.objects
    }
}

// MARK: - Writable

extension PBXProj: Writable {
    public func write(path: Path, override: Bool) throws {
        try write(path: path, override: override, outputSettings: PBXOutputSettings())
    }

    public func write(path: Path, override: Bool, outputSettings: PBXOutputSettings) throws {
        let encoder = PBXProjEncoder(outputSettings: outputSettings)
        let output = try encoder.encode(proj: self)
        if override, path.exists {
            try path.delete()
        }
        try path.write(output)
    }
}
