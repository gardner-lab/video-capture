//
//  EquationParser.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/28/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation

/// The equation tokens that are used to construct the equation element tree.
private enum EquationToken: CustomStringConvertible {
    case whitespace
    case parenthesisOpen
    case parenthesisClose
    case number(s: String)
    case placeholder(s: String)
    case `operator`(s: String)
    
    init?(fromCharacter c: Character, after lastToken: EquationToken?) {
        switch c {
        case "(": self = .parenthesisOpen
        case ")": self = .parenthesisClose
        case "R": self = .placeholder(s: String(c))
        case ".", "0"..."9": self = .number(s: String(c))
        case "-":
            // only ambigious symbol, can be operator or can be number
            // yes, yes, a lexxer would be better. but this works
            if let token = lastToken {
                switch token {
                case .number(_), .placeholder(_), .parenthesisClose: self = .operator(s: String(c))
                case .operator(_), .parenthesisOpen: self = .number(s: String(c))
                case .whitespace: self = .number(s: String(c)) // should never be called, since whitespace is ignored
                }
            }
            else {
                // no prior token, must be part of number
                self = .number(s: String(c))
            }
        case " ", "\t","\r", "\n": self = .whitespace
        default: self = .operator(s: String(c))
        }
    }
    
    var description: String {
        get {
            switch self {
            case .whitespace: return " "
            case .parenthesisOpen: return "("
            case .parenthesisClose: return ")"
            case .number(let s): return s
            case .placeholder(let s): return s
            case .operator(let s): return s
            }
        }
    }
    
    mutating func matchCharacter(_ c: Character) -> Bool {
        switch self {
        case .whitespace:
            switch c {
            case " ", "\t", "\r", "\n": return true
            default: return false
            }
        case .parenthesisClose, .parenthesisOpen: return false
        case .number(let cur):
            switch c {
            case ".", "0"..."9":
                self = .number(s: cur + String(c))
                return true
            default:
                return false
            }
        case .placeholder(let cur):
            let new = cur + String(c)
            let re = Regex(pattern: "^R(|O(|I[0-9]*))$")
            if re.match(new) {
                self = .placeholder(s: new)
                return true
            }
            return false
        case .operator(let cur):
            // white space
            let ws = CharacterSet.whitespaces
            if ws.contains(UnicodeScalar(String(c).utf16.first!)!) {
                return false
            }
            
            // validate new combination is an operator
            let new = cur + String(c)
            if let _ = EquationOperator(fromString: new) {
                self = .operator(s: new)
                return true
            }
            
            // other current
            if let _ = EquationToken(fromCharacter: c, after: self) {
                return false
            }
            
            // assume it is part of the operator
            self = .operator(s: new)
            return true
        }
    }
    
    func isValid() -> Bool {
        switch self {
        case .whitespace: return true
        case .parenthesisClose, .parenthesisOpen: return true
        case .number(let s):
            if let _ = Float(s) {
                return true
            }
            return false
        case .placeholder(let s):
            let re = Regex(pattern: "^ROI[0-9]+$")
            return re.match(s)
        case .operator(let s):
            if let _ = EquationOperator(fromString: s) {
                return true
            }
            return false
        }
    }
    
    func isIgnored() -> Bool {
        switch self {
        case .whitespace: return true
        default: return false
        }
    }
}

enum EquationError : Error, CustomStringConvertible {
    case emptyEquation
    case missingToken
    case invalidToken(token: String)
    case unexpectedToken(token: String)
    case noOperator(phrase: String)
    case mismatchedParentheses
    case tooDeep
    
    var description: String {
        get {
            switch self {
            case .emptyEquation: return "The equation is empty or has an empty parenthetical."
            case .missingToken: return "The equation is malformed. There is a missing placeholder or number."
            case .invalidToken(let t): return "The equation contains an invalid token: \(t)."
            case .unexpectedToken(let t): return "The token \(t) appears out of place in the equation."
            case .noOperator(let p): return "There is no operator in the equation: \(p)."
            case .mismatchedParentheses: return "The parentheses in the equation are not balanced."
            case .tooDeep: return "The equation is too complex (maximum parsing depth of 50)."
            }
        }
    }
}

private func extractComponents(_ s: String) -> [EquationToken] {
    // empty
    if s.isEmpty {
        return []
    }
    
    // get current token
    var ret: [EquationToken] = []
    var cur: EquationToken? = nil
    var last: EquationToken? = nil
    for c in s {
        if nil == cur {
            // start new token
            cur = EquationToken(fromCharacter: c, after: last)
        }
        else {
            // match as part of current token
            if !cur!.matchCharacter(c) {
                // current token is over, append it to the output list
                ret.append(cur!)
                
                // not ignored? use as last
                if !cur!.isIgnored() {
                    last = cur
                }
                
                // start new token
                cur = EquationToken(fromCharacter: c, after: last)
            }
        }
    }
    if nil != cur {
        ret.append(cur!)
    }
    
    return ret
}

/// Returns true if the array of tokens is enclosed in a single set of parentheses. For example, (...) -> True, (...)+(...) -> False
private func equationEnclosedInParentheses(_ tokens: [EquationToken]) -> Bool {
    if tokens.count < 2 {
        return false
    }
    switch tokens[tokens.startIndex] {
    case .parenthesisOpen: break
    default: return false
    }
    switch tokens[tokens.endIndex - 1] {
    case .parenthesisClose: break
    default: return false
    }
    var c = 0
    for i in (tokens.startIndex + 1)..<(tokens.endIndex - 1) {
        switch tokens[i] {
        case .parenthesisOpen: c += 1
        case .parenthesisClose:
            c -= 1
            if c < 0 {
                return false
            }
        default: break
        }
    }
    return true
}

func equationParse(_ s: String) throws -> EquationElement {
    // get a list of tokens
    let tokens = extractComponents(s).filter {
        !$0.isIgnored()
    }
    
    // empty
    if tokens.isEmpty {
        throw EquationError.emptyEquation
    }
    
    // invalid token encountered
    let invalid = tokens.filter {
        !$0.isValid()
    }
    guard invalid.isEmpty else {
        throw EquationError.invalidToken(token: invalid.first!.description)
    }
    
    // find lowest
    return try equationParseTokens(tokens, depth: 0)
}

private func equationParseTokens(_ tokens: [EquationToken], depth: Int) throws -> EquationElement {
    // should always be a token
    if tokens.isEmpty {
        throw EquationError.missingToken
    }
    
    // too deep
    if depth > 50 {
        throw EquationError.tooDeep
    }
    
    // single token, easy
    if tokens.count == 1 {
        switch tokens[0] {
        case .number(let s):
            guard let v = Float(s) else {
                throw EquationError.invalidToken(token: s)
            }
            return EquationNumber(value: v)
        case .placeholder(let s):
            return EquationPlaceholder(name: s)
        default:
            throw EquationError.unexpectedToken(token: tokens[0].description)
        }
    }

    // is enclosed? remove parentheses
    if equationEnclosedInParentheses(tokens) {
        return try equationParseTokens(Array(tokens[(tokens.startIndex + 1)..<(tokens.endIndex - 1)]), depth: depth + 1)
    }
    
    // multiple tokens, find operator
    var splt: Int = -1
    var precedence: Int = Int.max
    var oper: EquationOperator?
    var in_paren: Int = 0
    for (i, t) in tokens.enumerated() {
        switch t {
        case .parenthesisOpen:
            in_paren += 1
        case .parenthesisClose:
            in_paren -= 1
            if in_paren < 0 {
                throw EquationError.mismatchedParentheses
            }
        case .operator(let op_string) where in_paren == 0:
            if let op = EquationOperator(fromString: op_string) {
                let p = op.precedence
                if p < precedence || (p == precedence && op.leftAssociative) {
                    precedence = p
                    splt = i
                    oper = op
                }
            }
            else {
                // should not happen, already filtered for valid
                throw EquationError.invalidToken(token: op_string)
            }
        default: break
        }
    }
    
    // unclose parenthesis
    if 0 < in_paren {
        throw EquationError.mismatchedParentheses
    }
    
    // new initial
    if oper == nil {
        throw EquationError.noOperator(phrase: tokens.map({ $0.description }).joined(separator: ""))
    }
    
    // split tokens
    let tokensLeft = Array(tokens[tokens.startIndex..<splt])
    let tokensRight = Array(tokens[tokens.indices.suffix(from: (splt + 1))])
    
    // parse left and right
    let elLeft = try equationParseTokens(tokensLeft, depth: depth + 1)
    let elRight = try equationParseTokens(tokensRight, depth: depth + 1)
    
    return EquationOperatorTriplet(lhe: elLeft, op: oper!, rhe: elRight)
}

//
//func seperate(s: String, sep: NSCharacterSet, includeEmpty: Bool = false) -> [String] {
//    if s.isEmpty {
//        return []
//    }
//    
//    let asUtf = s.utf16
//    var last = sep.characterIsMember(asUtf.first!), cur: Bool, val = "", ret: [String] = []
//    for c in asUtf {
//        // change type
//        cur = sep.characterIsMember(c)
//        if last != cur {
//            if includeEmpty || !val.isEmpty {
//                ret.append(val)
//            }
//            val = ""
//            last = cur
//        }
//        
//        // apend
//        val += String(c)
//    }
//    
//    // append final
//    if includeEmpty || !val.isEmpty {
//        ret.append(val)
//    }
//    
//    return ret
//}
