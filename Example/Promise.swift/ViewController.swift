//
//  ViewController.swift
//  Promise.swift
//
//  Created by k-o-d-e-n on 03/23/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Promise_swift

class ViewController: UIViewController {
    lazy var label: UILabel = UILabel(frame: view.bounds)

    override func viewDidLoad() {
        super.viewDidLoad()

        let ip = URLSession.shared.response(by: URL(string: "http://httpbin.org/ip")!).promise
        let agent = URLSession.shared.response(by: URL(string: "http://httpbin.org/user-agent")!).promise
        let get = URLSession.shared.response(by: URL(string: "http://httpbin.org/get")!).promise

        DispatchPromise<[Data?]>.all(ip, agent, get)
            .do { _ in
                self.view.addSubview(self.label)
                self.label.numberOfLines = 0
            }
            .then { (datas) -> String in
                return datas.reduce(into: "", { (res, d) in
                    let part = d.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    res.append(part)
                })
            }
            .then { self.label.text = $0 }
            .catch { e in print(e) }
    }
}

