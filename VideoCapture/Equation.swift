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
    
    
    /// Somewhat counter-intuitive: The higher the precedence, the later the grouping.
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
    
    func evaluate(left: Double, _ right: Double) -> Double {
        switch self {
        case .ArithmeticAdd: return left + right
        case .ArithmeticDivide:
            if right != 0 {
                return left / right
            }
            return Double.infinity
        case .ArithmeticMultiply: return left * right
        case .ArithmeticSubtract: return left - right
        case .BooleanAnd: return left > 0.0 && right > 0.0 ? 1.0 : -1.0
        case .BooleanOr: return left > 0.0 || right > 0.0 ? 1.0 : -1.0
        case .CompareEqual: return left == right ? 1.0 : -1.0
        case .CompareGreaterThan: return left > right ? 1.0 : -1.0
        case .CompareGreaterThanOrEqual: return left >= right ? 1.0 : -1.0
        case .CompareLessThan: return left < right ? 1.0 : -1.0
        case .CompareLessThanOrEqual: return left <= right ? 1.0 : -1.0
        }
    }
}

protocol EquationElement: CustomStringConvertible {
    func evaluate(placeholders: [String: Double]) -> Double
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
    
    func evaluate(placeholders: [String: Double]) -> Double {
        // TODO: potentially add lazy evaluation
        let left = lhe.evaluate(placeholders)
        let right = rhe.evaluate(placeholders)
        return op.evaluate(left, right)
    }
}

class EquationNumber: EquationElement {
    let value: Double
    
    init(value: Double) {
        self.value = value
    }
    
    var description: String {
        get {
            return String(value)
        }
    }
    
    func evaluate(placeholders: [String: Double]) -> Double {
        return value
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
    
    func evaluate(placeholders: [String: Double]) -> Double {
        if let v = placeholders[name] {
            return v
        }
        return 0.0
    }
}

//enum EquationElement: CustomStringConvertible {
//    indirect case OperatorTriplet(lhe: EquationElement, op: EquationOperator, rhe: EquationElement)
//    case Numeric(val: Double)
//    case Placeholder(name: String)
//
//    func toString(placeholders: [String: String]) -> String {
//        switch self {
//        case .OperatorTriplet(let lhe, let op, let rhe):
//            return lhe.toString(placeholders) + op.description + rhe.toString(placeholders)
//        case .Numeric(let val):
//            return String(val)
//        case .Placeholder(let nm):
//            if let niceName = placeholders[nm] {
//                return niceName
//            }
//            return nm
//        }
//    }
//    
//    var description: String {
//        get {
//            switch self {
//            case .OperatorTriplet(let lhe, let op, let rhe):
//                return lhe.description + " " + op.description + " " + rhe.description
//            case .Numeric(let val):
//                return String(val)
//            case .Placeholder(let nm):
//                return nm
//            }
//        }
//    }
//}
