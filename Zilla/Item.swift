//
//  Item.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
