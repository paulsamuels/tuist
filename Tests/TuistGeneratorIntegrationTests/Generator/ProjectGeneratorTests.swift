import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectGeneratorTests: TuistUnitTestCase {
    var subject: ProjectGenerator!

    override func setUp() {
        super.setUp()
        subject = ProjectGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = Target.test(name: "Target", platform: .iOS, product: .framework, infoPlist: .dictionary(["a": "b"]))
        let targets = [target]
        let project = Project.test(path: temporaryPath, name: "Project", targets: targets)
        try FileHandler.shared.touch(temporaryPath.appending(component: "Project.swift"))

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: temporaryPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let schemesPath = got.path.appending(RelativePath("xcshareddata/xcschemes"))
        let targetScheme = schemesPath.appending(component: "Target.xcscheme")
        XCTAssertTrue(FileHandler.shared.exists(targetScheme))
        XCTAssertTrue(FileHandler.shared.exists(got.path.appending(RelativePath("../Derived/InfoPlists/Target.plist"))))
    }

    func test_generate_doesNotWipeUserData() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let paths = try createFiles([
            "Foo.xcodeproj/xcuserdata/a",
            "Foo.xcodeproj/xcuserdata/b/c",
        ])

        let target = Target.test(name: "Target", platform: .iOS, product: .framework)
        let project = Project.test(path: temporaryPath, name: "Foo", targets: [target])

        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: target, dependencies: []),
                                 ])

        // When
        try (0 ..< 2).forEach { _ in
            _ = try subject.generate(project: project, graph: graph)
        }

        // Then
        XCTAssertTrue(paths.allSatisfy { FileHandler.shared.exists($0) })
    }

    func test_generate_replacesSchemes() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let schemeA = Scheme(name: "SchemeA", shared: true)
        let schemeB = Scheme(name: "SchemeB", shared: true)
        let userScheme = Scheme(name: "UserScheme", shared: false)

        func makeModels(with schemes: [Scheme]) -> (graph: Graph, project: Project) {
            let target = Target.test(name: "Target", platform: .iOS, product: .framework)
            let project = Project.test(path: temporaryPath, name: "Foo", targets: [target], schemes: schemes)
            let graph = Graph.create(project: project,
                                     dependencies: [
                                         (target: target, dependencies: []),
                                     ])
            return (graph, project)
        }

        let generations = [
            [schemeA, schemeB],
            [schemeA, userScheme],
        ]

        // When
        try generations.forEach {
            let (graph, project) = makeModels(with: $0)
            _ = try subject.generate(project: project, graph: graph)
        }

        // Then
        let fileHandler = FileHandler.shared
        let schemesPath = temporaryPath.appending(RelativePath("Foo.xcodeproj"))
        let schemes = fileHandler.glob(schemesPath, glob: "**/*.xcscheme").map { $0.relative(to: schemesPath).basename }
        XCTAssertEqual(schemes, [
            "SchemeA.xcscheme",
            "Target.xcscheme",
            "UserScheme.xcscheme",
        ])
    }

    func test_generate_scheme() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = Target.test(name: "Target", platform: .iOS, product: .framework)
        let sharedScheme = Scheme.test(name: "Target-Scheme", shared: true, buildAction: BuildAction(targets: [TargetReference(projectPath: temporaryPath, name: "Target")]))

        let targets = [target]
        let project = Project.test(path: temporaryPath, name: "Project", targets: targets, schemes: [sharedScheme])
        try FileHandler.shared.touch(temporaryPath.appending(component: "Project.swift"))

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: temporaryPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let schemesPath = got.path.appending(RelativePath("xcshareddata/xcschemes"))
        let targetScheme = schemesPath.appending(component: "Target-Scheme.xcscheme")
        XCTAssertTrue(FileHandler.shared.exists(targetScheme))
    }

    func test_generate_local_scheme() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = Target.test(name: "Target", platform: .iOS, product: .framework)
        let localScheme = Scheme.test(name: "Target-Local", shared: false, buildAction: BuildAction(targets: [TargetReference(projectPath: temporaryPath, name: "Target")]))

        let targets = [target]
        let project = Project.test(path: temporaryPath, name: "Project", targets: targets, schemes: [localScheme])
        try FileHandler.shared.touch(temporaryPath.appending(component: "Project.swift"))

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: temporaryPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let username = NSUserName()
        let userSchemesPath = got.path.appending(RelativePath("xcuserdata/\(username).xcuserdatad/xcschemes"))
        let userScheme = userSchemesPath.appending(component: "Target-Local.xcscheme")
        XCTAssertTrue(FileHandler.shared.exists(userScheme))
    }

    func test_generate_testTargetIdentity() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let app = Target.test(name: "App",
                              platform: .iOS,
                              product: .app)
        let test = Target.test(name: "Tests",
                               platform: .iOS,
                               product: .unitTests)
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   targets: [app, test])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: temporaryPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: test,
                                                       dependencies: [
                                                           TargetNode(project: project, target: app, dependencies: []),
                                                       ])])

        // When
        let generatedProject = try subject.generate(project: project, graph: graph)

        // Then
        let pbxproject = try generatedProject.pbxproj.rootProject()
        let nativeTargets = generatedProject.targets
        let attributes = pbxproject?.targetAttributes ?? [:]
        XCTAssertTrue(attributes.contains { attribute in

            guard let app = nativeTargets["App"], let testTargetID = attribute.value["TestTargetID"] as? PBXNativeTarget else {
                return false
            }

            return attribute.key.name == "Tests" && testTargetID == app

        }, "Test target is missing from target attributes.")
    }

    func test_generate_testUsingFileName() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        try FileHandler.shared.touch(temporaryPath.appending(component: "Project.swift"))
        let target = Target.test()
        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: temporaryPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        XCTAssertTrue(FileHandler.shared.exists(got.path))
        XCTAssertEqual(got.path.components.last, "SomeAwesomeName.xcodeproj")
        XCTAssertEqual(project.name, "Project")
    }

    func test_objectVersion_when_xcode11_and_spm() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [.test(dependencies: [.package(product: "A")])],
                                   packages: [.remote(url: "A", requirement: .exact("0.1"))])

        let target = Target.test()
        let cache = GraphLoaderCache()
        cache.add(project: project)
        let packageNode = PackageNode(package: .remote(url: "A", requirement: .exact("0.1")),
                                      path: temporaryPath)
        let graph = Graph.test(entryPath: temporaryPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [packageNode])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        XCTAssertEqual(got.pbxproj.objectVersion, 52)
        XCTAssertEqual(got.pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode11() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        let graph = Graph.test(entryPath: temporaryPath)

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        XCTAssertEqual(got.pbxproj.objectVersion, 50)
        XCTAssertEqual(got.pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode10() throws {
        xcodeController.selectedVersionStub = .success(Version(10, 2, 1))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        let graph = Graph.test(entryPath: temporaryPath)

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        XCTAssertEqual(got.pbxproj.objectVersion, 50)
        XCTAssertEqual(got.pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_knownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(entryPath: path)
        let resources = [
            "resources/en.lproj/App.strings",
            "resources/en.lproj/Extension.strings",
            "resources/fr.lproj/App.strings",
            "resources/fr.lproj/Extension.strings",
            "resources/Base.lproj/App.strings",
            "resources/Base.lproj/Extension.strings",
        ]
        let project = Project.test(path: path,
                                   targets: [
                                       .test(resources: resources.map {
                                           .file(path: path.appending(RelativePath($0)))
                                       }),
                                   ])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxProject = try XCTUnwrap(try got.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.knownRegions, [
            "Base",
            "en",
            "fr",
        ])
    }

    func test_generate_setsDefaultKnownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(entryPath: path)
        let project = Project.test(path: path,
                                   targets: [])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxProject = try XCTUnwrap(try got.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.knownRegions, [
            "Base",
            "en",
        ])
    }
}
