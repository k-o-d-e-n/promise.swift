//
//  Support.swift
//  Promise.swift
//
//  Created by Denis Koryttsev on 02/04/2018.
//

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
