//
//  ScopeExtractor.swift
//  CodeEditorCore
//
//  Created by Grigory Markin on 04.07.19.
//

import AppKit
import Oniguruma
import NimbleCore

public protocol Tokenizer: class {
  func tokenize(_ str: String, in range: Range<String.Index>) -> TokenizerResult?
  func tokenize(_ str: String) -> TokenizerResult?
}

extension Tokenizer {
  func tokenize(_ str: String, in range: NSRange) -> TokenizerResult? {
    let begin = str.index(str.startIndex, offsetBy: range.lowerBound, limitedBy: str.endIndex) ?? str.endIndex
    let end = str.index(str.startIndex, offsetBy: range.upperBound, limitedBy: str.endIndex) ?? str.endIndex
    return tokenize(str, in: begin..<end)
  }
}

public struct TokenizerContext {
  let range: Range<Int>
  /// A match has to start before the `upperBound` if it's specified (larger than 0)
  let upperBound: Int
  let isFirstLine: Bool
  
  init(range: Range<Int>) {
    self.range = range
    self.upperBound = -1
    self.isFirstLine = true
  }
  
  init(range: Range<Int>, upperBound: Int, isFirstLine: Bool) {
    self.range = range
    self.upperBound = upperBound
    self.isFirstLine = isFirstLine
  }
    
  func with(range: Range<Int>? = nil,
            upperBound: Int? = nil,
            isFirstLine: Bool? = nil) -> TokenizerContext {
    
    return TokenizerContext(range: range ?? self.range,
                            upperBound: upperBound ?? self.upperBound,
                            isFirstLine: isFirstLine ?? self.isFirstLine)
  }
}

public struct TokenizerResult {
  var range: Range<Int>
  var nodes: [SyntaxNode]  
  var isEmpty: Bool { return range.isEmpty }
  
  init(range: Range<Int> = 0..<0, nodes: [SyntaxNode] = []) {
    self.range = range
    self.nodes = nodes
  }
  
  init(location: Int) {
    self.init(range: location..<location)
  }
  
  init(node: SyntaxNode) {
    self.range = node.range
    self.nodes = [node]

  }
}

public protocol TokenizerRepository: class {
  subscript(ref: GrammarRef) -> Tokenizer? { get }
}



// MARK: TM Tokenizer

protocol TMTokenizer: Tokenizer {
  typealias SearchResult = (range: Range<Int>, tokenize: () -> TokenizerResult)
  
  func prepare() -> Void
  
  func search(_: String, with: TokenizerContext) -> SearchResult?
  
  func tokenize(_: String, with: TokenizerContext) -> TokenizerResult?
}


extension TMTokenizer {
  func prepare() { }
  
  func tokenize(_ str: String) -> TokenizerResult? {
    return tokenize(str, in: str.range)
  }
  
  func tokenize(_ str: String, in range: Range<String.Index>) -> TokenizerResult? {
    guard !range.isEmpty else { return nil }
    
    let ctx = TokenizerContext(range: str.utf8(in: range), upperBound: -1, isFirstLine: true)
    return tokenize(str, with: ctx)
  }
  
  func tokenize(_ str: String, with ctx: TokenizerContext) -> TokenizerResult? {
    guard let (_, tokenize) = self.search(str, with: ctx) else { return nil }
    return tokenize()
  }
}


// MARK: Grammar extensions

extension Grammar {
  public func createTokenizer(with repo: TokenizerRepository) -> Tokenizer? {
    return GrammarTokenizer(self, with: repo)
  }
  
  func buildRepository(with global: TokenizerRepository) -> [String : Tokenizer] {
    return patterns.buildRepository(with: global, from: buildLocalRepo(with: global))
  }
}

extension GrammarRule {
  func buildLocalRepo(with global: TokenizerRepository) -> [String : Tokenizer] {
    return repository.reduce([:]) {
      var r = $0.merging($1.value.buildRepository(with: global)) { (current, _) in current }
      if let t = $1.value.createTokenizer(with: global) {
        r[$1.key] = t
      }
      return r
    }
  }
}

extension Array where Element == Pattern {
  func buildRepository(with global: TokenizerRepository, from local: [String : Tokenizer] = [:]) -> [String : Tokenizer] {
    return self.reduce(local) {
      return $0.merging($1.buildRepository(with: global)) { (current, _) in current }
    }
  }
}

extension Pattern {
  func createTokenizer(with repo: TokenizerRepository) -> TMTokenizer? {
    switch self {
    case .include(let p):
      return IncludeTokenizer(p, with: repo)
      
    case .match(let p):
      return MatchTokenizer(p, with: repo)
      
    case .beginEnd(let p):
      return BeginEndTokenizer(p, with: repo)
      
    case .beginWhile(let p):
      return BeginWhileTokenizer(p, with: repo)
      
    case .patterns(let p):
      return PatternsListTokenizer(p, with: repo)
    }
  }
  
  func buildRepository(with global: TokenizerRepository) -> [String : Tokenizer] {
    switch self {
    case .include(let p):
      return p.buildLocalRepo(with: global)
      
    case .match(let p):
      return p.buildLocalRepo(with: global)
      
    case .beginEnd(let p):
      return p.patterns.buildRepository(with: global, from: p.buildLocalRepo(with: global))
      
    case .beginWhile(let p):
      return p.patterns.buildRepository(with: global, from: p.buildLocalRepo(with: global))
      
    case .patterns(let p):
      return p.patterns.buildRepository(with: global, from: p.buildLocalRepo(with: global))
    }
  }
}


// MARK: Tokenizers

class GrammarTokenizer: PatternsListTokenizer {
  override func tokenize(_ str: String, with ctx: TokenizerContext) -> TokenizerResult? {

    let lines = str.utf8.lines(from: ctx.range)
    var linesRes = [TokenizerResult?](repeating: nil, count: lines.count)

    DispatchQueue.concurrentPerform(iterations: lines.count) {
      linesRes[$0] = applyTokenizers(tokenizers, to: str, with: ctx.with(range: lines[$0]))
    }

    var result: TokenizerResult? = nil

    for case let lineRes? in linesRes {
      guard let res = result else { merge(lineRes, into: &result); continue }
      if lineRes.range.lowerBound >= res.range.upperBound {
        merge(lineRes, into: &result)
      }
    }

    return result
  }
  
//  override func tokenize(_ str: String, with ctx: TokenizerContext) -> TokenizerResult? {
//    var result: TokenizerResult? = nil
//
//    var line = str.utf8.lineRange(at: ctx.range.lowerBound)
//    line = max(ctx.range.lowerBound, line.lowerBound)..<line.upperBound
//
//    while(line.lowerBound < ctx.range.upperBound && (ctx.upperBound < 0 || line.lowerBound < ctx.upperBound)) {
//      let res = applyTokenizers(tokenizers, to: str, with: ctx.with(range: line))
//      merge(res, into: &result)
//
//      if let res = result, res.range.upperBound > line.upperBound {
//        line = res.range.upperBound..<str.utf8.lineEnd(at: res.range.upperBound)
//      } else {
//        line = str.utf8.lineRange(at: line.upperBound)
//      }
//    }
//
//    return result
//  }
}


class PatternsListTokenizer: TMTokenizer {
  let tokenizers: [TMTokenizer]
  
  init (_ pattern: PatternsList , with repo: TokenizerRepository) {
    self.tokenizers = pattern.patterns.compactMap { $0.createTokenizer(with: repo) }
  }
  
  func search(_ str: String, with ctx: TokenizerContext) -> SearchResult? {
    return searchMatchingTokenizer(tokenizers, to: str, with: ctx)
  }
  
  open func tokenize(_ str: String, with ctx: TokenizerContext) -> TokenizerResult? {
    guard let (_, tokenize) = self.search(str, with: ctx) else { return nil }
    return tokenize()
  }
}


// MARK: -

class IncludeTokenizer: TMTokenizer {
  var ref: GrammarRef
  weak var repo: TokenizerRepository?
  
  // Emulate a lazy weak variable
  private var _init: Bool = false
  private var _queue: DispatchQueue = DispatchQueue(label: "com.nimble.IncludeTokenizer")
  private weak var _tokenizer: TMTokenizer? = nil
    
  var tokenizer: TMTokenizer? {
    return _queue.sync {
      if !self._init {
        //TODO: integrate other types of tokenizers
        self._tokenizer = repo?[ref] as? TMTokenizer
        self._init = true
      }
      return self._tokenizer
    }
  }
  
  init?(_ pattern: IncludePattern, with repo: TokenizerRepository) {
    guard let ref = pattern.ref else { return nil }
    self.ref = ref
    self.repo = repo
  }
      
  func search(_ str: String, with ctx: TokenizerContext) -> TMTokenizer.SearchResult? {
    guard let t = tokenizer else { return nil }
    return t.search(str, with: ctx)
  }
  
  public func prepare() {
    guard let t = tokenizer else { return }
    t.prepare()
  }
}


// MARK: -

typealias CaptureTokenizer = (`var`: MatchCapture.MatchGroup, (name: MatchName?, tokenizers: [TMTokenizer]))



// MARK: -
class MatchTokenizer: TMTokenizer {
  let name: MatchName?
  let match: MatchRegex
  let tokenizers: [CaptureTokenizer]
  
  init(_ pattern: MatchPattern, with repo: TokenizerRepository) {
    self.name = pattern.name
    self.match = pattern.match
    self.tokenizers = pattern.captures.map {
      ($0.key, $0.createTokenizer(with: repo))
    }
  }
      
  func search(_ str: String, with ctx: TokenizerContext) -> SearchResult? {
    guard let regex = match.get(allowA: ctx.isFirstLine, allowG: true),
          let res = regex.search(str, in: ctx.range),
          ctx.upperBound < 0 || res.range.lowerBound < ctx.upperBound else { return nil }
    
    return (res.range, {
      let nodes = applyCaptureTokenizers(self.tokenizers, to: str, with: res)
      return TokenizerResult(node: SyntaxNode(scope: self.name?.resolve(in: str, with: res),
                                              range: res.range,
                                              nodes: nodes))
      
    })
  }
}


// MARK: -

class RangeTokenizer {
  let name: MatchName?
  let contentName: MatchName?
  
  let contentTokenizers: [TMTokenizer]
  
  let begin: MatchRegex
  let beginTokenizers: [CaptureTokenizer]
  
  let pattern: RangeMatchPattern
  
  init(_ pattern: RangeMatchPattern, with repo: TokenizerRepository) {
    self.name = pattern.name
    self.contentName = pattern.contentName
    
    self.contentTokenizers = pattern.patterns.compactMap {
      $0.createTokenizer(with: repo)
    }
    
    self.begin = pattern.begin
    self.beginTokenizers = pattern.beginCaptures.map {
      ($0.key, $0.createTokenizer(with: repo))
    }
    
    //TODO: remove
    self.pattern = pattern
  }
}

// MARK: -

class BeginEndTokenizer: RangeTokenizer, TMTokenizer {
  let end: MatchRegex
  let endTokenizers: [CaptureTokenizer]

  init(_ pattern: BeginEndPattern, with repo: TokenizerRepository) {
    self.end = pattern.end
    self.endTokenizers = pattern.endCaptures.map {
      ($0.key, $0.createTokenizer(with: repo))
    }
    
    super.init(pattern, with: repo)
  }
  
  
  func search(_ str: String, with ctx: TokenizerContext) -> SearchResult? {
    /// A match has to start before the `upperBound` if it's larger than `range.lowerBound`
    guard let regex = self.begin.get(allowA: ctx.isFirstLine, allowG: true),
          let res = regex.search(str, in: ctx.range),
          ctx.upperBound < 0 || res.range.lowerBound < ctx.upperBound else { return nil }
    
    return (res.range, {
      return self.tokenize(str, with: ctx, from: res)
    })
  }
  
  func tokenize(_ str: String, with ctx: TokenizerContext, from beginRes: Regex.SearchResult) -> TokenizerResult {
    var isFirstLine = ctx.isFirstLine
    
    let begin = beginRes.range
    
    // Setup search space starting from begin and up to the current line's end
    var line = begin.upperBound..<str.utf8.lineEnd(at: begin.upperBound)
    var (end, endRes) = findEnd(str, start: line, isFirstLine: isFirstLine, isBegin: true)
    
    var content: TokenizerResult? = nil
              
    while(line.lowerBound < end.lowerBound) {
      while true {
        let res = applyTokenizers(contentTokenizers, to: str, with: ctx.with(range: line, upperBound: end.lowerBound))
        merge(res, into: &content)
        
        if let res = res, res.range.upperBound >= end.upperBound {
          line = res.range.upperBound..<str.utf8.lineEnd(at: res.range.upperBound)
          (end, endRes) = findEnd(str, start: line, isFirstLine: isFirstLine, isBegin: false)
        } else {
          break
        }
      }
              
      line = str.utf8.lineRange(at: line.upperBound)
      isFirstLine = false
    }
    
    
    
    var nodes: [SyntaxNode] = []
    

    // Begin node
    if !begin.isEmpty{
      let beginNode = SyntaxNode(scope: nil,
                                 range: begin.lowerBound..<begin.upperBound,
                                 nodes: applyCaptureTokenizers(beginTokenizers, to: str, with: beginRes))
      
      nodes.append(beginNode)
    }

    
    // Content node
    let contentNode = SyntaxNode(scope: contentName?.resolve(),
                                 range: begin.upperBound..<end.lowerBound,
                                 nodes: content?.nodes ?? [])
    
    nodes.append(contentNode)
    
    
    // End node
    if !end.isEmpty, let endRes = endRes {
      let endNode = SyntaxNode(scope: nil,
                               range: end.lowerBound..<end.upperBound,
                               nodes: applyCaptureTokenizers(endTokenizers, to: str, with: endRes))
      nodes.append(endNode)
    }
    
                
    return TokenizerResult(node: SyntaxNode(scope: name?.resolve(),
                                            range: begin.lowerBound..<end.upperBound,
                                            nodes: nodes))
  }
  
    
  func findEnd(_ str: String, start from: Range<Int>, isFirstLine: Bool, isBegin: Bool) -> (Range<Int>, Regex.SearchResult?) {
    var isFirstLine = isFirstLine
    if let regex = self.end.get(allowA: isFirstLine, allowG: isBegin) {
      var line = from
      while(line.lowerBound < str.utf8.count) {
        if let res = regex.search(str, in: line) {
          return (res.regs[0], res)
        }
        line = str.utf8.lineRange(at: line.upperBound)
        isFirstLine = false
      }
    }
    return (str.utf8.count..<str.utf8.count, nil)
  }
  
}



// MARK: -

class BeginWhileTokenizer: RangeTokenizer, TMTokenizer {
  let `while`: MatchRegex
  let whileTokenizers: [CaptureTokenizer]

  init(_ pattern: BeginWhilePattern, with repo: TokenizerRepository) {
    self.while = pattern.while
    self.whileTokenizers = pattern.whileCapture.map {
      ($0.key, $0.createTokenizer(with: repo))
    }
    super.init(pattern, with: repo)
  }
  
  func search(_: String, with ctx: TokenizerContext) -> SearchResult? {
    return nil
  }
}


// MARK: Utilities


fileprivate func merge(_ res1: TokenizerResult?, into res2: inout TokenizerResult?) -> Void {
  guard let res1 = res1 else { return }
  if var res = res2 {
    res.range = res.range.union(res1.range)
    res.nodes.append(contentsOf: res1.nodes)
    res2 = res
  } else {
    res2 = res1
  }
}


fileprivate func searchMatchingTokenizer(_ tokenizers: [TMTokenizer], to str: String, with ctx: TokenizerContext) -> TMTokenizer.SearchResult? {
  var result: TMTokenizer.SearchResult? = nil
  
  for t in tokenizers {
    guard let cur = t.search(str, with: ctx) else { continue }
    if cur.range.lowerBound == ctx.range.lowerBound {
      return cur
    }
    
    guard let res = result else { result = cur; continue }
    if cur.range.lowerBound < res.range.lowerBound {
      result = cur
    }
  }

  return result
}


fileprivate func applyTokenizers(_ tokenizers: [TMTokenizer], to str: String, with ctx: TokenizerContext) -> TokenizerResult? {
  
  var result: TokenizerResult? = nil
  var begin = ctx.range.lowerBound
  
  while begin < ctx.range.upperBound && (ctx.upperBound < 0 || begin < ctx.upperBound) {
    let ctx = ctx.with(range: begin..<ctx.range.upperBound)
    guard let (_, tokenize) = searchMatchingTokenizer(tokenizers, to: str, with: ctx) else { break }
    
    let cur = tokenize()
    
    merge(cur, into: &result)
    
    if begin < cur.range.upperBound {
      begin = cur.range.upperBound
    } else {
      begin += 1
    }
  }

  return result
}


fileprivate func applyCaptureTokenizers(_ tokenizers: [CaptureTokenizer], to str: String,
                                            with res: Regex.SearchResult) -> [SyntaxNode] {
  var nodes: [SyntaxNode] = []
  
  for t in tokenizers {
    var regs: [Range<Int>] = []
    
    switch t.var {
    case .index(let i):
      if i < res.regs.count {
        regs.append(res.regs[Int(i)])
      }
    case .name(let n):
      if let indices = res.names[n] {
        regs = indices.map {res.regs[$0]}
      }
    }
    
    for r in regs where !r.isEmpty {
      let tRes = applyTokenizers(t.1.tokenizers, to: str, with: TokenizerContext(range: r))
      nodes.append(
        SyntaxNode(scope: t.1.name?.resolve(in: str, with: res),
                   range: r,
                   nodes: tRes?.nodes ?? []))
    }
  }
  
  return nodes
}

// MARK: Extensions

extension MatchCapture {
  func createTokenizer(with repo: TokenizerRepository) -> (name: MatchName?, tokenizers: [TMTokenizer]) {
    return (name, patterns.compactMap { $0.createTokenizer(with: repo) })
  }
}


fileprivate let nameRegex = try? NSRegularExpression(pattern: "\\$([0-9]+)", options: [])

extension MatchName {
  func resolve(`in` str: String? = nil, with result: Oniguruma.Regex.SearchResult? = nil) -> SyntaxScope {
    guard let regex = nameRegex, let str = str, let res = result, res.regs.count > 0 else {
       return SyntaxScope(self.value)
    }
        
    var name = self.value
    
    regex.enumerateMatches(in: self.value, options: [], range: self.value.nsRange) { (match, _, _) in
      guard let match = match else { return }
      let r0 = match.range(at: 0)
      let r1 = match.range(at: 1)
      
      guard let i = Int((self.value as NSString).substring(with: r1)), i < res.regs.count else { return }
      
      let r = name.index(at: r0.lowerBound)..<name.index(at: r0.upperBound)
      let repl = str.chars(utf8: res.regs[i])
      
      name.replaceSubrange(r, with: str[repl])
    }
    
    return SyntaxScope(name)
  }
}
