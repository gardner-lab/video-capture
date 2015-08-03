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
    case Whitespace
    case ParenthesisOpen
    case ParenthesisClose
    case Number(s: String)
    case Placeholder(s: String)
    case Operator(s: String)
    
    init?(fromCharacter c: Character, after lastToken: EquationToken?) {
        switch c {
        case "(": self = .ParenthesisOpen
        case ")": self = .ParenthesisClose
        case "R": self = .Placeholder(s: String(c))
        case ".", "0"..."9": self = .Number(s: String(c))
        case "-":
            // only ambigious symbol, can be operator or can be number
            // yes, yes, a lexxer would be better. but this works
            if let token = lastToken {
                switch token {
                case .Number(_), .Placeholder(_), .ParenthesisClose: self = .Operator(s: String(c))
                case .Operator(_), .ParenthesisOpen: self = .Number(s: String(c))
                case .Whitespace: self = .Number(s: String(c)) // should never be called, since whitespace is ignored
                }
            }
            else {
                // no prior token, must be part of number
                self = .Number(s: String(c))
            }
        case " ", "\t","\r", "\n": self = .Whitespace
        default: self = .Operator(s: String(c))
        }
    }
    
    var description: String {
        get {
            switch self {
            case .Whitespace: return " "
            case .ParenthesisOpen: return "("
            case .ParenthesisClose: return ")"
            case .Number(let s): return s
            case .Placeholder(let s): return s
            case .Operator(let s): return s
            }
        }
    }
    
    mutating func matchCharacter(c: Character) -> Bool {
        switch self {
        case .Whitespace:
            switch c {
            case " ", "\t", "\r", "\n": return true
            default: return false
            }
        case .ParenthesisClose, .ParenthesisOpen: return false
        case .Number(let cur):
            switch c {
            case ".", "0"..."9":
                self = .Number(s: cur + String(c))
                return true
            default:
                return false
            }
        case .Placeholder(let cur):
            let new = cur + String(c)
            let re = Regex(pattern: "^R(|O(|I[0-9]*))$")
            if re.match(new) {
                self = .Placeholder(s: new)
                return true
            }
            return false
        case .Operator(let cur):
            // white space
            let ws = NSCharacterSet.whitespaceCharacterSet()
            if ws.characterIsMember(String(c).utf16.first!) {
                return false
            }
            
            // validate new combination is an operator
            let new = cur + String(c)
            if let _ = EquationOperator(fromString: new) {
                self = .Operator(s: new)
                return true
            }
            
            // other current
            if let _ = EquationToken(fromCharacter: c, after: self) {
                return false
            }
            
            // assume it is part of the operator
            self = .Operator(s: new)
            return true
        }
    }
    
    func isValid() -> Bool {
        switch self {
        case .Whitespace: return true
        case .ParenthesisClose, .ParenthesisOpen: return true
        case .Number(let s):
            if let _ = Float(s) {
                return true
            }
            return false
        case .Placeholder(let s):
            let re = Regex(pattern: "^ROI[0-9]+$")
            return re.match(s)
        case .Operator(let s):
            if let _ = EquationOperator(fromString: s) {
                return true
            }
            return false
        }
    }
    
    func isIgnored() -> Bool {
        switch self {
        case .Whitespace: return true
        default: return false
        }
    }
}

enum EquationError : ErrorType, CustomStringConvertible {
    case EmptyEquation
    case MissingToken
    case InvalidToken(token: String)
    case UnexpectedToken(token: String)
    case NoOperator(phrase: String)
    case MismatchedParentheses
    case TooDeep
    
    var description: String {
        get {
            switch self {
            case .EmptyEquation: return "The equation is empty or has an empty parenthetical."
            case .MissingToken: return "The equation is malformed. There is a missing placeholder or number."
            case .InvalidToken(let t): return "The equation contains an invalid token: \(t)."
            case .UnexpectedToken(let t): return "The token \(t) appears out of place in the equation."
            case .NoOperator(let p): return "There is no operator in the equation: \(p)."
            case .MismatchedParentheses: return "The parentheses in the equation are not balanced."
            case .TooDeep: return "The equation is too complex (maximum parsing depth of 50)."
            }
        }
    }
}

private func extractComponents(s: String) -> [EquationToken] {
    // empty
    if s.isEmpty {
        return []
    }
    
    // get current token
    var ret: [EquationToken] = []
    var cur: EquationToken? = nil
    var last: EquationToken? = nil
    for c in s.characters {
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
private func equationEnclosedInParentheses(tokens: [EquationToken]) -> Bool {
    if tokens.count < 2 {
        return false
    }
    switch tokens[tokens.startIndex] {
    case .ParenthesisOpen: break
    default: return false
    }
    switch tokens[tokens.endIndex - 1] {
    case .ParenthesisClose: break
    default: return false
    }
    var c = 0
    for i in (tokens.startIndex + 1)..<(tokens.endIndex - 1) {
        switch tokens[i] {
        case .ParenthesisOpen: ++c
        case .ParenthesisClose:
            if --c < 0 {
                return false
            }
        default: break
        }
    }
    return true
}

func equationParse(s: String) throws -> EquationElement {
    // get a list of tokens
    let tokens = extractComponents(s).filter {
        !$0.isIgnored()
    }
    
    // empty
    if tokens.isEmpty {
        throw EquationError.EmptyEquation
    }
    
    // invalid token encountered
    let invalid = tokens.filter {
        !$0.isValid()
    }
    guard invalid.isEmpty else {
        throw EquationError.InvalidToken(token: invalid.first!.description)
    }
    
    // find lowest
    return try equationParseTokens(tokens, depth: 0)
}

private func equationParseTokens(tokens: [EquationToken], depth: Int) throws -> EquationElement {
    // should always be a token
    if tokens.isEmpty {
        throw EquationError.MissingToken
    }
    
    // too deep
    if depth > 50 {
        throw EquationError.TooDeep
    }
    
    // single token, easy
    if tokens.count == 1 {
        switch tokens[0] {
        case .Number(let s):
            guard let v = Float(s) else {
                throw EquationError.InvalidToken(token: s)
            }
            return EquationNumber(value: v)
        case .Placeholder(let s):
            return EquationPlaceholder(name: s)
        default:
            throw EquationError.UnexpectedToken(token: tokens[0].description)
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
    for (i, t) in tokens.enumerate() {
        switch t {
        case .ParenthesisOpen:
            ++in_paren
        case .ParenthesisClose:
            if --in_paren < 0 {
                throw EquationError.MismatchedParentheses
            }
        case .Operator(let op_string) where in_paren == 0:
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
                throw EquationError.InvalidToken(token: op_string)
            }
        default: break
        }
    }
    
    // unclose parenthesis
    if 0 < in_paren {
        throw EquationError.MismatchedParentheses
    }
    
    // new initial
    if oper == nil {
        throw EquationError.NoOperator(phrase: "".join(tokens.map {
            $0.description
            }))
    }
    
    // split tokens
    let tokensLeft = Array(tokens[tokens.startIndex..<splt])
    let tokensRight = Array(tokens[(splt + 1)..<tokens.endIndex])
    
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
