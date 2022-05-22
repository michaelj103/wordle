//
//  WordRules.swift
//  
//
//  Created by Michael Brandt on 5/21/22.
//

import Foundation

enum LetterRule: Int {
    case Absent = 0
    case Present = 1
    case Correct = 2
}

struct WordRules {
    
    static func wordIsValid(_ word: String) -> Bool {
        if word.count != 5 {
            return false
        }
        
        for c in word {
            if c.isASCII {
                let value = c.asciiValue!
                if value < Character("a").asciiValue! || value > Character("z").asciiValue! {
                    return false
                }
            } else {
                return false
            }
        }
        
        return true
    }
    
    static func rulesFromString(_ string: String) throws -> [LetterRule] {
        guard string.count == 5 else {
            throw SimpleErr("Invalid response length")
        }
        var rules = [LetterRule]()
        rules.reserveCapacity(5)
        for c in string {
            switch c {
            case "0":
                rules.append(.Absent)
            case "1":
                rules.append(.Present)
            case "2":
                rules.append(.Correct)
            default:
                throw SimpleErr("Invalid rule character \"\(c)\"")
            }
        }
        return rules
    }
    
    static func responseForGuess(_ guess: String, answer: String) -> [LetterRule] {
        precondition(guess.count == 5 && answer.count == 5)
        var rules = [LetterRule](repeating: .Absent, count: 5)
        var letterCounts = [Character:Int]()
        for (idx, ch) in guess.enumerated() {
            let answerCh = answer[answer.index(answer.startIndex, offsetBy: idx)]
            if ch == answerCh {
                rules[idx] = .Correct
            } else {
                letterCounts[answerCh,default:0] += 1
            }
        }
        for (idx, ch) in guess.enumerated() {
            let remainingCountOfCh = letterCounts[ch,default:0]
            if remainingCountOfCh > 0 && rules[idx] == .Absent {
                rules[idx] = .Present
                letterCounts[ch] = remainingCountOfCh - 1
            }
        }
        return rules
    }
}
