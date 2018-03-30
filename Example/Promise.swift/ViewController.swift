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

    override func viewDidLoad() {
        super.viewDidLoad()
        let p = DispatchPromise(on: .main) { () -> String in
            return "Promise.swift is running"
        }

        p.then { print($0) }

        let p_value = DispatchPromise(0)
        p_value.then { print($0) }
    }

}

