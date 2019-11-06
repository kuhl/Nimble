//
//  SourceCodeDocument.swift
//  CodeEditor
//
//  Created by Grigory Markin on 13.06.19.
//  Copyright © 2019 SCADE. All rights reserved.
//

import AppKit
import NimbleCore
import CodeEditor

public final class SourceCodeDocument: NSDocument, TextDocument {
  let textStorage = NSTextStorage()
  
  public var observer: DocumentObserver? = nil
  
  var changed : Bool = false {
    didSet {
      if changed {
        self.observer?.documentDidChange(self)
      } else {
        self.observer?.documentDidSave(self)
      }
    }
  }
  
  public var isChanged : Bool{
    get {
      return changed
    }
  }
  
  public var language: Language? {
    didSet {
      guard let grammar = language?.grammar else { return }
      self.syntaxParser = SyntaxParser(textStorage: textStorage, grammar: grammar)
    }
  }
  
  
  private var languageFromURL: Language? {
    return self.fileURL?.file?.language
  }
  
  public var syntaxParser: SyntaxParser?
  
  private lazy var editorController: CodeEditorController = {
    let controller = CodeEditorController.loadFromNib()
    controller.doc = self
    return controller
  }()
  
  public var contentViewController: NSViewController? { return editorController }
  
  public var languageId: String {
    if let lang = language {
      return lang.id
    }
    guard let id = languageFromURL?.id else { return "" }
    return id
  }
  
  public lazy var delegates: [TextDocumentDelegate] = {
    return TextDocumentDelegateManager.shared.createDelegates(for: self)
  }()
  
  public class func canOpen(_ file: File) -> Bool {
    guard !file.uti.starts(with: "dy") else {
      return true
    }
    return file.typeIdentifierConforms(to: "public.text") || file.typeIdentifierConforms(to: "public.svg-image")
  }
  
  public override func read(from url: URL, ofType typeName: String) throws {
    self.language = url.file?.language
    try super.read(from: url, ofType: typeName)
  }
  
  public override func read(from data: Data, ofType typeName: String) throws {
    guard let str =  String(bytes: data, encoding: .utf8) else {
      throw NSError.init(domain: "NimbleCodeEditor", code: 1, userInfo: ["FileUrl": self.fileURL ?? ""])
    }
    let content = str.replacingLineEndings(with: .lf)
    textStorage.replaceCharacters(in: textStorage.range, with: content)
  }
  
  public override func data(ofType typeName: String) throws -> Data {
    return textStorage.string.data(using: .utf8)!
  }
  
  public override func save(_ sender: Any?) {
    changed = false
    super.save(sender)
  }
  
  public override func saveAs(_ sender: Any?) {
    changed = false
    super.saveAs(sender)
  }
}
