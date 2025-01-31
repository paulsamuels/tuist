import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSupport
import XcodeProj

struct ProjectConstants {
    var objectVersion: UInt
    var archiveVersion: UInt
}

extension ProjectConstants {
    static var xcode10: ProjectConstants {
        ProjectConstants(objectVersion: 50,
                         archiveVersion: Xcode.LastKnown.archiveVersion)
    }

    static var xcode11: ProjectConstants {
        ProjectConstants(objectVersion: 52,
                         archiveVersion: Xcode.LastKnown.archiveVersion)
    }
}

protocol ProjectGenerating: AnyObject {
    /// Generates the given project.
    /// - Parameters:
    ///   - project: Project to be generated.
    ///   - graph: Dependencies graph.
    ///   - sourceRootPath: Directory where the files are relative to.
    ///   - xcodeprojPath: Path to the Xcode project. When not given, the xcodeproj is generated at sourceRootPath.
    func generate(project: Project,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?,
                  xcodeprojPath: AbsolutePath?) throws -> GeneratedProject
}

// swiftlint:disable type_body_length
final class ProjectGenerator: ProjectGenerating {
    // MARK: - Attributes

    /// Generator for the project targets.
    let targetGenerator: TargetGenerating

    /// Generator for the project configuration.
    let configGenerator: ConfigGenerating

    /// Generator for the project schemes.
    let schemesGenerator: SchemesGenerating

    /// Generator for the project derived files.
    let derivedFileGenerator: DerivedFileGenerating

    // MARK: - Init

    /// Initializes the project generator with its attributes.
    ///
    /// - Parameters:
    ///   - targetGenerator: Generator for the project targets.
    ///   - configGenerator: Generator for the project configuration.
    ///   - schemesGenerator: Generator for the project schemes.
    ///   - derivedFileGenerator: Generator for the project derived files.
    init(targetGenerator: TargetGenerating = TargetGenerator(),
         configGenerator: ConfigGenerating = ConfigGenerator(),
         schemesGenerator: SchemesGenerating = SchemesGenerator(),
         derivedFileGenerator: DerivedFileGenerating = DerivedFileGenerator()) {
        self.targetGenerator = targetGenerator
        self.configGenerator = configGenerator
        self.schemesGenerator = schemesGenerator
        self.derivedFileGenerator = derivedFileGenerator
    }

    // MARK: - ProjectGenerating

    func generate(project: Project,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath? = nil,
                  xcodeprojPath: AbsolutePath? = nil) throws -> GeneratedProject {
        Printer.shared.print("Generating project \(project.name)")

        // Getting the path.
        let sourceRootPath = sourceRootPath ?? project.path

        // If the xcodeproj path is not given, we generate it under the source root path.
        let xcodeprojPath = xcodeprojPath ?? sourceRootPath.appending(component: "\(project.fileName).xcodeproj")

        // Project and workspace.
        return try generateProjectAndWorkspace(project: project,
                                               graph: graph,
                                               sourceRootPath: sourceRootPath,
                                               xcodeprojPath: xcodeprojPath)
    }

    // MARK: - Fileprivate

    // swiftlint:disable:next function_body_length
    private func generateProjectAndWorkspace(project: Project,
                                             graph: Graphing,
                                             sourceRootPath: AbsolutePath,
                                             xcodeprojPath: AbsolutePath) throws -> GeneratedProject {
        // Derived files
        let (project, deleteOldDerivedFiles) = try derivedFileGenerator.generate(graph: graph, project: project, sourceRootPath: sourceRootPath)

        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let projectConstants = try determineProjectConstants(graph: graph)
        let pbxproj = PBXProj(objectVersion: projectConstants.objectVersion,
                              archiveVersion: projectConstants.archiveVersion,
                              classes: [:])

        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            xcodeprojPath: xcodeprojPath,
                                            sourceRootPath: sourceRootPath)

        let fileElements = ProjectFileElements()
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj,
                                              sourceRootPath: sourceRootPath)

        let configurationList = try configGenerator.generateProjectConfig(project: project, pbxproj: pbxproj, fileElements: fileElements)
        let pbxProject = try generatePbxproject(project: project,
                                                projectFileElements: fileElements,
                                                configurationList: configurationList,
                                                groups: groups,
                                                pbxproj: pbxproj)

        let nativeTargets = try generateTargets(project: project,
                                                pbxproj: pbxproj,
                                                pbxProject: pbxProject,
                                                fileElements: fileElements,
                                                sourceRootPath: sourceRootPath,
                                                graph: graph)

        generateTestTargetIdentity(project: project,
                                   pbxproj: pbxproj,
                                   pbxProject: pbxProject)

        try generateSwiftPackageReferences(project: project,
                                           pbxproj: pbxproj,
                                           pbxProject: pbxProject)
        try deleteOldDerivedFiles()

        return try write(xcodeprojPath: xcodeprojPath,
                         nativeTargets: nativeTargets,
                         workspace: workspace,
                         pbxproj: pbxproj,
                         project: project,
                         graph: graph)
    }

    private func generatePbxproject(project: Project,
                                    projectFileElements: ProjectFileElements,
                                    configurationList: XCConfigurationList,
                                    groups: ProjectGroups,
                                    pbxproj: PBXProj) throws -> PBXProject {
        let defaultRegions = ["en", "Base"]
        let knownRegions = Set(defaultRegions + projectFileElements.knownRegions).sorted()
        let pbxProject = PBXProject(name: project.name,
                                    buildConfigurationList: configurationList,
                                    compatibilityVersion: Xcode.Default.compatibilityVersion,
                                    mainGroup: groups.sortedMain,
                                    developmentRegion: Xcode.Default.developmentRegion,
                                    hasScannedForEncodings: 0,
                                    knownRegions: knownRegions,
                                    productsGroup: groups.products,
                                    projectDirPath: "",
                                    projects: [],
                                    projectRoots: [],
                                    targets: [])
        pbxproj.add(object: pbxProject)
        pbxproj.rootObject = pbxProject
        return pbxProject
    }

    private func generateTargets(project: Project,
                                 pbxproj: PBXProj,
                                 pbxProject: PBXProject,
                                 fileElements: ProjectFileElements,
                                 sourceRootPath: AbsolutePath,
                                 graph: Graphing) throws -> [String: PBXNativeTarget] {
        var nativeTargets: [String: PBXNativeTarget] = [:]
        try project.targets.forEach { target in
            let nativeTarget = try targetGenerator.generateTarget(target: target,
                                                                  pbxproj: pbxproj,
                                                                  pbxProject: pbxProject,
                                                                  projectSettings: project.settings,
                                                                  fileElements: fileElements,
                                                                  path: project.path,
                                                                  sourceRootPath: sourceRootPath,
                                                                  graph: graph)
            nativeTargets[target.name] = nativeTarget
        }

        /// Target dependencies
        try targetGenerator.generateTargetDependencies(path: project.path,
                                                       targets: project.targets,
                                                       nativeTargets: nativeTargets,
                                                       graph: graph)
        return nativeTargets
    }

    private func generateTestTargetIdentity(project _: Project,
                                            pbxproj: PBXProj,
                                            pbxProject: PBXProject) {
        func testTargetName(_ target: PBXTarget) -> String? {
            guard let buildConfigurations = target.buildConfigurationList?.buildConfigurations else {
                return nil
            }

            return buildConfigurations
                .compactMap { $0.buildSettings["TEST_TARGET_NAME"] as? String }
                .first
        }

        let testTargets = pbxproj.nativeTargets.filter { $0.productType == .uiTestBundle || $0.productType == .unitTestBundle }

        for testTarget in testTargets {
            guard let name = testTargetName(testTarget) else {
                continue
            }

            guard let target = pbxproj.targets(named: name).first else {
                continue
            }

            var attributes = pbxProject.targetAttributes[testTarget] ?? [:]

            attributes["TestTargetID"] = target

            pbxProject.setTargetAttributes(attributes, target: testTarget)
        }
    }

    private func generateSwiftPackageReferences(project: Project, pbxproj: PBXProj, pbxProject: PBXProject) throws {
        var packageReferences: [String: XCRemoteSwiftPackageReference] = [:]

        for package in project.packages {
            switch package {
            case let .local(path):

                let reference = PBXFileReference(
                    sourceTree: .group,
                    name: path.components.last,
                    lastKnownFileType: "folder",
                    path: path.pathString
                )

                pbxproj.add(object: reference)
                try pbxproj.rootGroup()?.children.append(reference)

            case let .remote(url: url, requirement: requirement):
                let packageReference = XCRemoteSwiftPackageReference(
                    repositoryURL: url,
                    versionRequirement: requirement.xcodeprojValue
                )
                packageReferences[url] = packageReference
                pbxproj.add(object: packageReference)
            }
        }

        pbxProject.packages = packageReferences.sorted { $0.key < $1.key }.map { $1 }
    }

    private func write(xcodeprojPath: AbsolutePath,
                       nativeTargets: [String: PBXNativeTarget],
                       workspace: XCWorkspace,
                       pbxproj: PBXProj,
                       project: Project,
                       graph: Graphing) throws -> GeneratedProject {
        let fileHandler = FileHandler.shared
        func write(xcodeprojPath: AbsolutePath) throws -> GeneratedProject {
            let generatedProject = GeneratedProject(pbxproj: pbxproj,
                                                    path: xcodeprojPath,
                                                    targets: nativeTargets,
                                                    name: xcodeprojPath.basename)
            try writeXcodeproj(workspace: workspace,
                               pbxproj: pbxproj,
                               xcodeprojPath: xcodeprojPath)

            try writeSchemes(project: project,
                             generatedProject: generatedProject,
                             xcprojectPath: xcodeprojPath,
                             graph: graph)

            return generatedProject
        }

        guard fileHandler.exists(xcodeprojPath) else {
            return try write(xcodeprojPath: xcodeprojPath)
        }

        var generatedProject: GeneratedProject!
        try fileHandler.inTemporaryDirectory { temporaryPath in
            let temporaryPath = temporaryPath.appending(component: xcodeprojPath.basename)
            generatedProject = try write(xcodeprojPath: temporaryPath)

            let pathsToReplace = self.pathsToReplace(xcodeProjPath: temporaryPath)
            try pathsToReplace.forEach {
                let relativeFile = $0.relative(to: temporaryPath)
                let writeToPath = xcodeprojPath.appending(relativeFile)
                try fileHandler.createFolder(writeToPath.parentDirectory)
                try fileHandler.replace(writeToPath, with: $0)
            }
        }

        return generatedProject.at(path: xcodeprojPath)
    }

    private func pathsToReplace(xcodeProjPath: AbsolutePath) -> [AbsolutePath] {
        var paths = [
            "project.pbxproj",
            "project.xcworkspace",
            "xcshareddata/xcschemes",
        ]

        if FileHandler.shared.exists(xcodeProjPath.appending(component: "xcuserdata")) {
            paths.append("xcuserdata/**/*.xcscheme")
        }

        return paths.flatMap {
            FileHandler.shared.glob(xcodeProjPath, glob: $0)
        }
    }

    private func writeXcodeproj(workspace: XCWorkspace,
                                pbxproj: PBXProj,
                                xcodeprojPath: AbsolutePath) throws {
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: xcodeprojPath.path)
    }

    private func writeSchemes(project: Project,
                              generatedProject: GeneratedProject,
                              xcprojectPath: AbsolutePath,
                              graph: Graphing) throws {
        try schemesGenerator.generateProjectSchemes(project: project,
                                                    xcprojectPath: xcprojectPath,
                                                    generatedProject: generatedProject,
                                                    graph: graph)
    }

    private func determineProjectConstants(graph: Graphing) throws -> ProjectConstants {
        if !graph.packages.isEmpty {
            return .xcode11
        } else {
            return .xcode10
        }
    }
}
