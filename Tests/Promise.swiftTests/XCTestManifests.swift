import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(Promise_swiftTests.allTests),
    ]
}
#endif
