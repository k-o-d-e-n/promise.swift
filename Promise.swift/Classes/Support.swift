//
//  Support.swift
//  Promise.swift
//
//  Created by Denis Koryttsev on 02/04/2018.
//

import Foundation

public extension URLSession {
    func response(by url: URL) -> DispatchPromise<Data?> {
        let promise = DispatchPromise<Data?>()
        dataTask(with: url) { (data, response, err) in
            if let e = err {
                promise.reject(e)
            } else {
                promise.fulfill(data)
            }
        }.resume()
        return promise
    }
}
