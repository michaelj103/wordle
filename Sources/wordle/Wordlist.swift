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
            if min > 0 || max < 5 {
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
    
    // Note that the best guess may be a word that's already been eliminated
    // So, work with an input list of available words rather than the allWords property
    private func _bestGuess(_ available: [String], reasonable: Set<String>?, showProgress: Bool = false) -> ([String], [String:Double]) {
        let reasonableWeight = 3.0
        let denominator: Double
        if let reasonableSet = reasonable {
            let reasonableCount = allWords.intersection(reasonableSet).count
            let unreasonableCount = allWords.count - reasonableCount
            denominator = Double(unreasonableCount) + (Double(reasonableCount) * reasonableWeight)
        } else {
            denominator = Double(allWords.count)
        }
        var scoreByWord = [String:Double]()
        for word in available {
            // all possible responses are 5-digit ternary numbers
            // so there are 243 possible responses 0-242.
            // Some of those responses may be invalid, e.g. marking a letter as absent then later present
            // Those will throw but we want to just skip them so use try?
            var expectedReductionMagnitude = 0.0
            for i in 0..<243 {
                let rules = _rulesForNum(i)
                // Note that empty means that the response is not possible, so skip it
                if let words = try? reducedWords(word, rules: rules), !words.isEmpty {
                    let reasonableCount: Int
                    if let reasonableSet = reasonable {
                        reasonableCount = words.intersection(reasonableSet).count
                    } else {
                        reasonableCount = 0
                    }
                    
                    let reducedReasonableCount = Double(reasonableCount)
                    let reducedUnreasonableCount = Double(words.count - reasonableCount)
                    let reductionMagnitude = Double(allWords.count - words.count)
                    let probability = (reducedUnreasonableCount + (reducedReasonableCount * reasonableWeight)) / denominator
                    let expectation = reductionMagnitude * probability
                    expectedReductionMagnitude += expectation
                }
            }
            
            scoreByWord[word] = expectedReductionMagnitude
            if showProgress {
                fputs("\r\(scoreByWord.count)/\(available.count)", stderr)
                fflush(stderr)
            }
        }
        
        let sorted = available.sorted { scoreByWord[$0,default: Double.infinity] > scoreByWord[$1,default: Double.infinity] }
        
        if showProgress {
            fputs("\n", stderr)
        }
        return (sorted, scoreByWord)
    }
    
    func printBestGuessList(_ available: [String], reasonable: Set<String>?) {
        let (sorted, scoreByWord) = _bestGuess(available, reasonable: reasonable, showProgress: true)
        for (idx, word) in sorted.enumerated() {
            print("\(idx+1). \(word): \(scoreByWord[word, default: Double.infinity])")
        }
    }
    
    func bestGuesses(_ available: [String], reasonable: Set<String>?, showProgress: Bool = false) -> [String] {
        precondition(available.count >= 1)
        let (sorted, _) = _bestGuess(available, reasonable: reasonable, showProgress: showProgress)
        return Array<String>(sorted.prefix(upTo: 5))
    }
}
