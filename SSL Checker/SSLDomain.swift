//
//  Item.swift
//  SSL Checker
//
//  Created by Mai Dũng on 20/1/26.
//

import Foundation
import SwiftData

@Model
final class SSLDomain {
    var host: String
    var expiryDate: Date?
    var lastChecked: Date
    
    init(host: String, expiryDate: Date? = nil, lastChecked: Date = Date()) {
        self.host = host
        self.expiryDate = expiryDate
        self.lastChecked = lastChecked
    }
}
