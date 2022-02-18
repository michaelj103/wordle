//
//  Wordlist.swift
//  
//
//  Created on 1/25/22.
//

import Foundation

fileprivate struct RuleCounts {
    let absent: Int
    let present: Int
    let correct: Int

    func countRange() -> (Int,Int) {
        let min = present + correct
        let max = absent > 0 ? min : 5
        return (min, max)
    }
}

enum LetterRule: Int {    
    case Absent = 0
    case Present = 1
    case Correct = 2
}

struct Wordlist {
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
    
    // indexed by asciiValue - 'a'
    private let wordsByLetter: [Set<String>]
    let allWords: Set<String>
    
    init<S: Sequence>(_ words: S) where S.Element == String {
        allWords = Set<String>(words)
        var _wordsByLetter = [Set<String>](repeating: Set<String>(), count: 26)
        for word in words {
            for c in word {
                let value = Int(c.asciiValue!) - Int(Character("a").asciiValue!)
                precondition(value >= 0 && value < 26)
                _wordsByLetter[value].insert(word)
            }
        }
        wordsByLetter = _wordsByLetter
    }
    
    private func _wordsForLetter(_ ch: Character) -> Set<String> {
        let value = Int(ch.asciiValue!) - Int(Character("a").asciiValue!)
        precondition(value >= 0 && value < 26)
        return wordsByLetter[value]
    }
    
    private func _isCountInRange(_ string: String, letter: Character, min: Int, max: Int) -> Bool {
        var count = 0
        for ch in string {
            if ch == letter {
                count += 1
                if count > max {
                    return false
                }
            }
        }
        return count >= min
    }
    
    func reducedWords(_ string: String, rules: [LetterRule]) throws -> Set<String> {
        precondition(string.count == rules.count && string.count == 5)
        
        // get the rules by letter
        var countsByLetter = [Character:RuleCounts]()
        var requiredLetters = [Character?](repeating: nil, count: 5)
        var elsewhereLetters = [Set<Character>](repeating: [], count: 5)
        for (idx, ch) in string.enumerated() {
            let rule = rules[idx]
            let existingCounts = countsByLetter[ch, default: RuleCounts(absent: 0, present: 0, correct: 0)]
            let updatedCounts: RuleCounts
            switch rule {
            case .Absent:
                if existingCounts.present > 0 {
                    // if a letter was marked present and later in the word as absent, that means it's excluded from the absent space
                    elsewhereLetters[idx].insert(ch)
                }
                updatedCounts = RuleCounts(absent: existingCounts.absent + 1, present: existingCounts.present, correct: existingCounts.correct)
            case .Present:
                if existingCounts.absent > 0 {
                    // If a letter is marked absent and later present, this is an error. If there are too many in the guessed word,
                    // then the first should be marked present and the later ones absent. Exception is if a later one is in correct position
                    // We don't care about this relationship with correct and absent
                    throw SimpleErr("letter \"\(ch)\" was marked absent before present, which is invalid")
                }
                elsewhereLetters[idx].insert(ch)
                updatedCounts = RuleCounts(absent: existingCounts.absent, present: existingCounts.present + 1, correct: existingCounts.correct)
            case .Correct:
                requiredLetters[idx] = ch
                updatedCounts = RuleCounts(absent: existingCounts.absent, present: existingCounts.present, correct: existingCounts.correct + 1)
            }
            
            countsByLetter[ch] = updatedCounts
        }
        
        var currentWords = allWords
        // first eliminate all words with rejected letters
        // and eliminate all words missing required letters
        for (ch, counts) in countsByLetter {
            let (min, max) = counts.countRange()
            if max == 0 {
                // letter is rejected
                let wordsWithLetter = _wordsForLetter(ch)
                currentWords.subtract(wordsWithLetter)
            } else if min >= 1 {
                // letter is required
                let wordsWithLetter = _wordsForLetter(ch)
                currentWords.formIntersection(wordsWithLetter)
            }
        }
                
        // Now ensure required letters in the right places
        var rejectedWords = Set<String>()
        for word in currentWords {
            for (idx, ch) in word.enumerated() {
                if let requiredLetter = requiredLetters[idx], ch != requiredLetter {
                    // the letter in this position has to be something else
                    rejectedWords.insert(word)
                    break
                }
                if elsewhereLetters[idx].contains(ch) {
                    // the letter in this position is present, but isn't correct here
                    rejectedWords.insert(word)
                    break
                }
            }
        }
        currentWords.subtract(rejectedWords)
        
        // Last, if there are any reduced count requirements for letters, apply them
        var rejectedWords2 = Set<String>()
        for (ch, counts) in countsByLetter {
            let (min, max) = counts.countRange()
            if min > 1 || max < 5 {
                // we have an interesting range
                for word in currentWords {
                    if !_isCountInRange(word, letter: ch, min: min, max: max) {
                        rejectedWords2.insert(word)
                    }
                }
            }
        }
        currentWords.subtract(rejectedWords2)
        
        return currentWords
    }
    
    private func _rulesForNum(_ x: Int) -> [LetterRule] {
        var rules = [LetterRule](repeating: .Absent, count: 5)
        var val = x
        for i in (0..<5).reversed() {
            let digit = val % 3
            val = val / 3
            rules[i] = LetterRule(rawValue: digit)!
        }
        return rules
    }
}
