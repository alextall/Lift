//
//  AppDelegate.swift
//  Lift
//
//  Created by Carl Wieland on 9/28/17.
//  Copyright © 2017 Datum Apps. All rights reserved.
//

import Cocoa
// Pick a preference key to store the shortcut between launches

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    public static let runGlobalShortcut = "GlobalRunShortcut"

    override init() {
        UserDefaults.standard.register(defaults: ["suggestCompletions": true])

        MASShortcutBinder.shared()?.registerDefaultShortcuts([AppDelegate.runGlobalShortcut: MASShortcut(keyCode: kVK_F5, modifierFlags: [])])

        ValueTransformer.setValueTransformer(RowCountFormatter(), forName: NSValueTransformerName(rawValue: "RowCountFormatter"))
        ValueTransformer.setValueTransformer(URLPathFormatter(), forName: NSValueTransformerName("URLPathFormatter"))
    }
    #if FREE
    private weak var supportViewController: SupportLiftViewController?
    #endif

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        #if FREE
        pesterBuy()
        #endif
    }

    func pesterBuy() {
        #if FREE
        var time = 60
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(time)) { [weak self] in
            if !UserDefaults.standard.bool(forKey: "supportedLift") && self?.supportViewController == nil {
                let storyboard = NSStoryboard(name: .main, bundle: nil)
                if let contentViewController = NSApp.windows.last?.contentViewController, let vc = storyboard.instantiateController(withIdentifier: "supportLiftVC") as? SupportLiftViewController {
                    self?.supportViewController = vc
                    if contentViewController.children.lastIndex(where: { $0 is SupportLiftViewController}) == nil {
                        contentViewController.presentAsSheet(vc)
                    }
                }
            }
            time += (time * 4)
            time = min(time, 60 * 15)
            if time < (60 * 60) && !UserDefaults.standard.bool(forKey: "supportedLift") {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(time), execute: {self?.pesterBuy()})
            }
        }

        print("free version!")
        #endif
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if !UserDefaults.standard.bool(forKey: "hideWelcomeScreenOnLaunch") {
            createAndShowWelcome()
        }
        return false
    }

    @IBAction func showWelcomeToLiftWindow(_ sender: Any) {
        for window in NSApp.windows where window.contentViewController is WelcomeViewController {
            window.makeKeyAndOrderFront(self)
            return
        }
        createAndShowWelcome()
    }

    private func createAndShowWelcome() {
        let storyboard = NSStoryboard(name: .main, bundle: .main)

        guard let windowController = storyboard.instantiateController(withIdentifier: "welcomeWindow") as? WelcomeWindowController else {
            fatalError("Error getting main window controller")
        }
        windowController.showWindow(self)
    }
    @IBAction func showSupport(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://www.datumapps.com/contact-us/")!)
    }

    @IBAction func sendFeedback(_ sender: Any) {
        let encodedSubject = "SUBJECT=Feedback"
        let encodedTo = "carl@datumapps.com".addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)!
        let urlstring = "mailto:\(encodedTo)?\(encodedSubject)"
        if let url = URL(string: urlstring) {
            NSWorkspace.shared.open(url)
        }
    }

    @IBAction func newInMemoryFile(_ sender: Any) {
        NSDocumentController.shared.newDocument(self)
    }

    @IBAction func newFileDocument(_ sender: Any) {
        let spanel = NSSavePanel()
        spanel.canCreateDirectories = true
        spanel.canSelectHiddenExtension = true
        spanel.treatsFilePackagesAsDirectories = true
        spanel.begin { (response) in
            if response == .OK, let url = spanel.url {
                do {
                    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
                    let document = try LiftDocument(contentsOf: url, ofType: "db")
                    document.makeWindowControllers()
                    document.showWindows()
                    NSDocumentController.shared.addDocument(document)
                    NSDocumentController.shared.noteNewRecentDocument(document)
                } catch {
                    NSApplication.shared.presentError(error)
                }
            }
        }
    }
}

extension NSStoryboard.Name {
    static let main = "Main"
    static let createItems = "CreateItems"
    static let importExport = "ImportExport"
    static let constraints = "Constraints"
}
