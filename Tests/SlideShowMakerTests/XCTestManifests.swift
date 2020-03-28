import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(SlideShowMakerTests.allTests),
    ]
}
#endif
