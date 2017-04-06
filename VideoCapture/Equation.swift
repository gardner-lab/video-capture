//
//  Equation.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/28/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation

enum EquationOperator: CustomStringConvertible {
    case booleanAnd
    case booleanOr
    case compareEqual
    case compareGreaterThan
    case compareGreaterThanOrEqual
    case compareLessThan
    case compareLessThanOrEqual
    case arithmeticMultiply
    case arithmeticDivide
    case arithmeticAdd
    case arithmeticSubtract
    
    init?(fromString s: String) {
        switch s.lowercased() {
        case "&&": self = .booleanAnd
        case "||": self = .booleanOr
        case "==", "=": self = .compareEqual
        case ">": self = .compareGreaterThan
        case "<": self = .compareLessThan
        case ">=", "=>", "≥": self = .compareGreaterThanOrEqual
        case "<=", "=<", "≤": self = .compareLessThanOrEqual
        case "*", "×": self = .arithmeticMultiply
        case "/", "÷": self = .arithmeticDivide
        case "+": self = .arithmeticAdd
        case "-": self = .arithmeticSubtract
        default: return nil
        }
    }
    
    var description: String {
        get {
            switch self {
            case .booleanAnd: return "&&"
            case .booleanOr: return "||"
            case .compareEqual: return "="
            case .compareGreaterThan: return ">"
            case .compareGreaterThanOrEqual: return "≥"
            case .compareLessThan: return "<"
            case .compareLessThanOrEqual: return "≤"
            case .arithmeticMultiply: return "×"
            case .arithmeticDivide: return "÷"
            case .arithmeticAdd: return "+"
            case .arithmeticSubtract: return "-"
            }
        }
    }
    
    
    /// Somewhat counter-intuitive: The higher the precedence, the later the grouping. For example, `3*4+2` becomes `(3*4)+2`
    /// since multiplication has a lower precedence then addition (the addition is used to split the equation first).
    var precedence: Int {
        get {
            switch self {
            case .booleanAnd, .booleanOr:
                return 10
            case .compareEqual, .compareGreaterThan, .compareGreaterThanOrEqual, .compareLessThan, .compareLessThanOrEqual:
                return 20
            case .arithmeticAdd, .arithmeticSubtract:
                return 30
            case .arithmeticMultiply, .arithmeticDivide:
                return 40
            }
        }
    }
    
    /// If `leftAssociative == true`, then the right-most operator will be used to split the equation first. For example, `1+2+3`
    /// becomes `(1+2)+3`. For non-left associative operators, like boolean AND, then the left-most operator will be used to split
    /// the equation first. For example, `A&&B&&C` becomes `A&&(B&&C)`.
    var leftAssociative: Bool {
        get {
            switch self {
            case .arithmeticAdd, .arithmeticSubtract, .arithmeticMultiply, .arithmeticDivide:
                return true
            default:
                return false
            }
        }
    }
    
    func evaluate(_ lh: EquationElement, _ rh: EquationElement, placeholders: [String: Float]) -> Float {
        // lazy evaluation
        switch self {
        case .booleanAnd:
            if 0.0 >= lh.evaluate(placeholders) {
                return -1.0
            }
            if 0.0 >= rh.evaluate(placeholders) {
                return -1.0
            }
            return 1.0
        case .booleanOr:
            if 0.0 < lh.evaluate(placeholders) {
                return 1.0
            }
            if 0.0 < rh.evaluate(placeholders) {
                return 1.0
            }
            return -1.0
        default: break
        }
        
        // standard evaluation
        let left = lh.evaluate(placeholders)
        let right = rh.evaluate(placeholders)
        
        switch self {
        case .arithmeticAdd: return left + right
        case .arithmeticDivide:
            if right != 0 {
                return left / right
            }
            return Float.infinity
        case .arithmeticMultiply: return left * right
        case .arithmeticSubtract: return left - right
        case .compareEqual: return left == right ? 1.0 : -1.0
        case .compareGreaterThan: return left > right ? 1.0 : -1.0
        case .compareGreaterThanOrEqual: return left >= right ? 1.0 : -1.0
        case .compareLessThan: return left < right ? 1.0 : -1.0
        case .compareLessThanOrEqual: return left <= right ? 1.0 : -1.0
        case .booleanAnd, .booleanOr: return -1.0 // should never be reached
        }
    }
}

protocol EquationElement: CustomStringConvertible {
    func evaluate(_ placeholders: [String: Float]) -> Float
    func simplify() -> EquationElement
}

class EquationOperatorTriplet: EquationElement {
    let lhe: EquationElement
    let op: EquationOperator
    let rhe: EquationElement
    
    init(lhe: EquationElement, op: EquationOperator, rhe: EquationElement) {
        self.lhe = lhe
        self.op = op
        self.rhe = rhe
    }
    
    var description: String {
        get {
            return "(\(lhe.description) \(op.description) \(rhe.description))"
        }
    }
    
    func evaluate(_ placeholders: [String: Float]) -> Float {
        return op.evaluate(lhe, rhe, placeholders: placeholders)
    }
    
    func simplify() -> EquationElement {
        let newLhe = lhe.simplify(), newRhe = rhe.simplify()
        if newLhe is EquationNumber && newRhe is EquationNumber {
            let ph = [String: Float]()
            return EquationNumber(value: op.evaluate(newLhe, newRhe, placeholders: ph))
        }
        return EquationOperatorTriplet(lhe: newLhe, op: op, rhe: newRhe)
    }
}

class EquationNumber: EquationElement {
    let value: Float
    
    init(value: Float) {
        self.value = value
    }
    
    var description: String {
        get {
            return String(value)
        }
    }
    
    func evaluate(_ placeholders: [String: Float]) -> Float {
        return value
    }
    
    func simplify() -> EquationElement {
        return self
    }
}

class EquationPlaceholder: EquationElement {
    let name: String
    
    init(name: String) {
        self.name = name
    }
    
    var description: String {
        get {
            return name
        }
    }
    
    func evaluate(_ placeholders: [String: Float]) -> Float {
        if let v = placeholders[name] {
            return v
        }
        return 0.0
    }
    
    func simplify() -> EquationElement {
        return self
    }
}
