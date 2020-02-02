import Basic
import Foundation

public enum SDKStatus {
    case required
    case optional
}

public enum SDKSource {
    case developer
    case system

    public var path: String {
        switch self {
        case .developer:
            return "Platforms/iPhoneOS.platform/Developer/Library"
        case .system:
            return "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library"
        }
    }
}

public enum Dependency: Equatable, Hashable {
    case target(name: String)
    case project(target: String, path: AbsolutePath)
    case framework(path: AbsolutePath)
    case xcFramework(path: AbsolutePath)
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?)
    case package(product: String)
    case sdk(name: String, status: SDKStatus, source: SDKSource)
    case cocoapods(path: AbsolutePath)
}
