//
//  SimpleError.swift
//  
//
//  Created on 1/25/22.
//

import Foundation

struct SimpleErr : Error {
    let description: String
    init(_ desc: String) {
        description = desc
    }
}
