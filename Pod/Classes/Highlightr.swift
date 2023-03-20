//
//  Highlightr.swift
//  Pods
//
//  Created by Illanes, J.P. on 4/10/16.
//
//

import Foundation
import JavaScriptCore
#if os(OSX)
import AppKit
#elseif os(iOS)
import UIKit
#endif


/// Utility class for generating a highlighted NSAttributedString from a String.
open class Highlightr
{
  /// Returns the current Theme.
  open var theme : Theme!
  {
    didSet
    {
      themeChanged?(theme)
    }
  }
  
  open var interfaceStyle: UIUserInterfaceStyle = .light {
    didSet {
      switch interfaceStyle {
      case .unspecified, .light:
        setTheme(to: "medium-light")
      case .dark:
        setTheme(to: "medium-dark")
      @unknown default:
        setTheme(to: "medium-light")
      }
    }
  }
  
  public static let shared = Highlightr()
  
  /// This block will be called every time the theme changes.
  open var themeChanged : ((Theme) -> Void)?
  
  /// Defaults to `false` - when `true`, forces highlighting to finish even if illegal syntax is detected.
  open var ignoreIllegals = false
  
  private let hljs: JSValue
  
  private let bundle : Bundle
  private let htmlStart = "<"
  private let spanStart = "span class=\""
  private let spanStartClose = "\">"
  private let spanEnd = "/span>"
  private let htmlEscape = try! NSRegularExpression(pattern: "&#?[a-zA-Z0-9]+?;", options: .caseInsensitive)
  
  public struct Result {
    public let attributedString: NSAttributedString?
    public let language: String?
  }
  
  /**
   Default init method.
   
   - parameter highlightPath: The path to `highlight.min.js`. Defaults to `Highlightr.framework/highlight.min.js`
   
   - returns: Highlightr instance.
   */
  public init?(highlightPath: String? = nil)
  {
    guard let jsContext = JSContext() else {
      return nil
    }
#if SWIFT_PACKAGE
    let bundle = Bundle.module
#else
    let bundle = Bundle(for: Highlightr.self)
#endif
    self.bundle = bundle
    guard let hgPath = highlightPath ?? bundle.path(forResource: "highlight.min", ofType: "js") else {
      return nil
    }
    
    do {
      let hgJs = try String.init(contentsOfFile: hgPath)
      jsContext.evaluateScript(hgJs)
      self.hljs = jsContext.evaluateScript("hljs")
      guard setTheme(to: "medium-light") else {
        return nil
      }
    } catch {
      return nil
    }
  }
  
  /**
   Set the theme to use for highlighting.
   
   - parameter to: Theme name
   
   - returns: true if it was possible to set the given theme, false otherwise
   */
  @discardableResult
  open func setTheme(to name: String) -> Bool
  {
    guard let defTheme = bundle.path(forResource: name, ofType: "css") else
    {
      return false
    }
    let themeString = try! String.init(contentsOfFile: defTheme)
    theme =  Theme(themeString: themeString)
    
    
    return true
  }
  
  /**
   Takes a String and returns a NSAttributedString with the given language highlighted.
   
   - parameter code:           Code to highlight.
   - parameter languageName:   Language name or alias. Set to `nil` to use auto detection.
   - parameter fastRender:     Defaults to true - When *true* will use the custom made html parser rather than Apple's solution.
   
   - returns: NSAttributedString with the detected code highlighted.
   */
  open func highlight(_ code: String, as languageName: String? = nil, fastRender: Bool = true) -> Result?
  {
    let ret: JSValue
    if let languageName = languageName
    {
      ret = hljs.invokeMethod("highlight", withArguments: [languageName, code, ignoreIllegals])
    }else
    {
      // language auto detection
      ret = hljs.invokeMethod("highlightAuto", withArguments: [code])
    }
    
    let res = ret.objectForKeyedSubscript("value")
    let language = ret.objectForKeyedSubscript("language").toString()
    guard var string = res!.toString() else
    {
      return nil
    }
    
    var returnString : NSAttributedString?
    if(fastRender)
    {
      returnString = processHTMLString(string)!
    }else
    {
      string = "<style>"+theme.lightTheme+"</style><pre><code class=\"hljs\">"+string+"</code></pre>"
      let opt: [NSAttributedString.DocumentReadingOptionKey : Any] = [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
      ]
      
      let data = string.data(using: String.Encoding.utf8)!
      safeMainSync
      {
        returnString = try? NSMutableAttributedString(data:data, options: opt, documentAttributes:nil)
      }
    }
    
    return .init(attributedString: returnString, language: language)
  }
  
  /**
   Returns a list of all the available themes.
   
   - returns: Array of Strings
   */
  open func availableThemes() -> [String]
  {
    let paths = bundle.paths(forResourcesOfType: "css", inDirectory: nil) as [NSString]
    var result = [String]()
    for path in paths {
      result.append(path.lastPathComponent.replacingOccurrences(of: ".min.css", with: ""))
    }
    
    return result
  }
  
  /**
   Returns a list of all supported languages.
   
   - returns: Array of Strings
   */
  open func supportedLanguages() -> [String]
  {
    let res = hljs.invokeMethod("listLanguages", withArguments: [])
    return res!.toArray() as! [String]
  }
  
  /**
   Execute the provided block in the main thread synchronously.
   */
  private func safeMainSync(_ block: @escaping ()->())
  {
    if Thread.isMainThread
    {
      block()
    }else
    {
      DispatchQueue.main.sync { block() }
    }
  }
  
  private func processHTMLString(_ string: String) -> NSAttributedString?
  {
    let scanner = Scanner(string: string)
    scanner.charactersToBeSkipped = nil
    var scannedString: String?
    let resultString = NSMutableAttributedString(string: "")
    var propStack = ["hljs"]
    
    while !scanner.isAtEnd
    {
      var ended = false
      if let result = scanner.scanUpToString(htmlStart)
      {
        scannedString = result
        if scanner.isAtEnd
        {
          ended = true
        }
      }
      
      if scannedString != nil && scannedString!.utf8.count > 0 {
        let attrScannedString = theme.applyStyleToString(scannedString! as String, styleList: propStack)
        resultString.append(attrScannedString)
        if ended
        {
          continue
        }
      }
      
      scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
      
      let nextChar = scanner.string[scanner.currentIndex]
      if(nextChar == "s") {
        scanner.currentIndex = scanner.string.index(scanner.currentIndex, offsetBy: spanStart.utf8.count)
        scannedString = scanner.scanUpToString(spanStartClose)
        /// Test that advancing the index of the string is in the boundary of the string without invoking
        /// `offsetBy` which is unsafe.
        let currentString = scanner.string[scanner.string.startIndex..<scanner.currentIndex]
        if currentString.utf8.count + spanStartClose.utf8.count < scanner.string.utf8.count {
          scanner.currentIndex = scanner.string.index(scanner.currentIndex, offsetBy: spanStartClose.utf8.count)
          propStack.append(scannedString!)
        }
      } else if(nextChar == "/") {
        scanner.currentIndex = scanner.string.index(scanner.currentIndex, offsetBy: spanEnd.utf8.count)
        propStack.removeLast()
      } else {
        let attrScannedString = theme.applyStyleToString("<", styleList: propStack)
        resultString.append(attrScannedString)
        scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
      }
      
      scannedString = nil
    }
    
    let results = htmlEscape.matches(in: resultString.string,
                                     options: [.reportCompletion],
                                     range: NSMakeRange(0, resultString.length))
    var locOffset = 0
    for result in results
    {
      let fixedRange = NSMakeRange(result.range.location-locOffset, result.range.length)
      let entity = (resultString.string as NSString).substring(with: fixedRange)
      if let decodedEntity = HTMLUtils.decode(entity)
      {
        resultString.replaceCharacters(in: fixedRange, with: String(decodedEntity))
        locOffset += result.range.length-1;
      }
      
      
    }
    
    return resultString
  }
  
}
