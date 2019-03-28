//
//  Promise.swift
//  Promise.swift
//
//  Created by Denis Koryttsev on 23/03/2018.
//

import Foundation

extension DispatchGroup {
    static func single() -> DispatchGroup {
        let g = DispatchGroup()
        g.enter()
        return g
    }
}

class _Commit<T> {
    var result: T? { return nil }
    var isFired: Bool { return true }
    var isInvalidated: Bool { return true }
    func fire(_ value: T) {}
    func notify(on queue: DispatchQueue, _ it: @escaping (T) -> Void) {}
    func invalidate() {}

    #if TESTING
    weak var __dispatchObject: AnyObject? = nil
    #endif
}

public final class DispatchPromise<Value> {
    let success: _Commit<Value>
    let fail: _Commit<Error>

    var value: Value? { return success.result }
    var error: Error? { return fail.result }
    public var isPending: Bool { return !success.isFired && !fail.isFired }
    public var isRejected: Bool { return success.isInvalidated && fail.isFired }
    public var isFulfilled: Bool { return success.isFired && fail.isInvalidated }

    final class Commit<T>: _Commit<T> {
        var _result: T!
        var notifier: DispatchGroup
        var state: State = .pending
        var onFire: (() -> Void)?

        enum State {
            case pending, fired, invalidated
        }

        override var result: T? { return _result }
        override var isInvalidated: Bool { return state == .invalidated }
        override var isFired: Bool { return state == .fired }

        override init() {
            self.notifier = .single()
            super.init()
            #if TESTING
            self.__dispatchObject = notifier
            #endif
        }

        override func fire(_ value: T) {
            guard state == .pending else { return }

            self.state = .fired
            self._result = value
            onFire?()
            notifier.leave()
        }

        override func notify(on queue: DispatchQueue, _ it: @escaping (T) -> Void) {
            switch state {
            case .pending:
                notifier.notify(queue: queue, execute: {
                    if self.state == .fired {
                        it(self._result)
                    }
                })
            case .fired: queue.async { it(self._result) }
            case .invalidated: break
            }
        }

        override func invalidate() {
            guard state == .pending else { return }

            self.state = .invalidated
            notifier.leave()
        }

        deinit {
            invalidate()
        }
    }
    final class Resolved<T>: _Commit<T> {
        var _result: T

        override var result: T? { return _result }
        override var isFired: Bool { return true }
        override var isInvalidated: Bool { return false }

        init(_ value: T) {
            self._result = value
            super.init()
            #if TESTING
            self.__dispatchObject = noWork
            #endif
        }

        override func notify(on queue: DispatchQueue, _ it: @escaping (T) -> Void) {
            let r = _result
            queue.async { it(r) }
        }
    }
    final class Empty<T>: _Commit<T> {
        override var isFired: Bool { return false }
        override var isInvalidated: Bool { return true }
    }

    public typealias AsyncWork = (@escaping (Value) -> Void, @escaping (Error) -> Void) throws -> Void
    public typealias Work = () throws -> Value

    init(_ s: _Commit<Value>, _ f: _Commit<Error>) {
        self.success = s
        self.fail = f
    }

    /// Promise that does nothing. Use it when need stop the execution.
    ///
    /// - Returns: Promise object
    public static func stop() -> DispatchPromise {
        return DispatchPromise(Empty(), Empty())
    }

    /// Returns pending promise
    public convenience init() {
        let success = Commit<Value>()
        let fail = Commit<Error>()
        success.onFire = { [weak fail] in fail?.invalidate() }
        fail.onFire = { [weak success] in success?.invalidate() }
        self.init(success, fail)
    }

    public convenience init(_ work: @autoclosure () throws -> Value) {
        do {
            let result = try work()
            self.init(result)
        } catch let error {
            self.init(error)
        }
    }

    public convenience init<V>(_ work: @autoclosure () throws -> V) where V: DispatchPromise {
        do {
            let result = try work()
            self.init(result.success, result.fail)
        } catch let error {
            self.init(error)
        }
    }

    public convenience init(_ error: Error) {
        self.init(Empty(), Resolved(error))
    }

    public convenience init(_ value: Value) {
        self.init(Resolved(value), Empty())
    }

    public convenience init(on queue: DispatchQueue = .main, _ work: @escaping Work) {
        let success = Commit<Value>()
        let fail = Commit<Error>()
        success.onFire = { [weak fail] in fail?.invalidate() }
        fail.onFire = { [weak success] in success?.invalidate() }

        self.init(success, fail)

        queue.async {
            do {
                let result = try work()
                success.fire(result)
            } catch let error {
                fail.fire(error)
            }
        }
    }

    public convenience init(_ queue: DispatchQueue = .main, _ work: @escaping AsyncWork) {
        let success = Commit<Value>()
        let fail = Commit<Error>()
        success.onFire = { [weak fail] in fail?.invalidate() }
        fail.onFire = { [weak success] in success?.invalidate() }

        self.init(success, fail)

        queue.async {
            do {
                try work(success.fire, fail.fire)
            } catch let e {
                fail.fire(e)
            }
        }
    }

    public func fulfill(_ value: Value) {
        success.fire(value)
    }

    public func reject(_ error: Error) {
        fail.fire(error)
    }

    /// Breaks promise chain without error.
    /// This is not cancels the execution that runs in previous promises.
    public func cancel() {
        success.invalidate()
        fail.invalidate()
    }

    public func bind(to other: DispatchPromise) {
        self.do(other.fulfill)
        self.resolve(other.reject)
    }
}

// TODO: Check on correct behavior with queue for `catch`
public extension DispatchPromise {
    typealias Then<Result> = (Value) throws -> Result

    @discardableResult
    func `do`(on queue: DispatchQueue = .main, _ it: @escaping (Value) -> Void) -> DispatchPromise {
        success.notify(on: queue, it); return self
    }

    @discardableResult
    func resolve(on queue: DispatchQueue = .main, _ it: @escaping (Error) -> Void) -> DispatchPromise {
        fail.notify(on: queue, it); return self
    }

    @discardableResult
    func always(on queue: DispatchQueue = .main, _ doit: @escaping () -> Void) -> DispatchPromise {
        success.notify(on: queue, { _ in doit() })
        fail.notify(on: queue, { _ in doit() })
        return self
    }

    @discardableResult
    func then(on queue: DispatchQueue = .main, make it: @escaping Then<Void>) -> DispatchPromise {
        guard !success.isInvalidated else {
            return error.map(DispatchPromise.init) ?? .init(success, fail)
        }

        let promise = DispatchPromise()
        self.do(on: queue) { v in
            do {
                try it(v)
                promise.fulfill(v)
            } catch let error {
                promise.reject(error)
            }
        }
        self.resolve(on: queue, promise.fail.fire)
        return promise
    }

    @discardableResult
    public func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<Result>) -> DispatchPromise<Result> {
        guard !success.isInvalidated else {
            return error.map(DispatchPromise<Result>.init) ?? .init(Empty(), fail)
        }

        let promise = DispatchPromise<Result>()
        self.do(on: queue) { v in
            do {
                let value = try it(v)
                promise.fulfill(value)
            } catch let error {
                promise.reject(error)
            }
        }
        self.resolve(on: queue, promise.fail.fire)
        return promise
    }

    @discardableResult
    public func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<DispatchPromise<Result>>) -> DispatchPromise<Result> {
        guard !success.isInvalidated else {
            return error.map(DispatchPromise<Result>.init) ?? .init(Empty(), fail)
        }

        let promise = DispatchPromise<Result>()
        self.do(on: queue) { v in
            do {
                let p = try it(v)
                p.do(on: queue, promise.fulfill)
                p.resolve(on: queue, promise.fail.fire)
            } catch let e {
                promise.reject(e)
            }
        }
        self.resolve(on: queue, promise.fail.fire)
        return promise
    }

    @discardableResult
    public func then<Result>(on queue: DispatchQueue = .main, make it: @escaping (Value, DispatchPromise<Result>) throws -> Void) -> DispatchPromise<Result> {
        guard !success.isInvalidated else {
            return error.map(DispatchPromise<Result>.init) ?? .init(Empty(), fail)
        }

        let promise = DispatchPromise<Result>()
        self.do(on: queue) { v in
            do {
                try it(v, promise)
            } catch let e {
                promise.reject(e)
            }
        }
        self.resolve(on: queue, promise.fail.fire)
        return promise
    }

    @discardableResult
    func `catch`(on queue: DispatchQueue = .main, make it: @escaping (Error) -> Void) -> DispatchPromise {
        let promise = DispatchPromise()
        self.do(on: queue, promise.fulfill)
        self.resolve(on: queue, { it($0); promise.reject($0); })
        return promise
    }

    /// `testPromiseNoFulfillAfterReject` failed because called this method
//    @discardableResult
//    func `catch`<Resolved>(on queue: DispatchQueue = .main, make it: @escaping (Error) throws -> Resolved) -> DispatchPromise<Resolved> {
//        let promise = DispatchPromise<Resolved>()
//        self.resolve(on: queue, {
//            do {
//                promise.fulfill(try it($0))
//            } catch let e {
//                promise.reject(e)
//            }
//        })
//        return promise
//    }

    @discardableResult
    func `catch`<Resolved>(on queue: DispatchQueue = .main, make it: @escaping (Error) throws -> DispatchPromise<Resolved>) -> DispatchPromise<Resolved> {
        let promise = DispatchPromise<Resolved>()
        self.resolve(on: queue) { e in
            do {
                let p = try it(e)
                p.do(on: queue) { promise.fulfill($0) }
                p.resolve(on: queue, promise.fail.fire)
            } catch let e {
                promise.reject(e)
            }
        }
        return promise
    }
}

extension DispatchPromise {
    public static func all<Value>(
        on queue: DispatchQueue = .main,
        _ promises: DispatchPromise<Value>...
        ) -> DispatchPromise<[Value]> {
        return all(on: queue, promises)
    }
    
    public static func all<Value, Container: Sequence>(
        on queue: DispatchQueue = .main,
        _ promises: Container
        ) -> DispatchPromise<[Value]> where Container.Iterator.Element == DispatchPromise<Value> {

        var promise: DispatchPromise<[Value]>?
        promise = DispatchPromise<[Value]>.init { (fulfill, reject) in
            let group = DispatchGroup()
            promises.forEach { (p) in
                group.enter()
                p.resolve(on: queue, reject).always(on: queue, group.leave)
            }

            group.notify(queue: queue) {
                if promise?.isPending ?? false {
                    fulfill(promises.map { $0.value! })
                }
            }
        }

        return promise!
    }

    public class func tuple<V1, V2>(
        on queue: DispatchQueue = .main,
        _ first: DispatchPromise<V1>, _ second: DispatchPromise<V2>
        ) -> DispatchPromise<(V1, V2)> {

        var promise: DispatchPromise<(V1, V2)>?
        promise = DispatchPromise<(V1, V2)>.init { (fulfill, reject) in
            let group = DispatchGroup()
            group.enter(); group.enter()
            first.resolve(on: queue, reject).always(on: queue, group.leave)
            second.resolve(on: queue, reject).always(on: queue, group.leave)

            group.notify(queue: queue) {
                if promise?.isPending ?? false {
                    fulfill((first.value!, second.value!))
                }
            }
        }

        return promise!
    }

    public class func tuple<V1, V2, V3>(
        on queue: DispatchQueue = .main,
        _ first: DispatchPromise<V1>, _ second: DispatchPromise<V2>, _ third: DispatchPromise<V3>
        ) -> DispatchPromise<(V1, V2, V3)> {

        var promise: DispatchPromise<(V1, V2, V3)>?
        promise = DispatchPromise<(V1, V2, V3)>.init { (fulfill, reject) in
            let group = DispatchGroup()
            group.enter(); group.enter(); group.enter()
            first.resolve(on: queue, reject).always(on: queue, group.leave)
            second.resolve(on: queue, reject).always(on: queue, group.leave)
            third.resolve(on: queue, reject).always(on: queue, group.leave)

            group.notify(queue: queue) {
                if promise?.isPending ?? false {
                    fulfill((first.value!, second.value!, third.value!))
                }
            }
        }

        return promise!
    }

    public func attach<V2>(on queue: DispatchQueue = .main, _ second: DispatchPromise<V2>) -> DispatchPromise<(Value, V2)> {
        return DispatchPromise.tuple(on: queue, self, second)
    }
    public func attach<V2, V3>(on queue: DispatchQueue = .main, _ second: DispatchPromise<V2>, third: DispatchPromise<V3>) -> DispatchPromise<(Value, V2, V3)> {
        return DispatchPromise.tuple(on: queue, self, second, third)
    }
}

extension DispatchPromise: ExpressibleByNilLiteral where Value: ExpressibleByNilLiteral {
    public convenience init(nilLiteral: ()) {
        self.init(nil)
    }
}
