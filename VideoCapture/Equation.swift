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
    
    func getPrecedence() -> Int {
        switch self {
        case .BooleanAnd, .BooleanOr:
            return 10
        case .CompareEqual, .CompareGreaterThan, .CompareGreaterThanOrEqual, .CompareLessThan, .CompareLessThanOrEqual:
            return 20
        case .ArithmeticMultiply, .ArithmeticDivide:
            return 30
        case .ArithmeticAdd, .ArithmeticSubtract:
            return 40
        }
    }
}

enum EquationElement: CustomStringConvertible {
    indirect case OperatorTriplet(lhe: EquationElement, op: EquationOperator, rhe: EquationElement)
    case Numeric(val: Double)
    case Placeholder(name: String)
    
    init(lh: EquationElement, op: EquationOperator, rh: EquationElement) {
        self = .OperatorTriplet(lhe: lh, op: op, rhe: rh)
    }
    
    init(numeric: Double) {
        self = .Numeric(val: numeric)
    }
    
    init(placeholder: String) {
        self = .Placeholder(name: placeholder)
    }
    
    func toString(placeholders: [String: String]) -> String {
        switch self {
        case .OperatorTriplet(let lhe, let op, let rhe):
            return lhe.toString(placeholders) + op.description + rhe.toString(placeholders)
        case .Numeric(let val):
            return String(val)
        case .Placeholder(let nm):
            if let niceName = placeholders[nm] {
                return niceName
            }
            return nm
        }
    }
    
    var description: String {
        get {
            switch self {
            case .OperatorTriplet(let lhe, let op, let rhe):
                return lhe.description + " " + op.description + " " + rhe.description
            case .Numeric(let val):
                return String(val)
            case .Placeholder(let nm):
                return nm
            }
        }
    }
}