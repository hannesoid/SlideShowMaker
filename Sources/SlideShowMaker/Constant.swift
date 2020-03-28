//
//  K.swift
//  Pods
//
//  Created by lcf on 22/08/2017.
//
//

import UIKit

extension VideoMaker {

    enum Constants {

        struct Path {
            static var documentURL: URL {
                return try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            }

            static var libraryURL: URL {
                return try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            }

            static var movURL: URL {
                return libraryURL.appendingPathComponent("Mov", isDirectory: true)
            }
        }
    }
}
