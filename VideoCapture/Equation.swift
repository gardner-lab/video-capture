//
//  Equation.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/28/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation

enum EquationOperator: CustomStringConvertible {
    case BooleanAnd
    case BooleanOr
    case CompareEqual
    case CompareGreaterThan
    case CompareGreaterThanOrEqual
    case CompareLessThan
    case CompareLessThanOrEqual
    case ArithmeticMultiply
    case ArithmeticDivide
    case ArithmeticAdd
    case ArithmeticSubtract
    
    init?(fromString s: String) {
        switch s.lowercaseString {
        case "&&": self = .BooleanAnd
        case "||": self = .BooleanOr
        case "==", "=": self = .CompareEqual
        case ">": self = .CompareGreaterThan
        case "<": self = .CompareLessThan
        case ">=", "=>", "≥": self = .CompareGreaterThanOrEqual
        case "<=", "=<", "≤": self = .CompareLessThanOrEqual
        case "*", "×": self = .ArithmeticMultiply
        case "/", "÷": self = .ArithmeticDivide
        case "+": self = .ArithmeticAdd
        case "-": self = .ArithmeticSubtract
        default: return nil
        }
    }
    
    var description: String {
        get {
            switch self {
            case .BooleanAnd: return "&&"
            case .BooleanOr: return "||"
            case .CompareEqual: return "="
            case .CompareGreaterThan: return ">"
            case .CompareGreaterThanOrEqual: return "≥"
            case .CompareLessThan: return "<"
            case .CompareLessThanOrEqual: return "≤"
            case .ArithmeticMultiply: return "×"
            case .ArithmeticDivide: return "÷"
            case .ArithmeticAdd: return "+"
            case .ArithmeticSubtract: return "-"
            }
        }
    }
    
    
    /// Somewhat counter-intuitive: The higher the precedence, the later the grouping. For example, `3*4+2` becomes `(3*4)+2`
    /// since multiplication has a lower precedence then addition (the addition is used to split the equation first).
    var precedence: Int {
        get {
            switch self {
            case .BooleanAnd, .BooleanOr:
                return 10
            case .CompareEqual, .CompareGreaterThan, .CompareGreaterThanOrEqual, .CompareLessThan, .CompareLessThanOrEqual:
                return 20
            case .ArithmeticAdd, .ArithmeticSubtract:
                return 30
            case .ArithmeticMultiply, .ArithmeticDivide:
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
            case .ArithmeticAdd, .ArithmeticSubtract, .ArithmeticMultiply, .ArithmeticDivide:
                return true
            default:
                return false
            }
        }
    }
    
    func evaluate(lh: EquationElement, _ rh: EquationElement, placeholders: [String: Float]) -> Float {
        // lazy evaluation
        switch self {
        case .BooleanAnd:
            if 0.0 >= lh.evaluate(placeholders) {
                return -1.0
            }
            if 0.0 >= rh.evaluate(placeholders) {
                return -1.0
            }
            return 1.0
        case .BooleanOr:
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
        case .ArithmeticAdd: return left + right
        case .ArithmeticDivide:
            if right != 0 {
                return left / right
            }
            return Float.infinity
        case .ArithmeticMultiply: return left * right
        case .ArithmeticSubtract: return left - right
        case .CompareEqual: return left == right ? 1.0 : -1.0
        case .CompareGreaterThan: return left > right ? 1.0 : -1.0
        case .CompareGreaterThanOrEqual: return left >= right ? 1.0 : -1.0
        case .CompareLessThan: return left < right ? 1.0 : -1.0
        case .CompareLessThanOrEqual: return left <= right ? 1.0 : -1.0
        case .BooleanAnd, .BooleanOr: return -1.0 // should never be reached
        }
    }
}

protocol EquationElement: CustomStringConvertible {
    func evaluate(placeholders: [String: Float]) -> Float
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
    
    func evaluate(placeholders: [String: Float]) -> Float {
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
    
    func evaluate(placeholders: [String: Float]) -> Float {
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
    
    func evaluate(placeholders: [String: Float]) -> Float {
        if let v = placeholders[name] {
            return v
        }
        return 0.0
    }
    
    func simplify() -> EquationElement {
        return self
    }
}
