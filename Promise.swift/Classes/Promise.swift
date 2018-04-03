//
//  Promise.swift
//  Promise.swift
//
//  Created by Denis Koryttsev on 23/03/2018.
//

import Foundation

class _Commit<T> {
    var result: T? { return nil }
    var isFired: Bool { return true }
    var isInvalidated: Bool { return true }
    func fire(_ value: T) {}
    func notify(on queue: DispatchQueue, _ it: @escaping (T) -> Void) {}

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
        let notifier: DispatchGroup
        var state: State = .pending
        var onFire: (() -> Void)?

        enum State {
            case pending, fired, invalidated
        }

        override var result: T? { return _result }
        override var isInvalidated: Bool { return state == .invalidated }
        override var isFired: Bool { return state == .fired }

        override init() {
            let notifier = DispatchGroup()
            notifier.enter()
            self.notifier = notifier
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
            notifier.notify(queue: queue, execute: {
                if self.state == .fired {
                    it(self.result!)
                }
            })
        }

        func invalidate() {
            guard state == .pending else { return }

            self.state = .invalidated
            notifier.leave()
        }

        deinit {
//            if state == .fired {
//                onFire?()
//            }
        }
    }
    final class Resolved<T>: _Commit<T> {
        var _result: T
        let workItem: DispatchWorkItem

        override var result: T? { return _result }
        override var isFired: Bool { return true }
        override var isInvalidated: Bool { return false }

        init(_ value: T) {
            let noWork = DispatchWorkItem {}
            noWork.perform()

            self.workItem = noWork
            self._result = value
            super.init()
            #if TESTING
            self.__dispatchObject = noWork
            #endif
        }

        override func notify(on queue: DispatchQueue, _ it: @escaping (T) -> Void) {
            let r = _result
            workItem.notify(queue: queue) { it(r) }
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

    public static func pendingError() -> DispatchPromise {
        let fail = Commit<Error>()
        return DispatchPromise(Empty(), fail)
    }

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
            return error.map { .init($0) } ?? .init(Empty(), fail)
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
            return error.map { .init($0) } ?? .init(Empty(), fail)
        }

        let promise = DispatchPromise<Result>()
        self.do(on: queue) { v in
            do {
                let p = try it(v)
                p.do(on: queue) { promise.fulfill($0) }
                p.catch(on: queue, make: promise.fail.fire)
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
                p.do(on: queue) { _ in
                    group.leave()
                }.resolve(on: queue) {
                    reject($0);
                    group.leave();
                }
            }

            group.notify(queue: queue) {
                if promise?.isPending ?? false {
                    fulfill(promises.map { $0.value! })
                }
            }
        }

        return promise!
    }
}
