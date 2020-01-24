//
//  Document.swift
//  NimbleCore
//
//  Created by Grigory Markin on 11.06.19.
//

import AppKit

// MARK: - Document

public protocol Document where Self: NSDocument {
  var observers: ObserverSet<DocumentObserver> { get set }
  
  var editor: WorkbenchEditor? { get }
      
  static var typeIdentifiers: [String] { get }
  
  static func isDefault(for file: File) -> Bool
  
  static func canOpen(_ file: File) -> Bool
  
  static var usupportedTypes: [String] { get }
}


public protocol DocumentController where Self: NSDocumentController {
  var currentWorkbench: Workbench? { get }
    
  func openDocument(_ doc: Document, display displayDocument: Bool) -> Void
}



public extension Document {
  static var usupportedTypes: [String] {
    return []
  }
  
  var path: Path? {
    guard let url = self.fileURL else { return nil }
    return Path(url: url)
  }
  
  var title: String {
    return path?.basename() ?? "untitled"
  }
  
  static func isDefault(for file: File) -> Bool {
    return false
  }
  
  static func canOpen(_ file: File) -> Bool {
    //dinamic UTI also can conforms to standart UTI
    //at the least one of public.item or public.contednt
    guard typeIdentifiers.contains(where: { file.url.typeIdentifierConforms(to: $0)}) else {
      return false
    }
    guard !usupportedTypes.contains(where: { file.url.typeIdentifierConforms(to: $0)}) else {
      return false
    }
    return true
  }
}


public protocol CreatableDocument where Self: Document {
  static var newMenuTitle: String { get }
  static func createUntitledDocument() -> Document?
}


// MARK: - Default document

open class NimbleDocument: NSDocument {
  public var observers = ObserverSet<DocumentObserver> ()

  override init() {
    super.init()
    NSFileCoordinator.addFilePresenter(self)
  }

  deinit {
    NSFileCoordinator.removeFilePresenter(self)
  }
  
  open override func updateChangeCount(_ change: NSDocument.ChangeType) {
    super.updateChangeCount(change)
    observers.notify {
      guard let doc = self as? Document else { return }
      $0.documentDidChange(doc)
    }
  }
}


// MARK: - Document Observer

public protocol DocumentObserver {
  func documentDidChange(_ document: Document)
}

public extension DocumentObserver {
  func documentDidChange(_ document: Document) {}
}

// MARK: - Document Manager

public class DocumentManager {
  public static let shared: DocumentManager = DocumentManager()
    
  private var documentClasses: [Document.Type] = []
  private var openedDocuments: [WeakRef<NSDocument>] = []
  public var defaultDocument: Document.Type? = nil
  
  public var typeIdentifiers: Set<String> {
    documentClasses.reduce(into: []) { $0.formUnion($1.typeIdentifiers) }
  }
  
  public var creatableDocuments: [CreatableDocument.Type] {
    documentClasses.compactMap{ $0 as? CreatableDocument.Type }
  }
  
  
  public func registerDocumentClass<T: Document>(_ docClass: T.Type) {
    documentClasses.append(docClass)
  }

  
  public func open(url: URL) -> Document? {
    guard let path = Path(url: url) else { return nil }

    return open(path: path)
  }

  public func open(path: Path) -> Document? {
    guard let file = File(path: path) else { return nil }

    return open(file: file)
  }

  public func open(file: File) -> Document? {
    guard let type = selectDocumentClass(for: file) else { return nil }

    return open(file: file, docType: type)
  }

  public func open(file: File, docType: Document.Type) -> Document? {
    if let doc = searchOpenedDocument(file) {
      return doc
    }

    guard let doc = try? docType.init(contentsOf: file.path.url, ofType: file.url.uti) else { return nil }
    
    openedDocuments.append(WeakRef<NSDocument>(value: doc))

    return doc
  }

  public func getSupportingDocumentTypes(of file: File) -> [Document.Type] {
    return documentClasses.filter { $0.canOpen(file) }
  }

  private func selectDocumentClass(for file: File) -> Document.Type? {
    var docClasses: [Document.Type] = []
    for dc in documentClasses {
      if dc.canOpen(file) {
        docClasses.append(dc)
        if dc.isDefault(for: file) {
          return dc
        }
      }
    }
    return docClasses.first ?? defaultDocument
  }
    
  private func searchOpenedDocument(_ file: File) -> Document? {
    openedDocuments.removeAll{ $0.value == nil }
    
    let ref = openedDocuments.first{
      guard let path = ($0.value as? Document)?.path else { return false}
      return path == file.path
    }
    
    return ref?.value as? Document
  }
}


// MARK: - Extensions

public extension File {
//  @discardableResult
//  func open(show: Bool = true) -> Document? {
//    var fileDoc: Document? = nil
//    NSDocumentController.shared.openDocument(withContentsOf: path.url, display: show) {doc, _, _ in
//      fileDoc = doc as? Document
//    }
//    return fileDoc
//  }
}
