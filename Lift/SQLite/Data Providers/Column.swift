//
//  Column.swift
//  Yield
//
//  Created by Carl Wieland on 4/4/17.
//  Copyright © 2017 Datum. All rights reserved.
//

import Foundation

class Column: NSObject {

    let connection: sqlite3

    /// Definition if there. Will be nil on views
    var definition: ColumnDefinition?

    weak var table: Table?

    let type: String

    @objc dynamic let name: String

    let isPrimaryKey: Bool

    let defaultValue: String?
    /*
     - 0 : "cid"
     - 1 : "name"
     - 2 : "type"
     - 3 : "notnull"
     - 4 : "dflt_value"
     - 5 : "pk"
     */
    init(rowInfo: [SQLiteData], connection: sqlite3) throws {

        self.connection = connection

        guard case .text(let name) = rowInfo[1],
        case .text(let type) = rowInfo[2],
        case .integer(let pk) = rowInfo[5] else {
            throw LiftError.invalidColumn
        }
        if case .text(let dflVal) = rowInfo[4] {
            defaultValue = dflVal
        } else {
            defaultValue = nil
        }
        self.name = name
        self.type = type
        self.isPrimaryKey = pk != 0
        super.init()
    }

    var simpleColumnCreationStatement: String {
        return "\(name.sqliteSafeString()) \(type)"
    }

}
