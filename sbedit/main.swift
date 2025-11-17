// sbEdit, a tool to edit the Finder's sidebar items
// 
// Works with macOS 14 and later (for the SFL3 file format)
// 
// Inspired by the AppleScript by com.cocolog-nifty.quicktimer
// https://quicktimer.cocolog-nifty.com/icefloe/2024/03/post-7f4cb0.html
// 
// Fabien Conus, 11.11.2025

import Foundation
import AppKit

enum MyError: Error {
    case inputOutputError(String)
}

/// Ajoute un élément à la liste des favoris du Finder (com.apple.LSSharedFileList.FavoriteItems.sfl3)
/// Compatible avec macOS 14 et ultérieur (format SFL3)

func main() {
    // Initialisation du fichier SFL3
    guard let sharedFileListURL = try? getSFL3path() else
    {
        print("Unable to get URL for the SFL3 file")
        exit(1)
    }
    if !FileManager.default.fileExists(atPath: sharedFileListURL.path) {
        createEmptySFL3(to: sharedFileListURL)
    }
        
    // On récupère les arguments en ignorant le chemin de l'exécutable
    let arguments = CommandLine.arguments.dropFirst()
    
    let command = arguments.first
    
    switch command {
    case "--add":
        let itemPaths = Array(arguments.dropFirst())
        add(items: itemPaths, to:sharedFileListURL)
    case "--removeAll":
        print("Removing all items from the sidebar")
        removeAll(from: sharedFileListURL)
    case "--reload":
        let force = arguments.contains(where: { $0 == "--force" })
        reloadServices(force: force)
    case "--list":
        list(contentof: sharedFileListURL)
    case "--remove":
        let itemPath = arguments.dropFirst().first ?? "no item"
        do {
            try remove(item: itemPath, from: sharedFileListURL)
        } catch {
            print(error)
            exit(1)
        }
    default:
        print("Unknown command \(command ?? "no command")")
        exit(1)
    }
}

func add(items itemPaths:[String], to sharedFileList:URL) {
    if itemPaths.isEmpty {
        print("Usage: script <chemin1> [chemin2] ...")
        exit(1)
    }
    
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileList)
    else {
        print("Error reading SFL3 file")
        exit(1)
    }
    
    // Traiter chaque chemin fourni et suivre les succès
    var hasSuccess = false
    
    for itemPath in itemPaths {
        do {
           try addItem(itemPath: itemPath, to:archiveDictM)
            hasSuccess = true
        } catch {
            print("Error adding item \(itemPath): \(error)")
        }
    }
        
    if !hasSuccess {
        exit(1)
    }
    
    do {
        try saveSFL3(file: sharedFileList, archiveDictM: archiveDictM)
    } catch {
        print(error)
    }
}

func removeAll(from sharedFileListURL:URL) {
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileListURL)
    else {
        print("Error reading SLF3 file")
        exit(1)
    }
    
    let itemsArrayM = NSMutableArray()
    
    // Mise à jour du dictionnaire principal
    archiveDictM.setObject(itemsArrayM, forKey: "items" as NSString)
    
    do {
        try saveSFL3(file: sharedFileListURL, archiveDictM: archiveDictM)
    } catch {
        print(error)
    }
}

func remove(item itemPath:String, from sharedFileListURL:URL) throws {
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileListURL)
    else {
        print("Error reading SLF3 file")
        exit(1)
    }
    
    // ============================================
    // Normalisation du chemin
    // ============================================
    let pathString = (itemPath as NSString).standardizingPath
    guard let addDirURL = URL(fileURLWithPath: pathString).absoluteURL as URL? else {
        print("Erreur : chemin invalide - \(itemPath)")
        throw MyError.inputOutputError("Erreur : chemin invalide - \(itemPath)")
    }
    
    let absoluteString = addDirURL.absoluteString
    
    // ============================================
    // Traitement des items
    // ============================================
    guard let itemsArray = archiveDictM.object(forKey: "items") as? NSArray else {
        print("Erreur : impossible de trouver les items")
        exit(1)
    }
    
    let itemsArrayM = NSMutableArray(array: itemsArray)
    
    for item in itemsArrayM {
        guard let itemDict = item as? NSDictionary,
              let bookmarkData = itemDict.object(forKey: "Bookmark") as? Data else {
            continue
        }
        
        var isStale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            if bookmarkURL.absoluteString == absoluteString {
                // Item was found -> remove it
                itemsArrayM.remove(item)
                break
            }
        }
    }
    
    // Mise à jour du dictionnaire principal
    archiveDictM.setObject(itemsArrayM, forKey: "items" as NSString)
    
    do {
        try saveSFL3(file: sharedFileListURL, archiveDictM: archiveDictM)
    } catch {
        print(error)
    }
}

func list(contentof sharedFileListURL:URL) {
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileListURL)
    else {
        print("Error reading SLF3 file")
        exit(1)
    }
        
    // ============================================
    // Traitement des items
    // ============================================
    guard let itemsArray = archiveDictM.object(forKey: "items") as? NSArray else {
        print("Erreur : impossible de trouver les items")
        exit(1)
    }
    
    for item in itemsArray {
        guard let itemDict = item as? NSDictionary,
              let bookmarkData = itemDict.object(forKey: "Bookmark") as? Data else {
            continue
        }
        
        var isStale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            print(bookmarkURL.absoluteString)
        }
    }
}

func addItem(itemPath: String, to archiveDictM:NSMutableDictionary) throws {
    // ============================================
    // Normalisation du chemin
    // ============================================
    let pathString = (itemPath as NSString).standardizingPath
    guard let addDirURL = URL(fileURLWithPath: pathString).absoluteURL as URL? else {
        print("Erreur : chemin invalide - \(itemPath)")
        throw MyError.inputOutputError("Erreur : chemin invalide - \(itemPath)")
    }
    
    let absoluteString = addDirURL.absoluteString
    print("Ajout de : \(absoluteString)")
    
    
    // ============================================
    // Traitement des items
    // ============================================
    guard let itemsArray = archiveDictM.object(forKey: "items") as? NSArray else {
        print("Erreur : impossible de trouver les items")
        throw MyError.inputOutputError("Erreur : impossible de trouver les items")
    }
    
    let itemsArrayM = NSMutableArray(array: itemsArray)
    
    // Vérification si l'élément existe déjà
    for item in itemsArrayM {
        guard let itemDict = item as? NSDictionary,
              let bookmarkData = itemDict.object(forKey: "Bookmark") as? Data else {
            continue
        }
        
        var isStale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            if bookmarkURL.absoluteString == absoluteString {
                print("L'élément existe déjà dans la liste")
                throw MyError.inputOutputError("L'élément existe déjà dans la liste")
            }
        }
    }
    
    // ============================================
    // Ajout du nouvel élément si nécessaire
    // ============================================
    let newItemDict = NSMutableDictionary()
    
    // CustomItemProperties
    if !addDirURL.lastPathComponent.contains("Desktop") {
        let customProperties = NSMutableDictionary()
        customProperties.setValue(NSNumber(value: 1), forKey: "com.apple.LSSharedFileList.ItemIsHidden") // 0=true, 1=false
        customProperties.setValue(NSNumber(value: 0), forKey: "com.apple.finder.dontshowonreappearance") // 0=true, 1=false
        
        
        newItemDict.setObject(customProperties, forKey: "CustomItemProperties" as NSString)
    }
    // UUID
    let uuid = UUID().uuidString
    newItemDict.setValue(uuid, forKey: "uuid")
    
    // Visibility
    newItemDict.setValue(NSNumber(value: 0), forKey: "visibility")
    
    // Bookmark
    if let bookmarkData = try? addDirURL.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) {
        newItemDict.setObject(bookmarkData, forKey: "Bookmark" as NSString)
    } else {
        print("Erreur : impossible de créer les données de bookmark")
        throw MyError.inputOutputError("Erreur : impossible de créer les données de bookmark")
    }
    
    // Ajout à l'array
    itemsArrayM.add(newItemDict)
    print("Élément ajouté avec succès")
    
    // Mise à jour du dictionnaire principal
    archiveDictM.setObject(itemsArrayM, forKey: "items" as NSString)
}

func reloadServices(force:Bool) {
    print("Rechargement des services...")
    
    var forceReload = force
    
    // Tenter de tuer sharedfilelistd
    let killProcess = Process()
    killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killProcess.arguments = ["sharedfilelistd"]
    
    do {
        try killProcess.run()
        killProcess.waitUntilExit()
    } catch {
        print("Unable to kill process")
        // Si killall échoue, essayer avec launchctl
        /*let agentPath = "/System/Library/LaunchAgents/com.apple.coreservices.sharedfilelistd.plist"
        
        let stopProcess = Process()
        stopProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        stopProcess.arguments = ["stop", "-w", agentPath]
        try? stopProcess.run()
        
        let startProcess = Process()
        startProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        startProcess.arguments = ["start", "-w", agentPath]
        try? startProcess.run()*/
        forceReload = true
    }
    
    if forceReload {
        // Relancer le Finder
        let killFinder = Process()
        killFinder.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killFinder.arguments = ["Finder"]
        try? killFinder.run()
    }
    
    print("Services rechargés")
}

func getSFL3path() throws -> URL {
    // ============================================
    // Obtention du chemin du fichier SFL3
    // ============================================
    let fileManager = FileManager.default
    let fileName = "com.apple.LSSharedFileList.FavoriteItems.sfl3"
    
    guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        print("Erreur : impossible de trouver le dossier Application Support")
        throw MyError.inputOutputError("Erreur : impossible de trouver le dossier Application Support")
    }
    
    let containerURL = appSupportURL.appendingPathComponent("com.apple.sharedfilelist", isDirectory: true)
    let sharedFileListURL = containerURL.appendingPathComponent(fileName, isDirectory: false)
    
    return sharedFileListURL
}

func openSFL3(sharedFileListURL:URL) throws -> NSMutableDictionary {
    // ============================================
    // Lecture et désarchivage du fichier SFL3
    // ============================================
    guard let plistData = try? Data(contentsOf: sharedFileListURL) else {
        print("Erreur : impossible de lire le fichier SFL3")
        throw MyError.inputOutputError("Erreur : impossible de lire le fichier SFL3")
    }
    
    // Définir les classes autorisées pour le désarchivage (utiliser un tableau)
    let allowedClasses: [AnyClass] = [
        NSDictionary.self,
        NSMutableDictionary.self,
        NSArray.self,
        NSMutableArray.self,
        NSString.self,
        NSMutableString.self,
        NSData.self,
        NSMutableData.self,
        NSNumber.self,
        NSUUID.self,
        NSDate.self
    ]
    
    var archivedDict:NSDictionary
    do {
        archivedDict = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: plistData) as! NSDictionary
    } catch {
        print("Erreur : impossible de désarchiver les données: \(error)")
        throw error
    }
    
    do {
        try archivedDict.write(to: URL(fileURLWithPath: "/tmp/archiveDict.plist"))
    } catch {
        print(error)
    }
    
    let archiveDictM = NSMutableDictionary(dictionary: archivedDict)
    
    return archiveDictM
}

func saveSFL3(file sharedFileListURL:URL, archiveDictM:NSMutableDictionary) throws {
    // ============================================
    // Archivage et sauvegarde
    // ============================================
    guard let saveData = try? NSKeyedArchiver.archivedData(withRootObject: archiveDictM, requiringSecureCoding: false) else {
        print("Erreur : impossible d'archiver les données")
        throw MyError.inputOutputError("Erreur : impossible d'archiver les données")
    }
    
    do {
        try saveData.write(to: sharedFileListURL, options: [])
        print("Fichier SFL3 sauvegardé avec succès")
    } catch {
        print("Erreur lors de la sauvegarde : \(error)")
        throw error
    }
    
}

func createEmptySFL3(to file:URL) {
    print("Création d'un fichier vide")
    let archiveDictM = NSMutableDictionary()
    
    let items = NSArray()
    archiveDictM.setObject(items, forKey: NSString("items"))
    
    let properties = NSDictionary(object: true, forKey: NSString("com.apple.LSSharedFileList.ForceTemplateIcons"))
    archiveDictM.setObject(properties, forKey: NSString("properties"))
    
    do {
        try saveSFL3(file: file, archiveDictM: archiveDictM)
    } catch {
        print(error)
    }
}

// Exécution du script
main()
