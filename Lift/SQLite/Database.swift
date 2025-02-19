//
//  SQLiteDatabase.swift
//  Lift
//
//  Created by Carl Wieland on 10/3/17.
//  Copyright © 2017 Datum Apps. All rights reserved.
//

import Cocoa

enum DatabaseType {
    case inMemory(name: String)
    case disk(path: URL, name: String)
    case aux(path: URL)
}

enum AutocommitStatus {
    case autocommit
    case inTransaction
}

extension Notification.Name {
    static let DatabaseReloaded = Notification.Name("DatabaseReloaded")
    static let AttachedDatabasesChanged = Notification.Name("AttachedDatabasesChanged")
    static let AutocommitStatusChanged = Notification.Name("AutocommitStatusChanged")

}

typealias sqlite3 = OpaquePointer

class Database: NSObject {
    private static var inMemoryCount = 0

    convenience init(type: DatabaseType) throws {

        switch  type {
        case .inMemory(name: let name):
            let dbName = "file:memdb\(Database.inMemoryCount)?mode=memory&cache=shared"
            var db: sqlite3?
            let ret = sqlite3_open_v2(dbName, &db, SQLITE_OPEN_URI | SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            guard ret == SQLITE_OK, let connection = db else {
                throw SQLiteError(connection: db, code: ret, sql: "Opening with: \(dbName)")
            }
            self.init(connection: connection, name: name)
            Database.inMemoryCount += 1
        case .disk(path:let path, name:let name):
            var db: sqlite3?
            let ret = sqlite3_open(path.path, &db)
            guard ret == SQLITE_OK, let connection = db else {
                throw SQLiteError(connection: db, code: ret, sql: "Opening path:\(path.path)")
            }

            self.init(connection: connection, name: name)
        case .aux(path: let path):
            var db: sqlite3?
            let ret = sqlite3_open(path.path, &db)
            guard ret == SQLITE_OK, let connection = db else {
                throw SQLiteError(connection: db, code: ret, sql: "Opening path:\(path.path)")
            }

            self.init(connection: connection, name: "main", enableLogging: false)
        }

    }

    public let connection: sqlite3
    @objc dynamic public let name: String

    fileprivate var trace: Trace?

    public private(set) var path: String = ""

    @objc dynamic public private(set) var tables = [Table]()
    public private(set) var systemTables = [Table]()

    public private(set) var views = [View]()

    public private(set) var tempDatabase: Database?
    public private(set) var mainDB: Database?

    public private(set) var history = [String]()

    public private(set) var autocommitStatus = AutocommitStatus.autocommit {
        didSet {
            if autocommitStatus != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .AutocommitStatusChanged, object: self)
                }
            }
        }
    }

    private init(connection: sqlite3, name: String, enableLogging: Bool = true) {
        self.connection = connection
        self.name = name

        super.init()

        if name == "main" {
            areForeignKeysEnabled = true
            extensionsAllowed = true
            if enableLogging {
                trace_v2 { [weak self] log in
                    DispatchQueue.main.async {
                        self?.history.append(log)
                    }
                }
            }

        }
    }

    deinit {
        if name == "main" {
            sqlite3_close_v2(connection)
        }
    }

    func refresh( tableLoadCompletion: (([String: Error]) -> Void)? = nil) {
        refreshAutoCommit()
        refreshAttachedDatabases()
        refreshTables(completion: tableLoadCompletion)
    }

    func refreshAutoCommit() {
        DispatchQueue.main.async {
            self.autocommitStatus = sqlite3_get_autocommit(self.connection) != 0 ? .autocommit : .inTransaction
        }
    }

    private func refreshTables(completion: (([String: Error]) -> Void)? = nil) {
        do {
            tables.removeAll(keepingCapacity: true)
            systemTables.removeAll(keepingCapacity: true)
            views.removeAll(keepingCapacity: true)
            let clearedName = name
            let refreshDBQuery = try Query(connection: self.connection, query: "SELECT * from \(clearedName).sqlite_master where type in ('table', 'view') ORDER BY name;")

            var errors = [String: Error]()
            try refreshDBQuery.processRows { (data) in
                //type|name|tbl_name|rootpage|sql
                guard case .text(let type) = data[0], case .text(let name) = data[1] else {
                    return
                }
                do {
                    if type  == "table" {
                        let table = try Table(database: self, data: data, connection: connection)
                        if table.name.hasPrefix("sqlite_") {
                            systemTables.append(table)
                        } else {
                            tables.append(table)
                        }
                    } else {
                        views.append(try View(database: self, data: data, connection: connection))
                    }
                } catch {
                    print("Error!:\(error)")
                    errors[name] = error
                }

            }

            systemTables.append(try Table(database: self, data: [.text("table"), .text("sqlite_master"), .text("sqlite_master"), .integer(0), .text("CREATE TABLE sqlite_master(type text,name text,tbl_name text, rootpage integer,sql text)")], connection: connection))
            completion?(errors)
        } catch {
            print("Failed to refresh:\(error)")
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .DatabaseReloaded, object: self)
        }

    }

    private func refreshAttachedDatabases() {
        guard name == "main" else {
            return
        }

        attachedDatabases.removeAll()
        tempDatabase = nil
        do {
            let query = try Query(connection: connection, query: "PRAGMA main.database_list")
            try query.processRows(handler: { row in
                var path = "In Memory"

                if case .text(let fullPath) = row[2], !fullPath.isEmpty {
                    path = fullPath
                }

                guard case .integer( let num) = row[0] else { //skip the main and temp databases
                    return
                }

                guard case .text(let name) = row[1] else {
                    return
                }

                if num == 0 && name == "main" {
                    self.path = path
                } else if num == 1 && name == "temp" {
                    tempDatabase = Database(connection: connection, name: name)
                    tempDatabase?.mainDB = self
                    tempDatabase?.path = path
                    tempDatabase?.refresh()
                } else {
                    let childDB = Database(connection: self.connection, name: name)
                    childDB.mainDB = self
                    childDB.path = path
                    childDB.refresh()
                    attachedDatabases.append(childDB)
                }

            })

        } catch {
            print("Failed to refresh database list:\(error)")
        }
    }

    var attachedDatabases = [Database]() {
        didSet {
            NotificationCenter.default.post(name: .AttachedDatabasesChanged, object: self)
        }
    }

    var allDatabases: [Database] {

        guard name == "main" else {
            return []
        }

        var dbs = attachedDatabases
        dbs.insert(self, at: 0)
        if let tempDB = tempDatabase {
            dbs.insert(tempDB, at: 1)
        }

        return dbs
    }

    public func table(named name: String) -> Table? {
        return tables.first(where: { $0.name == name })
    }

    @discardableResult
    public func execute(statement: String) throws -> Bool {
        defer {
            refreshAutoCommit()
        }

        let statement = try Statement(connection: connection, text: statement)
        return try statement.step()
    }

    public func executeStatementInBackground(_ statement: String, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            var returnError: Error?

            do {
                let statement = try Statement(connection: self.connection, text: statement)
                let rc = try statement.step()

                if !rc {
                    print("INVALID USAGE! SHOULD NOT BE EXPECTING ROWS HERE!")
                    returnError = LiftError.invalidUsage
                }

            } catch {
                returnError = error
            }

            DispatchQueue.main.async {
                completion(returnError)
            }
        }
    }

    public func attachDatabase(at path: URL, with name: String) throws -> Bool {
        let cleanedPath = path.path.sqliteSafeString()
        let sql = "ATTACH DATABASE \(cleanedPath) AS \(name.sqliteSafeString())"
        let success = try execute(statement: sql)
        if success {
            DispatchQueue.main.async { [weak self] in
                self?.refreshAttachedDatabases()
            }

        }
        return success

    }

    public func detachDatabase(named name: String) throws -> Bool {
        let sql = "DETACH DATABASE \(name.sqliteSafeString())"
        let success = try execute(statement: sql)
        if success {
            DispatchQueue.main.async { [weak self] in
                self?.refreshAttachedDatabases()
            }

        }
        return success
    }

    public func loadExtension(at path: URL, entryPoint: String? ) throws {

        if !extensionsAllowed {
            extensionsAllowed = true
        }

        let zFile = path.path
        var errorMsg: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_load_extension(connection, zFile, entryPoint, &errorMsg)
        guard rc == SQLITE_OK else {
            if let msg = errorMsg {
                let str = String(cString: msg)
                print("Failed to load extension:\(str)")
            }
            throw SQLiteError(connection: connection, code: rc, sql: "sqlite3_load_extension(connection, zFile, entryPoint, &errorMsg)")
        }
    }

    public func clearHistory() {
        history.removeAll(keepingCapacity: true)
    }

    public func cleanDatabase() throws {

        _ = try execute(statement: "VACUUM \(name.sqliteSafeString())")

        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    public func checkDatabaseIntegrity() throws -> Bool {
        let integrityQuery = try Query(connection: connection, query: "PRAGMA integrity_check")
        let allRows = try integrityQuery.allRows()
        guard allRows.count == 1, allRows[0].count == 1, case .text(let okStr) = allRows[0][0] else {
            throw LiftError.integrityCheck
        }
        return okStr == "ok"

    }

    public func checkForeignKeyIntegrity() throws -> Bool {
        return try execute(statement: "PRAGMA foreign_key_check")
    }

    // MARK: - Transactions
    public func exec(_ statement: String) throws {

        defer {
            refreshAutoCommit()
        }

        let rc = sqlite3_exec(connection, statement, nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw SQLiteError(connection: connection, code: rc, sql: statement)
        }

    }

    public func beginTransaction() throws {
        try exec("BEGIN TRANSACTION;")

    }

    public func endTransaction() throws {
        try exec("COMMIT;")

    }

    public func rollback() {
        do {
            try exec("ROLLBACK;")
        } catch {
            print("FAILED TO ROLLBACK!!!:\(error)")
        }
    }

    // MARK: - Save points

    public func beginSavepoint(named name: String) throws {
        try exec("SAVEPOINT \(name);")
    }

    public func releaseSavepoint(named name: String) throws {
        try exec("RELEASE \(name);")
    }
    public func rollbackSavepoint(named name: String) throws {
        try exec("ROLLBACK TO \(name);")
    }

}

extension Database {
    fileprivate typealias Trace = @convention(block) (UnsafeRawPointer) -> Void
    fileprivate func trace_v2(_ callback: ((String) -> Void)?) {
        guard let callback = callback else {
            // If the X callback is NULL or if the M mask is zero, then tracing is disabled.
            sqlite3_trace_v2(connection, 0 /* mask */, nil /* xCallback */, nil /* pCtx */)
            trace = nil
            return
        }

        let box: Trace = { (pointer: UnsafeRawPointer) in
            callback(String(cString: pointer.assumingMemoryBound(to: UInt8.self)))
        }
        sqlite3_trace_v2(connection,
                         UInt32(SQLITE_TRACE_STMT) /* mask */,
                // A trace callback is invoked with four arguments: callback(T,C,P,X).
                // The T argument is one of the SQLITE_TRACE constants to indicate why the
                // callback was invoked. The C argument is a copy of the context pointer.
                // The P and X arguments are pointers whose meanings depend on T.
                { (_: UInt32, C: UnsafeMutableRawPointer?, P: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?) in
                if let P = P,
                    let expandedSQL = sqlite3_expanded_sql(OpaquePointer(P)) {
                    unsafeBitCast(C, to: Trace.self)(expandedSQL)
                    sqlite3_free(expandedSQL)
                }
                return Int32(0) // currently ignored
        },
            unsafeBitCast(box, to: UnsafeMutableRawPointer.self) /* pCtx */
        )
        trace = box
    }
}
