import Basic
import Foundation

enum OpeningError: FatalError, Equatable {
    case notFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .notFound:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .notFound(path):
            return "Couldn't open file at path \(path.pathString)"
        }
    }

    static func == (lhs: OpeningError, rhs: OpeningError) -> Bool {
        switch (lhs, rhs) {
        case let (.notFound(lhsPath), .notFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

public protocol Opening: AnyObject {
    func open(path: AbsolutePath) throws
}

public class Opener: Opening {
    // MARK: - Attributes

    private let system: Systeming

    // MARK: - Init

    public init(system: Systeming = System()) {
        self.system = system
    }

    // MARK: - Opening

    public func open(path: AbsolutePath) throws {
        if !FileHandler.shared.exists(path) {
            throw OpeningError.notFound(path)
        }
        try system.runAndPrint("/usr/bin/open", path.pathString)
    }
}
