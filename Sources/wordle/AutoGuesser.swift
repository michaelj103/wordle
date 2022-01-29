//
//  AutoGuesser.swift
//  
//
//  Created on 1/28/22.
//

import Foundation

// work item for the auto guesser queue
fileprivate struct GuessItem {
    let word: String
    let answer: String
    let guesses: Int
    let pathWeight: Double
    let wordlist: Wordlist
}

class AutoGuesser {
    let firstWord: String
    let answers: [String]
    let allWords: [String]
    let targetAnswers: [String]
    
    init(firstWord: String, answers: Set<String>, targetAnswers: [String]? = nil, allWords: Set<String>) throws {
        self.firstWord = firstWord
        self.answers = Array<String>(answers)
        if let tAnswers = targetAnswers {
            self.targetAnswers = tAnswers
            for ans in tAnswers {
                if !answers.contains(ans) {
                    throw SimpleErr("Target answer \"\(ans)\" is not in the set of possible answers")
                }
            }
        } else {
            self.targetAnswers = self.answers
        }
        self.allWords = Array<String>(allWords)
    }
    
    private var completionHandler: (()->())?
    func run(targetAnswers: [String]? = nil, completion: @escaping ()->()) {
        completionHandler = completion
        _processNextAnswer()
    }

    private var expectedTurnsByAnswer = [String:Double]()
    private var processingQueue = [GuessItem]()
    private var lastProcessedAnswer: Int?
    private func _processNextAnswer() {
        let nextAnswerIndex: Int = (lastProcessedAnswer ?? -1) + 1
        lastProcessedAnswer = nextAnswerIndex
        // print progress
        if nextAnswerIndex > 0 {
            let ans = targetAnswers[nextAnswerIndex-1]
            print("\(ans): \(expectedTurnsByAnswer[ans]!)")
        }
//        fputs("\r\(nextAnswerIndex)/\(targetAnswers.count)", stderr)
//        fflush(stderr)
        if nextAnswerIndex >= targetAnswers.count {
            // Done! Consolidate output
//            fputs("\n", stderr)
            print("Done")
            completionHandler?()
            return
        }
        
        let answer = targetAnswers[nextAnswerIndex]
        let wordlist = Wordlist(answers)
        let guess = GuessItem(word: firstWord, answer: answer, guesses: 0, pathWeight: 1.0, wordlist: wordlist)
        processingQueue.append(guess)
        _processQueue()
    }
    
    // run the next item in the queue
    private func _processQueue() {
        if processingQueue.isEmpty {
            DispatchQueue.main.async {
                self._processNextAnswer()
            }
            return
        }
        
        let nextGuess = processingQueue.removeFirst()
        if nextGuess.word == nextGuess.answer {
            // got the answer, done with this branch
            let totalTurns = nextGuess.guesses + 1
            expectedTurnsByAnswer[nextGuess.answer,default: 0.0] += Double(totalTurns) * nextGuess.pathWeight
            DispatchQueue.main.async {
                self._processQueue()
            }
        } else {
            let currentWord = nextGuess.word
            
            // the next guess isn't correct. Figure out how it narrows the field and compute best follow-up guess(es)
            let response = Wordlist.responseForGuess(currentWord, answer: nextGuess.answer)
            if let reducedWords = try? nextGuess.wordlist.reducedWords(currentWord, rules: response), !reducedWords.isEmpty {
                let reducedWordlist = Wordlist(reducedWords)
                if reducedWords.count <= 2 {
                    // for 1 or 2 remaining words, all should be attempted and weighted equally
                    DispatchQueue.main.async {
                        self._enqueueEqualGuesses(reducedWords, guessCount: reducedWords.count, previousGuess: nextGuess, reducedWordlist: reducedWordlist)
                        self._processQueue()
                    }
                } else {
                    let calculator = GuessCalculator(reducedWordlist, guesses: self.allWords)
                    calculator.run { scoreByGuess in
                        let bestGuesses = self._bestGuesses(scoreByGuess)
                        DispatchQueue.main.async {
                            self._enqueueEqualGuesses(bestGuesses, guessCount: bestGuesses.count, previousGuess: nextGuess, reducedWordlist: reducedWordlist)
                            self._processQueue()
                        }
                    }
                }
                
            } else {
                print("Unexpected empty result for guess \"\(nextGuess.word)\", answer \"\(nextGuess.answer)\"")
                preconditionFailure()
            }
        }
    }
    
    private func _enqueueEqualGuesses<S: Sequence>(_ guesses: S, guessCount: Int, previousGuess: GuessItem, reducedWordlist: Wordlist) where S.Element == String {
        let answer = previousGuess.answer
        let nextGuessCount = previousGuess.guesses + 1
        let updatedWeight = previousGuess.pathWeight / Double(guessCount)
        for word in guesses {
            let guessItem = GuessItem(word: word, answer: answer, guesses: nextGuessCount, pathWeight: updatedWeight, wordlist: reducedWordlist)
            processingQueue.append(guessItem)
        }
    }
    
    private func _bestGuesses(_ scoreByGuess: [String:Double]) -> [String] {
        let sorted = allWords.sorted { scoreByGuess[$0,default: Double.infinity] > scoreByGuess[$1,default: Double.infinity] }
        let topScore = scoreByGuess[sorted[0], default: Double.infinity]
        precondition(topScore <= Double(scoreByGuess.count), "Top score is too high")
        
        let bestWords = sorted.prefix { str in
            let score = scoreByGuess[str,default: 0.0]
            // account for some floating point inaccuracy. Unlikely though. Could also score using fractions
            return (score + 0.000001) >= topScore
        }
        
        return Array<String>(bestWords)
    }
}
