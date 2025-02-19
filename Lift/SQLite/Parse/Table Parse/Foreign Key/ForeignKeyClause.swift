//
//  ForeignKeyClause.swift
//  Lift
//
//  Created by Carl Wieland on 9/29/17.
//  Copyright © 2017 Datum Apps. All rights reserved.
//

import Foundation

struct ForeignKeyClause {

    var foreignTable: String
    var actionStatements = [ForeignKeyActionStatement]()
    var matchStatements = [ForeignKeyMatchStatement]()

    var toColumns = [String]()

    var deferStatement: ForeignKeyDeferStatement?

    init( destination: String, columns: [String]) {

        foreignTable = destination
        toColumns = columns

    }

    init(from scanner: Scanner) throws {

        guard scanner.scanString("references", into: nil) else {
            throw ParserError.unexpectedError("Expected references for FK clause!?")
        }

        foreignTable = try SQLiteCreateTableParser.parseStringOrName(from: scanner)

        if scanner.scanString("(", into: nil) {
            repeat {
                let name = try SQLiteCreateTableParser.parseStringOrName(from: scanner)

                guard !name.isEmpty else {
                    throw ParserError.unexpectedError("Empty foreign key column name!")
                }
                toColumns.append(name)

            } while (scanner.scanString(",", into: nil))

            guard scanner.scanString(")", into: nil) else {
                throw ParserError.unexpectedError("Failed to end parsing the foreign key column names!")
            }
            guard !toColumns.isEmpty else {
                throw ParserError.unexpectedError("No to columns in foreign key clause!")
            }
        }

        var finished = false

        while !finished {
            finished = true
            if scanner.scanString("ON", into: nil) {
                let actionStatement = try ForeignKeyActionStatement(from: scanner)
                actionStatements.append(actionStatement)
                finished = false
            }
            if scanner.scanString("match", into: nil) {
                let matchStatement = try ForeignKeyMatchStatement(from: scanner)
                matchStatements.append(matchStatement)
                finished = false
            }

            let start = scanner.scanLocation
            if scanner.scanString("NOT", into: nil) || scanner.scanString("Deferrable", into: nil) {
                scanner.scanLocation = start
                deferStatement = try ForeignKeyDeferStatement(from: scanner)
                finished = true
            }
        }
    }

    var sql: String {
        var builder = "REFERENCES \(foreignTable.sqliteSafeString()) "
        if !toColumns.isEmpty {
            builder += "(" + toColumns.map({ $0.sqliteSafeString() }).joined(separator: ", ") + ") "
        }

        builder += actionStatements.map({ $0.sql }).joined(separator: " ")
        builder += matchStatements.map({ $0.sql }).joined(separator: " ")
        if let defStat = deferStatement {
            builder += defStat.sql
        }

        return builder

    }
}

func == (lhs: ForeignKeyClause, rhs: ForeignKeyClause) -> Bool {
    if !(lhs.foreignTable == rhs.foreignTable) {
        return false
    }

    if lhs.toColumns.count != rhs.toColumns.count {
        return false
    }

    for i in 0..<lhs.toColumns.count where lhs.toColumns[i] != rhs.toColumns[i] {
        return false
    }

    if let lhD = lhs.deferStatement, let rhD = rhs.deferStatement, lhD != rhD {
        return false
    }

    if lhs.actionStatements.count != rhs.actionStatements.count {
        return false
    }

    for i in 0..<lhs.actionStatements.count where lhs.actionStatements[i] != rhs.actionStatements[i] {
        return false

    }

    if lhs.matchStatements.count != rhs.matchStatements.count {
        return false
    }

    for i in 0..<lhs.matchStatements.count where lhs.matchStatements[i] != rhs.matchStatements[i] {
        return false
    }

    return true
}
