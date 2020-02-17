import Foundation
import XCTest
import TuistSupport
import TuistCore
import TuistSupportTesting
import TuistCoreTesting
import TuistCacheTesting

@testable import TuistKit

final class CacheControllerTests: XCTestCase {
    
    var generator: MockGenerator!
    var xcframeworkBuilder: MockXCFrameworkBuilder!
    var cache: MockCacheStorage!
}
