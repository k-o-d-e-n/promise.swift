//
//  Support.swift
//  Promise.swift
//
//  Created by Denis Koryttsev on 02/04/2018.
//

#if os(iOS) || os(tvOS) || os(macOS)
import Foundation

public extension URLSession {
    func response(by url: URL) -> (promise: DispatchPromise<(data: Data?, response: HTTPURLResponse?)>, task: URLSessionDataTask) {
        let promise = DispatchPromise<(data: Data?, response: HTTPURLResponse?)>()
        let task = dataTask(with: url) { (data, response, err) in
            if let e = err {
                promise.reject(e)
            } else {
                promise.fulfill((data, response as? HTTPURLResponse))
            }
        }
        task.resume()
        return (promise, task)
    }
    func response(for request: URLRequest) -> (promise: DispatchPromise<(data: Data?, response: HTTPURLResponse?)>, task: URLSessionDataTask) {
        let promise = DispatchPromise<(data: Data?, response: HTTPURLResponse?)>()
        let task = dataTask(with: request) { (data, response, err) in
            if let e = err {
                promise.reject(e)
            } else {
                promise.fulfill((data, response as? HTTPURLResponse))
            }
        }
        task.resume()
        return (promise, task)
    }
}
#endif

#if os(iOS)
import UIKit

public extension URLSession {
    func image(by url: URL) -> (promise: DispatchPromise<UIImage?>, task: URLSessionDataTask) {
        let (promise, task) = response(by: url)
        return (promise.then { (data, response) -> UIImage? in
            return data.flatMap(UIImage.init)
        }, task)
    }
}
#endif
