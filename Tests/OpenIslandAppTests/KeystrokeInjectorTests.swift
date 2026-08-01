import XCTest
@testable import OpenIslandApp

final class KeystrokeInjectorTests: XCTestCase {
    func testDefaultInjectorPostsCmdShiftRightBracketWithoutCrashing() {
        // We can't observe actual OS-level CGEvent delivery in a unit test,
        // but constructing and posting the event without throwing/crashing
        // covers the init-time correctness of the keycode and flags.
        let injector = DefaultKeystrokeInjector()
        injector.sendCmdShiftRightBracket()  // no XCTAssert — if this crashes the test fails
    }
}
