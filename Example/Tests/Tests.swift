import XCTest
@testable import Promise_swift

/// Namespace for test helpers.
public struct Test {

    /// Executes `work` after a time `interval` on the main queue.
    public static func delay(_ interval: TimeInterval, work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            work()
        }
    }

    // Phony errors.
    public enum Error: Int, CustomNSError {
        case code13 = 13
        case code42 = 42

        public static var errorDomain: String {
            return "Promises_swift.Test.Error"
        }

        public var errorCode: Int { return rawValue }

        public var errorUserInfo: [String: Any] { return [:] }
    }
}

class Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
}

#if TESTING
extension Tests {
    func testDispatchWorkItem() {
        let workItem = DispatchWorkItem {}
        workItem.notify(queue: .main) {
//            XCTFail("Must not notify on cancel")
        }

        workItem.cancel()
        XCTAssertTrue(workItem.isCancelled)
    }

    func testDispatchWorkItem2() {
        var workItem: DispatchWorkItem? = DispatchWorkItem {}
        workItem!.notify(queue: .main) {
//            XCTFail("Must not notify on cancel")
        }

        workItem = nil
    }

    func testDispatchGroup() {
        var group: DispatchGroup? = DispatchGroup()
        group!.notify(queue: .main) {
//            XCTFail("Must not notify on cancel")
        }

        group = nil
    }

    func testDispatchPromise() {
        let exp = expectation(description: "")

        var promise: DispatchPromise<String>! = DispatchPromise(.global(qos: .background)) { (onFulfilled, onRejected) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                onFulfilled("Task is completed")
                //                onRejected(NSError(domain: "DispatchPromise.Task", code: 1, userInfo: [NSDebugDescriptionErrorKey: "Task is failed"]))
            })
        }

        promise
            .then(on: .main) { (value) in
                XCTAssertEqual(value, "Task is completed")
                print("Task is completed")
                exp.fulfill()
            }
            .catch(on: .main) { (error) in
                print(error)
                exp.fulfill()
        }

        weak var p = promise
        weak var s = promise.success
        weak var sWork = promise.success.__dispatchObject
        weak var f = promise.fail
        weak var fWork = promise.fail.__dispatchObject
        promise = nil

        waitForExpectations(timeout: 100) { (_) in
            XCTAssertNil(p)
            XCTAssertNil(s)
            XCTAssertNil(f)
            XCTAssertNil(sWork)
            XCTAssertNil(fWork)
        }
    }
    func testDispatchPromiseSimpleThen() {
        let exp = expectation(description: "")

        var promise: DispatchPromise<String>! = DispatchPromise(.global(qos: .background)) { (onFulfilled, onRejected) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                //                onFulfilled("200")
                onRejected(NSError(domain: "DispatchPromise.Task", code: 1, userInfo: [NSDebugDescriptionErrorKey: "Task is failed"]))
            })
        }

        promise.then(on: .main) { (value) -> Int in
            let v = Int(value)
            guard let intV = v else { throw NSError(domain: "", code: 1, userInfo: nil) }
            return intV
            }.then(on: .main) { (v) in
                print(v)
                exp.fulfill()
            }.catch(on: .main) { (err) in
                print(err)
                exp.fulfill()
        }

        weak var p = promise
        weak var s = promise.success
        weak var sWork = promise.success.__dispatchObject
        weak var f = promise.fail
        weak var fWork = promise.fail.__dispatchObject
        promise = nil

        waitForExpectations(timeout: 100) { (_) in
            XCTAssertNil(p)
            XCTAssertNil(s)
            XCTAssertNil(f)
            XCTAssertNil(sWork)
            XCTAssertNil(fWork)
        }
    }
    func testDispatchPromiseDispatchThen() {
        let exp = expectation(description: "")

        var promise: DispatchPromise<String>! = DispatchPromise(.global(qos: .background)) { (onFulfilled, onRejected) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                onFulfilled("__")
            })
        }

        promise.then(on: .main) { (value) in
            return DispatchPromise<String>(.global(qos: .background), { (s, f) in
                sleep(2)
                s("Slept 2 seconds")
            })
            }.then(on: .main) { (v) in
                XCTAssertEqual("Slept 2 seconds", v)
                print(v)
                exp.fulfill()
            }.catch(on: .main) { (err) in
                print(err)
                exp.fulfill()
        }

        weak var p = promise
        weak var s = promise.success
        weak var sWork = promise.success.__dispatchObject
        weak var f = promise.fail
        weak var fWork = promise.fail.__dispatchObject
        promise = nil

        waitForExpectations(timeout: 100) { (_) in
            XCTAssertNil(p)
            XCTAssertNil(s)
            XCTAssertNil(f)
            XCTAssertNil(sWork)
            XCTAssertNil(fWork)
        }
    }
}
#endif

// MARK: GOOGLE Tests

// TODO: Test invalidate behavior
extension Tests {
    func testPromiseThen() {
        let exp = expectation(description: "")

        // Act.
        let numberPromise = DispatchPromise { fulfill, _ in
            fulfill(42)
        }
        let stringPromise = numberPromise.then { number in
            return DispatchPromise { fulfill, _ in
                fulfill(String(number))
            }
        }
        typealias Block = (Int) -> [Int]
        let blockPromise = stringPromise.then { value in
            return DispatchPromise<Block> { fulfill, _ in
                fulfill({ number in
                    return [number + (Int(value) ?? 0)]
                })
            }
        }
        let finalPromise = blockPromise.then { (value: @escaping Block) -> Int? in
            return value(42).first
        }
        let postFinalPromise = finalPromise.then { number -> Int in
            defer { exp.fulfill() }
            return number ?? 0
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertEqual(numberPromise.value, 42)
            XCTAssertNil(numberPromise.error)
            XCTAssertEqual(stringPromise.value, "42")
            XCTAssertNil(stringPromise.error)
            XCTAssertNotNil(blockPromise.value)
            let array = blockPromise.value?(42) ?? []
            XCTAssertEqual(array.count, 1)
            XCTAssertEqual(array.first, 84)
            XCTAssertNil(blockPromise.error)
            XCTAssertEqual(finalPromise.value ?? 0, 84)
            XCTAssertNil(finalPromise.error)
            XCTAssertEqual(postFinalPromise.value, 84)
            XCTAssertNil(postFinalPromise.error)
        }
    }

    func testPromiseAsyncFulfill() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise { fulfill, _ in
            Test.delay(0.1) {
                fulfill(42)
            }
            }.then { number in
                XCTAssertEqual(number, 42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertEqual(promise.value, 42)
            XCTAssertNil(promise.error)
        }
    }

    func testPromiseChainedFulfill() {
        let exp = expectation(description: "")
        // Arrange.
        var count = 0

        // Act.
        let promise = DispatchPromise<Int> {
            let number = 42
            return number
            }.then { value in
                XCTAssertEqual(value, 42)
                count += 1
            }.then { value in
                XCTAssertEqual(value, 42)
                count += 1
            }.then { value in
                XCTAssertEqual(value, 42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertEqual(count, 2)
            XCTAssertEqual(promise.value, 42)
            XCTAssertNil(promise.error)
        }
    }

    func testPromiseChainedAsyncFulfill() {
        let exp = expectation(description: "")
        // Arrange.
        var count = 0

        // Act.
        let promise = DispatchPromise { fulfill, _ in
            Test.delay(0.1) {
                fulfill(42)
            }
            }.then { value in
                XCTAssertEqual(value, 42)
                count += 1
            }.then { value in
                XCTAssertEqual(value, 42)
                count += 1
            }.then { value in
                XCTAssertEqual(value, 42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertEqual(count, 2)
            XCTAssertEqual(promise.value, 42)
            XCTAssertNil(promise.error)
        }
    }

    func testPromiseNoThenOnPending() {
        // Arrange.
        let expectation = self.expectation(description: "")

        // Act.
        let promise = DispatchPromise<Void>.pending()

        let thenPromise = promise.then { _ in
            XCTFail()
        }
        Test.delay(0.1) {
            expectation.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10)
        XCTAssert(promise.isPending)
        XCTAssertNil(promise.value)
        XCTAssertNil(promise.error)
        XCTAssert(thenPromise.isPending)
        XCTAssertNil(thenPromise.value)
        XCTAssertNil(thenPromise.error)
    }

    func testPromiseNoDoubleFulfill() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise<Int> { fulfill, _ in
            Test.delay(0.1) {
                fulfill(42)
                fulfill(13)
            }
            }.then { value in
                XCTAssertEqual(value, 42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertEqual(promise.value, 42)
            XCTAssertNil(promise.error)
        }
    }

    func testPromiseThenInitiallyFulfilled() {
        let exp = expectation(description: "")
        // Act.
        let initiallyFulfilledPromise = DispatchPromise(42)
        let promise = initiallyFulfilledPromise.then { value in
            XCTAssertEqual(value, 42)
            exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertEqual(initiallyFulfilledPromise.value, 42)
            XCTAssertNil(initiallyFulfilledPromise.error)
            XCTAssertEqual(promise.value, 42)
            XCTAssertNil(promise.error)
        }
    }

    func testPromiseThenNoDeallocUntilFulfilled() {
        let exp = expectation(description: "")
        // Arrange.
        let promise = DispatchPromise<Int>.pending()
        weak var weakExtendedPromise1: DispatchPromise<Int>?
        weak var weakExtendedPromise2: DispatchPromise<Int>?

        // Act.
        autoreleasepool {
            XCTAssertNil(weakExtendedPromise1)
            XCTAssertNil(weakExtendedPromise2)
            weakExtendedPromise1 = promise.then { _ in }
            weakExtendedPromise2 = promise.then { _ in }
            XCTAssertNotNil(weakExtendedPromise1)
            XCTAssertNotNil(weakExtendedPromise2)
        }

        // Assert.
        XCTAssertNotNil(weakExtendedPromise1)
        XCTAssertNotNil(weakExtendedPromise2)

        promise.fulfill(42)
        promise.then { (_) in
            exp.fulfill()
        }
        waitForExpectations(timeout: 100) { (e) in
            XCTAssertNil(e)
            XCTAssertNil(weakExtendedPromise1)
            XCTAssertNil(weakExtendedPromise2)
        }
    }
}
