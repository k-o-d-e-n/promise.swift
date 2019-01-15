import XCTest
@testable import Promise_swift

/// Namespace for test helpers.
struct Test {

    /// Executes `work` after a time `interval` on the main queue.
    static func delay(_ interval: TimeInterval, work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            work()
        }
    }

    // Phony errors.
    enum Error: Int, Swift.Error, Equatable {
        case code13 = 13
        case code42 = 42

        public static func ==(lhs: Error, rhs: Error) -> Bool {
            return lhs.rawValue == rhs.rawValue
        }
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
        let promise = DispatchPromise<Void>()

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
        let promise = DispatchPromise<Int>()
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

// MARK: All

/// Compare two arrays of the same generic type conforming to `Equatable` protocol.
public func == <T: Equatable>(lhs: [T?], rhs: [T?]) -> Bool {
    if lhs.count != rhs.count { return false }
    for (l, r) in zip(lhs, rhs) where l != r { return false }
    return true
}

public func != <T: Equatable>(lhs: [T?], rhs: [T?]) -> Bool {
    return !(lhs == rhs)
}

class PromiseAllTests: XCTestCase {
    func testPromiseAll() {
        let exp = expectation(description: "")
        // Arrange.
        let expectedValues: [Int?] = [42, 13, nil]
        let promise1 = DispatchPromise<Int?> { fulfill, _ in
            Test.delay(0.1) {
                fulfill(42)
            }
        }
        let promise2 = DispatchPromise<Int?> { fulfill, _ in
            Test.delay(1) {
                fulfill(13)
            }
        }
        let promise3 = DispatchPromise<Int?> { fulfill, _ in
            Test.delay(2) {
                fulfill(nil)
            }
        }

        // Act.
        let combinedPromise = DispatchPromise<[Int?]>.all([promise1, promise2, promise3]).then { value in
            XCTAssert(value == expectedValues)
            exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            guard let value = combinedPromise.value else { XCTFail(); return }
            XCTAssert(value == expectedValues)
            XCTAssertNil(combinedPromise.error)
        }
    }

    func testPromiseAllEmpty() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise<[Any]>.all([DispatchPromise<Any>]()).then { value in
            XCTAssert(value.isEmpty)
            exp.fulfill()
        }

        // Assert.

        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssert(promise.value?.isEmpty ?? false)
            XCTAssertNil(promise.error)
        }
    }

    func testPromiseAllRejectFirst() {
        let exp = expectation(description: "")
        // Arrange.
        let promise1 = DispatchPromise { fulfill, _ in
            Test.delay(1) {
                fulfill(42)
            }
        }
        let promise2 = DispatchPromise<Int> { _, reject in
            Test.delay(0.1) {
                reject(Test.Error.code42)
            }
        }

        // Act.
        let combinedPromise = DispatchPromise<[Int]>.all([ promise1, promise2 ])
            .then { v in
                print(v)
                XCTFail()
            }
            .catch { error in
                print(error)
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.

        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((combinedPromise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(combinedPromise.value)
        }
    }

    func testPromiseAllRejectLast() {
        let exp = expectation(description: "")
        // Arrange.
        let promise1 = DispatchPromise { fulfill, _ in
            Test.delay(0.1) {
                fulfill(42)
            }
        }
        let promise2 = DispatchPromise<Int> { _, reject in
            Test.delay(1) {
                reject(Test.Error.code42)
            }
        }

        // Act.
        let combinedPromise = DispatchPromise<[Int]>.all([promise1, promise2]).then { _ in
            XCTFail()
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.

        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((combinedPromise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(combinedPromise.value)
        }
    }

    func testPromiseAllNoDeallocUntilResolved() {
        let exp = expectation(description: "")
        // Arrange.
        let promise = DispatchPromise<Int>()
        weak var weakExtendedPromise1: DispatchPromise<[Int]>?
        weak var weakExtendedPromise2: DispatchPromise<[Int]>?

        // Act.
        autoreleasepool {
            XCTAssertNil(weakExtendedPromise1)
            XCTAssertNil(weakExtendedPromise2)
            weakExtendedPromise1 = .all([promise])
            weakExtendedPromise2 = .all([promise])
            XCTAssertNotNil(weakExtendedPromise1)
            XCTAssertNotNil(weakExtendedPromise2)
        }

        // Assert.
        XCTAssertNotNil(weakExtendedPromise1)
        XCTAssertNotNil(weakExtendedPromise2)

        promise.fulfill(42)
        promise.then { (_) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                exp.fulfill()
            })
        }

        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)

            XCTAssertNil(weakExtendedPromise1)
            XCTAssertNil(weakExtendedPromise2)
        }
    }

//    func testPromiseAllHeterogeneous2() {
//        // Arrange.
//        let expectedValues = (42, "hello world")
//        let promise1 = DispatchPromise<Int> { fulfill, _ in
//            Test.delay(0.1) {
//                fulfill(42)
//            }
//        }
//        let promise2 = DispatchPromise<String> { fulfill, _ in
//            Test.delay(1) {
//                fulfill("hello world")
//            }
//        }
//
//        // Act.
//        let combinedPromise = DispatchPromise.all(promise1, promise2).then { value in
//            XCTAssert(value == expectedValues)
//        }
//
//        // Assert.
//        XCTAssert(waitForPromises(timeout: 10))
//        guard let value = combinedPromise.value else { XCTFail(); return }
//        XCTAssert(value == expectedValues)
//        XCTAssertNil(combinedPromise.error)
//    }

//    func testPromiseAllHeterogeneous2Reject() {
//        // Arrange.
//        let promise1 = DispatchPromise<Int> { fulfill, _ in
//            Test.delay(1) {
//                fulfill(42)
//            }
//        }
//        let promise2 = DispatchPromise<String> { _, reject in
//            Test.delay(0.1) {
//                reject(Test.Error.code42)
//            }
//        }
//
//        // Act.
//        let combinedPromise = DispatchPromise.all(promise1, promise2).then { _ in
//            XCTFail()
//            }.catch { error in
//                XCTAssertTrue(error == Test.Error.code42)
//        }
//
//        // Assert.
//        XCTAssert(waitForPromises(timeout: 10))
//        XCTAssertTrue(combinedPromise.error == Test.Error.code42)
//        XCTAssertNil(combinedPromise.value)
//    }

//    func testPromiseAllHeterogeneous2NoDeallocUntilResolved() {
//        // Arrange.
//        let promise1 = DispatchPromise<Int>()
//        let promise2 = DispatchPromise<String>()
//        weak var weakExtendedPromise1: DispatchPromise<(Int, String)>?
//        weak var weakExtendedPromise2: DispatchPromise<(Int, String)>?
//
//        // Act.
//        autoreleasepool {
//            XCTAssertNil(weakExtendedPromise1)
//            XCTAssertNil(weakExtendedPromise2)
//            weakExtendedPromise1 = DispatchPromise.all(promise1, promise2)
//            weakExtendedPromise2 = DispatchPromise.all(promise1, promise2)
//            XCTAssertNotNil(weakExtendedPromise1)
//            XCTAssertNotNil(weakExtendedPromise2)
//        }
//
//        // Assert.
//        XCTAssertNotNil(weakExtendedPromise1)
//        XCTAssertNotNil(weakExtendedPromise2)
//
//        promise1.fulfill(42)
//        promise2.fulfill("hello world")
//        XCTAssert(waitForPromises(timeout: 10))
//
//        XCTAssertNil(weakExtendedPromise1)
//        XCTAssertNil(weakExtendedPromise2)
//    }

//    func testPromiseAllHeterogeneous3() {
//        // Arrange.
//        let expectedValues = (42, "hello world", Int?.none)
//        let promise1 = DispatchPromise<Int> { fulfill, _ in
//            Test.delay(0.1) {
//                fulfill(42)
//            }
//        }
//        let promise2 = DispatchPromise<String> { fulfill, _ in
//            Test.delay(1) {
//                fulfill("hello world")
//            }
//        }
//        let promise3 = DispatchPromise<Int?> { fulfill, _ in
//            Test.delay(2) {
//                fulfill(nil)
//            }
//        }
//
//        // Act.
//        let combinedPromise = DispatchPromise.all(promise1, promise2, promise3).then { number, string, none in
//            XCTAssert(number == expectedValues.0)
//            XCTAssert(string == expectedValues.1)
//            XCTAssert(none == expectedValues.2)
//        }
//
//        // Assert.
//        XCTAssert(waitForPromises(timeout: 10))
//        guard let value = combinedPromise.value else { XCTFail(); return }
//        XCTAssert(value.0 == expectedValues.0)
//        XCTAssert(value.1 == expectedValues.1)
//        XCTAssert(value.2 == expectedValues.2)
//        XCTAssertNil(combinedPromise.error)
//    }

//    func testPromiseAllHeterogeneous3Reject() {
//        // Arrange.
//        let promise1 = DispatchPromise { fulfill, _ in
//            Test.delay(0.1) {
//                fulfill(42)
//            }
//        }
//        let promise2 = DispatchPromise<String> { _, reject in
//            Test.delay(1) {
//                reject(Test.Error.code42)
//            }
//        }
//        let promise3 = DispatchPromise<Int?> { fulfill, _ in
//            Test.delay(2) {
//                fulfill(nil)
//            }
//        }
//
//        // Act.
//        let combinedPromise = DispatchPromise.all(promise1, promise2, promise3).then { _ in
//            XCTFail()
//            }.catch { error in
//                XCTAssertTrue(error == Test.Error.code42)
//        }
//
//        // Assert.
//        XCTAssert(waitForPromises(timeout: 10))
//        XCTAssertTrue(combinedPromise.error == Test.Error.code42)
//        XCTAssertNil(combinedPromise.value)
//    }

//    func testPromiseAllHeterogeneous3NoDeallocUntilResolved() {
//        // Arrange.
//        let promise1 = DispatchPromise<Int>()
//        let promise2 = DispatchPromise<String>()
//        let promise3 = DispatchPromise<Int?>()
//        weak var weakExtendedPromise1: DispatchPromise<(Int, String, Int?)>?
//        weak var weakExtendedPromise2: DispatchPromise<(Int, String, Int?)>?
//
//        // Act.
//        autoreleasepool {
//            XCTAssertNil(weakExtendedPromise1)
//            XCTAssertNil(weakExtendedPromise2)
//            weakExtendedPromise1 = DispatchPromise.all(promise1, promise2, promise3)
//            weakExtendedPromise2 = DispatchPromise.all(promise1, promise2, promise3)
//            XCTAssertNotNil(weakExtendedPromise1)
//            XCTAssertNotNil(weakExtendedPromise2)
//        }
//
//        // Assert.
//        XCTAssertNotNil(weakExtendedPromise1)
//        XCTAssertNotNil(weakExtendedPromise2)
//
//        promise1.fulfill(42)
//        promise2.fulfill("hello world")
//        promise3.fulfill(nil)
//        XCTAssert(waitForPromises(timeout: 10))
//
//        XCTAssertNil(weakExtendedPromise1)
//        XCTAssertNil(weakExtendedPromise2)
//    }
}

class PromiseCatchTests: XCTestCase {
//    func testPromiseDoesNotCallThenAfterReject() {
//        let exp = expectation(description: "")
//        // Act.
//        let promise = DispatchPromise<AnyObject> {
//            return Test.Error.code42 as AnyObject
//            }.then { _ in
//                XCTFail()
//            }.then {
//                XCTFail()
//            }.then {
//                XCTFail()
//            }.catch { error in
//                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
//                exp.fulfill()
//        }
//
//        // Assert.
//        waitForExpectations(timeout: 10) { (err) in
//            XCTAssertNil(err)
//            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
//            XCTAssertTrue(promise.value == nil)
//        }
//    }

    func testPromiseDoesNotCallThenAfterAsyncReject() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise { _, reject in
            Test.delay(0.1) {
                reject(Test.Error.code42)
            }
            }.then {
                XCTFail()
            }.then {
                XCTFail()
            }.then {
                XCTFail()
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(promise.value)
        }
    }

//    func testPromiseCallsSubsequentCatchAfterReject() {
//        let exp = expectation(description: "")
//        // Arrange.
//        var count = 0
//
//        // Act.
//        let promise = DispatchPromise<AnyObject> {
//            return Test.Error.code42 as AnyObject
//            }.then { _ in
//                XCTFail()
//            }.catch { error in
//                XCTAssertEqual((error as? Test.Error)?.rawValue, 42)
//                count += 1
//            }.catch { error in
//                XCTAssertEqual((error as? Test.Error)?.rawValue, 42)
//                count += 1
//            }.catch { error in
//                XCTAssertEqual((error as? Test.Error)?.rawValue, 42)
//                count += 1
//                exp.fulfill()
//        }
//
//        // Assert.
//        waitForExpectations(timeout: 10) { (err) in
//            XCTAssertNil(err)
//            XCTAssertEqual(count, 3)
//            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
//            XCTAssertTrue(promise.value == nil)
//        }
//    }

    func testPromiseCallsSubsequentCatchAfterAsyncReject() {
        let exp = expectation(description: "")
        // Arrange.
        var count = 0

        // Act.
        let promise = DispatchPromise { _, reject in
            Test.delay(0.1) {
                reject(Test.Error.code42)
            }
            }.then {
                XCTFail()
            }.catch { error in
                XCTAssertEqual((error as? Test.Error)?.rawValue, 42)
                count += 1
            }.catch { error in
                XCTAssertEqual((error as? Test.Error)?.rawValue, 42)
                count += 1
            }.catch { error in
                XCTAssertEqual((error as? Test.Error)?.rawValue, 42)
                count += 1
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertEqual(count, 3)
            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(promise.value)
        }
    }

    func testPromiseCatchesThrownError() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise<AnyObject> {
            throw Test.Error.code42
            }.then { _ in
                XCTFail()
            }.then {
                XCTFail()
            }.then {
                XCTFail()
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
        }
    }

    func testPromiseCatchesThrownErrorFromAsync() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise { _, _ in
            throw Test.Error.code42
            }.then {
                XCTFail()
            }.then {
                XCTFail()
            }.then {
                XCTFail()
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
        }
    }

    func testPromiseNoCatchOnPending() {
        // Arrange.
        let expectation = self.expectation(description: "")

        // Act.
        let promise = DispatchPromise<Void>()

        let thenPromise = promise.catch { _ in
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

    func testPromiseNoRejectAfterFulfill() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise { fulfill, reject in
            let error = Test.Error.code42
            fulfill(42)
            reject(error)
            throw error
            }.then { value in
                XCTAssertEqual(value, 42)
            }.catch { _ in
                XCTFail()
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

    func testPromiseNoFulfillAfterReject() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise<Int> { fulfill, reject in
            let error = Test.Error.code42
            reject(error)
            fulfill(42)
            throw error
            }.then { _ in
                XCTFail()
            }.catch { error -> Void in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
            }.then {
                XCTFail()
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(promise.value)
        }
    }

    func testPromiseNoDoubleReject() {
        let exp = expectation(description: "")
        // Act.
        let promise = DispatchPromise<Void> { _, reject in
            Test.delay(0.1) {
                reject(Test.Error.code42)
                reject(Test.Error.code13)
            }
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(promise.value)
        }
    }

//    func testPromiseThenReturnError() {
//        let exp = expectation(description: "")
//        // Act.
//        let promise = DispatchPromise {
//            return 42
//            }.then { _ in
//                return Test.Error.code42
//            }.then { _ in
//                XCTFail()
//            }.then { _ in
//                XCTFail()
//            }.catch { error in
//                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
//                exp.fulfill()
//        }
//
//        // Assert.
//        waitForExpectations(timeout: 10) { (err) in
//            XCTAssertNil(err)
//            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
//            XCTAssertNil(promise.value)
//        }
//    }

    func testPromiseCatchInitiallyRejected() {
        let exp = expectation(description: "")
        // Act.
        let initiallyRejectedPromise = DispatchPromise<Void>(Test.Error.code42)
        let promise = initiallyRejectedPromise.then { _ in
            XCTFail()
            }.catch { error in
                XCTAssertTrue((error as? Test.Error) == Test.Error.code42)
                exp.fulfill()
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue((initiallyRejectedPromise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(initiallyRejectedPromise.value)
            XCTAssertTrue((promise.error as? Test.Error) == Test.Error.code42)
            XCTAssertNil(promise.value)
        }
    }

    func testPromiseCatchNoDeallocUntilRejected() {
        let exp = expectation(description: "")
        // Arrange.
        let promise = DispatchPromise<Int>()
        weak var weakExtendedPromise1: DispatchPromise<Int>?
        weak var weakExtendedPromise2: DispatchPromise<Int>?

        // Act.
        autoreleasepool {
            XCTAssertNil(weakExtendedPromise1)
            XCTAssertNil(weakExtendedPromise2)
            weakExtendedPromise1 = promise.catch { _ in }
            weakExtendedPromise2 = promise.catch { _ in }
            XCTAssertNotNil(weakExtendedPromise1)
            XCTAssertNotNil(weakExtendedPromise2)
        }
        // Assert.
        XCTAssertNotNil(weakExtendedPromise1)
        XCTAssertNotNil(weakExtendedPromise2)

        promise.reject(Test.Error.code42)
        promise.catch { (_) in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10) { (err) in
            XCTAssertNil(err)

            XCTAssertNil(weakExtendedPromise1)
            XCTAssertNil(weakExtendedPromise2)
        }
    }
}

