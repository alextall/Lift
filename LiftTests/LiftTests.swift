//
//  LiftTests.swift
//  LiftTests
//
//  Created by Carl Wieland on 9/28/17.
//  Copyright © 2017 Datum Apps. All rights reserved.
//

import XCTest
@testable import Lift

class LiftTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testColumnTypeTricky() {
        do {
            var tab = try SQLiteCreateTableParser.parseSQL("Create TABLE t1(col ty1 ty2 ty3 \"asdf fwqer\" UNIQUE)")

            XCTAssert(tab.columns[0].name == "col")
            XCTAssert(tab.columns[0].type ?? "" == "ty1 ty2 ty3 \"asdf fwqer\"")
            XCTAssert(tab.columns[0].columnConstraints[0] is UniqueColumnConstraint)

            tab = try SQLiteCreateTableParser.parseSQL("Create TABLE something(col type (1234, 4321))")
            XCTAssert(tab.columns[0].type ?? "" == "type (1234, 4321)")

            tab = try SQLiteCreateTableParser.parseSQL("Create TABLE sometabl(\"collumn \"\" with quote\" \"crazy type\" with lots of names(14243))")
            XCTAssert(tab.columns[0].type ?? "" == "\"crazy type\" with lots of names(14243)")

        } catch {
            XCTFail("Should have thrown")
        }

    }

    func testEvilQuotes() {
        do {
            var tab = try SQLiteCreateTableParser.parseSQL("Create TABLE `back ``ticks`(\"evil \"\"``'\"\"\")")
            XCTAssert(tab.tableName == "`back ``ticks`")
            XCTAssert(tab.columns[0].name == "\"evil \"\"``'\"\"\"")
            tab = try SQLiteCreateTableParser.parseSQL("Create TABLE 'bac\"k ''tick`][s'('evi''l \"\"``''\"\"\"')")
            XCTAssert(tab.tableName == "'bac\"k ''tick`][s'")
            XCTAssert(tab.columns[0].name == "'evi''l \"\"``''\"\"\"'")
            tab = try SQLiteCreateTableParser.parseSQL("Create TABLE `''\"`( failer)")
            XCTAssert(tab.tableName == "`''\"`")
            tab = try SQLiteCreateTableParser.parseSQL("Create TABLE \"\"\"\"\"\"\"\"(booya)")
            XCTAssert(tab.tableName == "\"\"\"\"\"\"\"\"")
            tab = try SQLiteCreateTableParser.parseSQL("Create TABLE \"a\"\"\"\"b\"\"\"(booya)")
            XCTAssert(tab.tableName == "\"a\"\"\"\"b\"\"\"")

        } catch {
            XCTFail("Should have thrown")
        }

    }

    func testFails() {
        do {
            _ = try SQLiteCreateTableParser.parseSQL("not a correct statement")
            XCTFail("Should have thrown")
        } catch {

        }
        do {
            _ = try SQLiteCreateTableParser.parseSQL("Create Index")
            XCTFail("Should have thrown")
        } catch {

        }
        do {
            _ = try SQLiteCreateTableParser.parseSQL("Create TEMPRORARY Index")
            XCTFail("Should have thrown")
        } catch {

        }
        do {
            _ = try SQLiteCreateTableParser.parseSQL("Create TEMPRORARY Index")
            XCTFail("Should have thrown")
        } catch {

        }
        do {
            _ = try SQLiteCreateTableParser.parseSQL("Create Table(")
            XCTFail("Should have thrown")
        } catch { }

        do {
            _ = try SQLiteCreateTableParser.parseSQL("Create Table    \t(")
            XCTFail("Should have thrown")
        } catch { }

        do {
            _ = try SQLiteCreateTableParser.parseSQL("Create temp Table(")
            XCTFail("Should have thrown")
        } catch {

        }
    }
    func testParseAllQuotes() {

        do {
            let def = try SQLiteCreateTableParser.parseSQL( "create table allQuotes(\"\"\"\", \"[]\");")
            XCTAssert(def.columns.count == 2)
            XCTAssert(def.columns[0].name == "\"\"\"\"")
            XCTAssert(def.columns[0].name.cleanedVersion == "\"")
        } catch {
            XCTFail("Should parse:\(error)")
        }

    }
    func testParse() {
        do {
            _ = try SQLiteCreateTableParser.parseSQL("""
                CREATE TABLE "my table"" with"" quotes"\""" a lot"" of "" quotes"\""" "(
                \"""F ASDF"" ASDFSDF"" "\""" SDFSDF"" " "QUATALICOUS",
                fsd)
                """)
        } catch {
            XCTFail("Should parse:\(error)")
        }
    }
    func testStartOfCreateStatement() {

        do {
            _ = try SQLiteCreateTableParser.parseSQL("CREATE table t1 (column3")
            XCTFail("Should not have created def")

        } catch {
        }

        do {
            let def = try SQLiteCreateTableParser.parseSQL("CREATE TEMP table   someTable   \t( \"column 2\")")

            XCTAssert(def.isTemp)
            XCTAssert(def.tableName == "someTable")
        } catch {
            XCTFail("Should have created def")
        }
        do {
            let def = try SQLiteCreateTableParser.parseSQL("CREATE TEMPorary tAbLe \"Sasdf\"\"asdtable\"( column1)")
            XCTAssert(def.isTemp)
            XCTAssert(def.tableName == "\"Sasdf\"\"asdtable\"")
        } catch {
            XCTFail("Should have created def")
        }
        do {
            let horriblName = try SQLiteCreateTableParser.parseSQL("CREATE TABLE \"(((((horrible\"\"name\"\"to\"\"parse)\"(pure, evil)")
            XCTAssert(horriblName.tableName == "\"(((((horrible\"\"name\"\"to\"\"parse)\"")
            let def = try SQLiteCreateTableParser.parseSQL("create table \"   \"\"( ( ( ( (( ( (\"\"\"(pure, evil);")
            XCTAssert(def.tableName == "\"   \"\"( ( ( ( (( ( (\"\"\"")

            let simplTab = try SQLiteCreateTableParser.parseSQL("create table \" Simple Table With Spaces \"(pure, evil);")
            XCTAssert(simplTab.tableName == "\" Simple Table With Spaces \"")

            let badTab = try SQLiteCreateTableParser.parseSQL("create table \"  Table With ( \"\"( \\( )) \"\")\"\"\"\"\"(pure, evil);")
            XCTAssert(badTab.tableName == "\"  Table With ( \"\"( \\( )) \"\")\"\"\"\"\"")

        } catch {
            XCTFail("Should have acceppted all")

        }
    }

    func testColumnNameParsing() {
        do {
            var def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(\"pure\", evil)")
            XCTAssert(def.columns[0].name == "\"pure\"")
            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(\"pure\"\"\", evil)")
            XCTAssert(def.columns[0].name == "\"pure\"\"\"")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(\"pureasdf _ asdf\\();.\"\"\", evil)")
            XCTAssert(def.columns[0].name == "\"pureasdf _ asdf\\();.\"\"\"")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(no_qoutes_just_unders, evil)")
            XCTAssert(def.columns[0].name == "no_qoutes_just_unders")
            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(simpleName , evil)")
            XCTAssert(def.columns[0].name == "simpleName")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(simple\"\"Na_me, evil)")
            XCTAssert(def.columns[0].name == "simple")

        } catch {
            XCTFail("Should have acceppted all")

        }
    }

    func testColumnTypeParsing() {
        do {
            var def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(\"pure\" INT, evil)")
            XCTAssert(def.columns[0].name == "\"pure\"")
            XCTAssert(def.columns[0].type ?? "" == "INT")
            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(\"pure\"\"\" \"Type val\", evil NULL)")
            XCTAssert(def.columns[0].name == "\"pure\"\"\"")
            XCTAssert(def.columns[0].type ?? "" == "\"Type val\"")
            XCTAssert(def.columns[1].name == "evil")
            XCTAssert(def.columns[1].type ?? "" == "NULL")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(nothingElse)")
            XCTAssert(def.columns[0].name == "nothingElse")
            XCTAssertNil(def.columns[0].type)

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(\"pureasdf _ asdf\\();.\"\"\", evil)")
            XCTAssert(def.columns[0].name == "\"pureasdf _ asdf\\();.\"\"\"")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(no_qoutes_just_unders, evil)")
            XCTAssert(def.columns[0].name == "no_qoutes_just_unders")
            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(simpleName , evil)")
            XCTAssert(def.columns[0].name == "simpleName")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(simple\"\"Na_me, evil)")
            XCTAssert(def.columns[0].name == "simple")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE t1(name0 type, name2 type2, name3 type3, name4 type4)")
            XCTAssert(def.columns.count == 4)
            XCTAssert(def.columns.reduce(true, { $0 && !($1.type?.isEmpty ?? true)}))
            XCTAssert(def.columns.reduce(true, { $0 && $1.name.hasPrefix("name")}))

        } catch {
            XCTFail("Should have acceppted all")

        }
    }

    func testTablePrimaryKeyConstraints() {
        do {
            var def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, PRIMARY KEY (colo2))")
            XCTAssert(!def.tableConstraints.isEmpty)
            XCTAssert(def.tableConstraints.first is PrimaryKeyTableConstraint)
            XCTAssert(!(def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns.isEmpty)
            XCTAssert((def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns[0].nameProvider.name == "colo2")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, CONSTRAINT abcd PRIMARY KEY (colo2, \"some column\"))")
            XCTAssert(!def.tableConstraints.isEmpty)
            XCTAssert(def.tableConstraints.first is PrimaryKeyTableConstraint)
            XCTAssert(!(def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns.isEmpty)
            XCTAssert((def.tableConstraints[0] as! PrimaryKeyTableConstraint).name ?? "" == "abcd")
            XCTAssert((def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns[0].nameProvider.name == "colo2")
            XCTAssert(((def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns.last?.nameProvider.name ?? "") == "\"some column\"")

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, CONSTRAINT abcd PRIMARY KEY (colo2, \"some column\") ON CONFLICT ROLLBACK)")
            XCTAssert(!def.tableConstraints.isEmpty)
            XCTAssert(def.tableConstraints.first is PrimaryKeyTableConstraint)
            XCTAssert(!(def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns.isEmpty)
            XCTAssert((def.tableConstraints[0] as! PrimaryKeyTableConstraint).name ?? "" == "abcd")
            XCTAssert((def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns[0].nameProvider.name == "colo2")
            XCTAssert(((def.tableConstraints[0] as! PrimaryKeyTableConstraint).indexedColumns.last?.nameProvider.name ?? "") == "\"some column\"")
            XCTAssert((def.tableConstraints[0] as! PrimaryKeyTableConstraint).conflictClause != nil)
            XCTAssert((def.tableConstraints[0] as! PrimaryKeyTableConstraint).conflictClause!.resolution == .rollback)

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, CONSTRAINT abcd PRIMARY KEY (colo2, \"some column\") ON CONFLICT ROLLBACK)")
            if let res = (def.tableConstraints[0] as? PrimaryKeyTableConstraint)?.conflictClause?.resolution {
                XCTAssert( res == .rollback)
            } else {
                XCTFail("Should have had a resolution")
            }

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, CONSTRAINT abcd PRIMARY KEY (colo2, \"some column\") ON CONFLICT ABORT)")
            if let res = (def.tableConstraints[0] as? PrimaryKeyTableConstraint)?.conflictClause?.resolution {
                XCTAssert( res == .abort)
            } else {
                XCTFail("Should have had a resolution")
            }
            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, CONSTRAINT abcd PRIMARY KEY (colo2, \"some column\") ON CONFLICT IGNORE)")
            if let res = (def.tableConstraints[0] as? PrimaryKeyTableConstraint)?.conflictClause?.resolution {
                XCTAssert( res == .ignore)
            } else {
                XCTFail("Should have had a resolution")
            }

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, CONSTRAINT abcd PRIMARY KEY (colo2, \"some column\") ON CONFLICT FAIL)")
            if let res = (def.tableConstraints[0] as? PrimaryKeyTableConstraint)?.conflictClause?.resolution {
                XCTAssert( res == .fail)
            } else {
                XCTFail("Should have had a resolution")
            }

            def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE tableT(\"some column\" INTEGER, colo2 INT, CONSTRAINT abcd PRIMARY KEY (colo2, \"some column\") ON CONFLICT REPLACE)")
            if let res = (def.tableConstraints[0] as? PrimaryKeyTableConstraint)?.conflictClause?.resolution {
                XCTAssert( res == .replace)
            } else {
                XCTFail("Should have had a resolution")
            }

        } catch {
            XCTFail("Should have acceppted all: \(error)")
        }
    }

    private func checkArray<T: Equatable>(expected: [T], got: [T]) -> Bool {

        if expected.count != got.count {
            return false
        }

        var allMatch = true
        for (index, value) in got.enumerated() {
            allMatch = allMatch && value == expected[index]
        }
        return allMatch
    }

    func testUniqueTableConstraints() {
        do {
            let def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE   simpleTable   \t( cola, colb, colc, cold, CONSTRAINT abcd UNIQUE ( cola, colb) ON CONFLICT ABORT, PRIMARY KEY (colc), CONSTRAINT uniqu2 UNIQUE (cold))")
            XCTAssert(def.tableName == "simpleTable")

            let constraints = def.tableConstraints

            guard constraints.count == 3 else {
                XCTFail("Not correct count")
                return
            }

            if let firstUnique = constraints[0] as? UniqueTableConstraint {
                XCTAssert(firstUnique.name ?? "" == "abcd")
                XCTAssert(firstUnique.indexedColumns.count == 2)
                XCTAssert(checkArray(expected: ["cola", "colb"], got: firstUnique.indexedColumns.map({ $0.nameProvider.name })))
                if let conf = firstUnique.conflictClause {
                    XCTAssert(conf.resolution == .abort)
                } else {
                    XCTFail("Should have had a conflict clause")
                }

            } else {
                XCTFail("Invalid constraint type")
            }

            if let firstUnique = constraints[1] as? PrimaryKeyTableConstraint {

                XCTAssert(firstUnique.indexedColumns.count == 1)
                XCTAssert(checkArray(expected: ["colc"], got: firstUnique.indexedColumns.map({ $0.nameProvider.name })))
                XCTAssert(firstUnique.conflictClause == nil)

            } else {
                XCTFail("Invalid constraint type")
            }

            if let firstUnique = constraints[2] as? UniqueTableConstraint {
                XCTAssert(firstUnique.name ?? "" == "uniqu2")

                XCTAssert(firstUnique.indexedColumns.count == 1)
                XCTAssert(checkArray(expected: ["cold"], got: firstUnique.indexedColumns.map({ $0.nameProvider.name })))
                XCTAssert(firstUnique.conflictClause == nil)
            } else {
                XCTFail("Invalid constraint type")
            }

        } catch {
            XCTFail("Should have created def\(error)")
        }
    }

    func testCheckTableExpressions() {
        do {
            let def = try SQLiteCreateTableParser.parseSQL("CREATE TABLE simpleTable(cola,colb,colc,cold,CONSTRAINT con1 CHECK ( \"(( \"\" ((\"),CONSTRAINT con2 CHECK( cola in (\"abcd)\", \"af(sd)\") or colb == 123), Constraint con3 CHECK (cold == 1234))")
            XCTAssert(def.tableName == "simpleTable")

            let constraints = def.tableConstraints

            guard constraints.count == 3 else {
                XCTFail("Invalid check constraint count")
                return
            }

            XCTAssert(constraints.reduce(true, {$0 && $1 is CheckTableConstraint}))

        } catch {
            XCTFail("Should have created def")
        }
    }

    func testForeignKeyTableConstraints() {
        do {
            var table = try SQLiteCreateTableParser.parseSQL("CREATE TABLE table1(cola,colb,colc,cold, FOREIGN KEY (cola, colb) REFERENCES table2 (cola1, colb1) ON DELETE SET NULL ON UPDATE NO ACTION MATCH \"some crazy\"\" name\" NOT DEFERRABLE INITIALLY DEFERRED)")

            var clause = ForeignKeyClause(destination: "table2", columns: ["cola1", "colb1"])
            clause.actionStatements.append( ForeignKeyActionStatement(type: .delete, result: .setNull))
            clause.actionStatements.append( ForeignKeyActionStatement(type: .update, result: .noAction))
            clause.matchStatements.append(ForeignKeyMatchStatement(name: "\"some crazy\"\" name\""))
            clause.deferStatement = ForeignKeyDeferStatement(deferrable: false, type: .initiallyDeferred)
            var byHand = ForeignKeyTableConstraint(name: nil, columns: ["cola", "colb"], clause: clause)

            XCTAssert(table.tableName == "table1")
            if let tableconst = table.tableConstraints.last as? ForeignKeyTableConstraint {

                XCTAssert( tableconst == byHand)
            } else {
                  XCTFail("Didn't parse table cosntraint")
            }

            table = try SQLiteCreateTableParser.parseSQL("CREATE TABLE table1(cola,colb,colc,cold, FOREIGN KEY (\"column a\", \"column b\") REFERENCES \"some other table\" (\"some other column\", \"column in some other table\"))")

            clause = ForeignKeyClause(destination: "\"some other table\"", columns: ["\"some other column\"", "\"column in some other table\""])
            byHand = ForeignKeyTableConstraint(name: nil, columns: ["\"column a\"", "\"column b\""], clause: clause)
            if let tableconst = table.tableConstraints.last as? ForeignKeyTableConstraint {
                XCTAssert( tableconst == byHand)
            } else {
                XCTFail("Didn't parse table cosntraint")
            }

            table = try SQLiteCreateTableParser.parseSQL("CREATE TABLE table1(cola,colb, FOREIGN KEY (cola, colb) REFERENCES \"some other table\")")

            clause = ForeignKeyClause(destination: "\"some other table\"", columns: [])
            byHand = ForeignKeyTableConstraint(name: nil, columns: ["cola", "colb"], clause: clause)
            if let tableconst = table.tableConstraints.last as? ForeignKeyTableConstraint {
                XCTAssert( tableconst == byHand)
            } else {
                XCTFail("Didn't parse table cosntraint")
            }

        } catch {
            XCTFail("Couldn't parse foreign key")
        }

    }

    func testComboTableConstraints() {
        do {
            var table = try SQLiteCreateTableParser.parseSQL("CREATE TABLE table1(cola,colb,colc,cold, CONSTRAINT uni UNIQUE (cola COLLATE \"some name\" ASC, colb), CHECK(cola = 23), FOREIGN KEY (cola, colb) REFERENCES table2 (cola1, colb1) ON DELETE SET NULL ON UPDATE NO ACTION MATCH \"some crazy\"\" name\" NOT DEFERRABLE INITIALLY DEFERRED)")

            var clause = ForeignKeyClause(destination: "table2", columns: ["cola1", "colb1"])
            clause.actionStatements.append( ForeignKeyActionStatement(type: .delete, result: .setNull))
            clause.actionStatements.append( ForeignKeyActionStatement(type: .update, result: .noAction))
            clause.matchStatements.append(ForeignKeyMatchStatement(name: "\"some crazy\"\" name\""))
            clause.deferStatement = ForeignKeyDeferStatement(deferrable: false, type: .initiallyDeferred)
            var byHand = ForeignKeyTableConstraint(name: nil, columns: ["cola", "colb"], clause: clause)

            XCTAssert(table.tableName == "table1")
            if let tableconst = table.tableConstraints.last as? ForeignKeyTableConstraint {

                XCTAssert( tableconst == byHand)
            } else {
                XCTFail("Didn't parse table cosntraint")
            }

            if let tableconst = table.tableConstraints.compactMap({ $0 as? UniqueTableConstraint}).first {
                if let name = tableconst.name {
                    XCTAssert( name == "uni")
                } else {
                    XCTFail("Should be named")
                }
                XCTAssert(tableconst.conflictClause == nil)
                XCTAssert(tableconst.indexedColumns[0].nameProvider.name == "cola")
                XCTAssert(tableconst.indexedColumns[0].sortOrder == .ASC)
                XCTAssert(tableconst.indexedColumns[0].collationName ?? "" == "\"some name\"")
            } else {
                XCTFail("Didn't parse table cosntraint")
            }
            if let checker = table.tableConstraints.compactMap({ $0 as? CheckTableConstraint}).first {
                XCTAssert(checker.checkExpression == "(cola = 23)")
            } else {
                XCTFail("Didn't parse table cosntraint")
            }

            table = try SQLiteCreateTableParser.parseSQL("CREATE TABLE table1(cola \"PRIMARY KEY\" PRIMARY KEY AUTOINCREMENT,colb UNIQUE ON CONFLICT ROLLBACK, colc, UNIQUE (cola,colb), CONSTRAINT ftab FOREIGN KEY (\"column a\", \"column b\") REFERENCES \"some other table\" (\"some other column\", \"column in some other table\"))")

            clause = ForeignKeyClause(destination: "\"some other table\"", columns: ["\"some other column\"", "\"column in some other table\""])
            byHand = ForeignKeyTableConstraint(name:"ftab", columns: ["\"column a\"", "\"column b\""], clause: clause)
            if let tableconst = table.tableConstraints.last as? ForeignKeyTableConstraint {
                XCTAssert( tableconst == byHand)
            } else {
                XCTFail("Didn't parse table cosntraint")
            }

            table = try SQLiteCreateTableParser.parseSQL("CREATE TABLE table1(cola INTEGER,colb TEXT, CONSTRAINT ftab FOREIGN KEY (cola, colb) REFERENCES \"some other table\")")

            clause = ForeignKeyClause(destination: "\"some other table\"", columns: [])
            byHand = ForeignKeyTableConstraint(name:"ftab", columns: ["cola", "colb"], clause: clause)
            if let tableconst = table.tableConstraints.last as? ForeignKeyTableConstraint {
                XCTAssert( tableconst == byHand)
            } else {
                XCTFail("Didn't parse table cosntraint")
            }

        } catch {
            XCTFail("Couldn't parse foreign key")
        }

    }

}
