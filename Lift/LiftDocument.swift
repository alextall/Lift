//
//  Document.swift
//  Lift
//
//  Created by Carl Wieland on 9/28/17.
//  Copyright © 2017 Datum Apps. All rights reserved.
//

import Cocoa

class LiftDocument: NSDocument {

    @objc dynamic public private(set) var database: Database {
        didSet {
            updateListeners()
        }
    }

    override init() {
        do {
            database = try Database(type: .inMemory(name: "main"))
        } catch {
            fatalError("Unable to create in-memory database!?")
        }
        super.init()
        updateListeners()

    }

    public private(set) var databaseLoadErrors: [String: Error]?

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        var allowed = true

        let shouldClose = {
            guard let shouldCloseSelector = shouldCloseSelector else { return }
            let Class: AnyClass = Swift.type(of: delegate as AnyObject)
            let method = class_getMethodImplementation(Class, shouldCloseSelector)

            typealias Signature = @convention(c) (Any, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
            let function = unsafeBitCast(method, to: Signature.self)

            function(delegate, shouldCloseSelector, self, allowed, contextInfo)
        }

        if database.autocommitStatus == .inTransaction {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Currently in transaction", comment: "Alert title when attempting to close while in transaction")
            alert.informativeText = NSLocalizedString("The database is currently in a transaction. Closing now could result in loss of data. Would you like to attempt to commit these changes?", comment: "Alert message when attempting to close while in transaction")
            alert.addButton(withTitle: NSLocalizedString("Commit", comment: "option to commit when closing"))
            alert.addButton(withTitle: NSLocalizedString("Close without committing", comment: " option to close document with out commiting"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button when closing"))

            let handler: (NSApplication.ModalResponse) -> Void = { response in
                if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                    do {
                        try self.database.endTransaction()
                        allowed = true
                    } catch {
                        self.presentError(error)
                        allowed = false
                    }

                } else if response == NSApplication.ModalResponse.alertSecondButtonReturn {
                    allowed = true
                } else if response == NSApplication.ModalResponse.alertThirdButtonReturn {
                    allowed = false
                }
                shouldClose()

            }
            if let window = windowControllers.first?.window {
                alert.beginSheetModal(for: window, completionHandler: handler)
            } else {
                let response = alert.runModal()
                handler(response)
            }
        } else {
            shouldClose()
        }

    }
    init(contentsOf url: URL, ofType typeName: String) throws {

        SQLiteDocumentPresenter.addPresenters(for: url)

        database = try Database(type: .disk(path: url, name: "main"))
        super.init()
        fileURL = url
        displayName = url.lastPathComponent
        refresh()
        updateListeners()

    }

    public convenience init(for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String) throws {
        try self.init(contentsOf: contentsURL, ofType: typeName)
    }

    override func makeWindowControllers() {
        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let windowController = storyboard.instantiateController(withIdentifier: "Document Window Controller") as? LiftWindowController else {
            fatalError("Unable to create document window controller")
        }
        self.addWindowController(windowController)

        if let errors = databaseLoadErrors {
            windowController.showLoadErrors(errors)
        }

    }

    override func save(_ sender: Any?) {
        if database.autocommitStatus == .inTransaction {
            do {
                try database.endTransaction()
            } catch {
                presentError(error)
            }
        }
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        if fileURL == nil {
            var pFile: sqlite3?;           /* Database connection opened on zFilename */

            var rc = sqlite3_open(url.path, &pFile)
            SQLiteDocumentPresenter.addPresenters(for: url)

            guard rc == SQLITE_OK, let pTo = pFile else {
                let error = SQLiteError(connection: nil, code: rc, sql: "sqlite3_open")
                completionHandler(error)
                return
            }

            if let pBackup = sqlite3_backup_init(pTo, "main", database.connection, "main") {
                sqlite3_backup_step(pBackup, -1)
                sqlite3_backup_finish(pBackup)
                rc = sqlite3_errcode(pTo)
                guard rc == SQLITE_OK else {
                    let error = SQLiteError(connection: nil, code: rc, sql: "sqlite3_backup_step")
                    completionHandler(error)
                    return
                }
                fileURL = url
                do {

                    database = try Database(type: .disk(path: url, name: "main"))
                    refresh()
                } catch {
                    completionHandler(error)
                }
            } else {
                let error = NSError(domain: "com.datumapps.lift", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Failed to initialize backup", comment: "Error string")])
                completionHandler(error)
            }
            /* Close the database connection opened on database file zFilename
             ** and return the result of this function. */
            sqlite3_close(pTo)
            return

        }

        if database.autocommitStatus == .inTransaction {
            do {
                try database.endTransaction()
            } catch {
                completionHandler(error)
            }
        }

        if let curURL = fileURL, curURL != url {

            do {
                SQLiteDocumentPresenter.addPresenters(for: url)
                try FileManager.default.moveItem(at: curURL, to: url)
                fileURL = curURL
                completionHandler(nil)
            } catch {
                completionHandler(error)

            }

        }

    }

    func keywords() -> Set<String> {
        var keywords = Set<String>()

        for database in database.allDatabases {
            keywords.insert(database.name)
            for table in database.tables {
                keywords.insert(table.name)
                keywords.formUnion(table.columns.map({ $0.name }))
            }
        }

        return keywords
    }

    func refresh() {
        databaseLoadErrors = nil
        database.refresh { [weak self] errors in
            self?.databaseLoadErrors = errors
        }
    }

    func cleanDatabase() throws {
        try database.cleanDatabase()
    }

    func checkDatabaseIntegrity() throws -> Bool {
        return try database.checkDatabaseIntegrity()
    }

    func checkForeignKeys() throws -> Bool {
        return try database.checkForeignKeyIntegrity()
    }

    private func updateListeners() {

        NotificationCenter.default.removeObserver(self, name: .AutocommitStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(autocommitStatusChanged), name: .AutocommitStatusChanged, object: database)

    }

    @objc private func autocommitStatusChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            if self.database.autocommitStatus == .inTransaction {
                self.updateChangeCount(NSDocument.ChangeType.changeDone)
            } else {
                self.updateChangeCount(NSDocument.ChangeType.changeCleared)
            }
        }
    }

}
