import XCTest
import MereKit
@testable import MereCore

@MainActor
final class TabTests: XCTestCase {
    func testOpenTab() async {
        let mock = MockWebContent()
        let tab = Tab(content: mock)
        XCTAssertEqual(tab.engine, .webkit)
        XCTAssertNil(tab.title)
    }
}
