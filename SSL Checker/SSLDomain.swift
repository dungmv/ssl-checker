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
    var ipAddress: String?
    
    init(host: String, expiryDate: Date? = nil, lastChecked: Date = Date(), ipAddress: String? = nil) {
        self.host = host
        self.expiryDate = expiryDate
        self.lastChecked = lastChecked
        self.ipAddress = ipAddress
    }
}
