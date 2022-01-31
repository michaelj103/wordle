//
//  ExpectedTurnCalculator.swift
//  
//
//  Created on 1/30/22.
//

import Foundation

class ExpectedTurnCalculator {
    
    private func expectedTurns(_ validGuesses: [String], wordlist: Wordlist, minKnownTurns: Double) -> (String, Double) {
        if minKnownTurns <= 1.0 {
            // cutoff. anything we do will be worse than the known best answer
            return ("", Double(wordlist.allWords.count))
        } else if wordlist.allWords.count == 1 {
            let expectedTurns = 1.0
            let bestGuess = wordlist.allWords.first!
            return (bestGuess, expectedTurns)
        } else if wordlist.allWords.count == 2 {
            let expectedTurns = 1.5
            let bestGuess = wordlist.allWords.first!
            return (bestGuess, expectedTurns)
        }
        
        var bestExpectedTurns = minKnownTurns
        var bestWord = ""
        let guessCalc = GuessCalculator(wordlist, guesses: validGuesses)
        let scoreByGuess = guessCalc.runSync()
        let recommendation = validGuesses.reduce("") { best, next in
            let bestScore = scoreByGuess[best,default: 0.0]
            let nextScore = scoreByGuess[next,default: 0.0]
            return bestScore >= nextScore ? best : next
        }
        precondition(!recommendation.isEmpty, "Empty recommendation?")
        
        let recommendationExpected = expectedTurnsForGuess(recommendation, validGuesses: validGuesses, wordlist: wordlist, minKnownTurns: minKnownTurns)
        if recommendationExpected < bestExpectedTurns {
            bestExpectedTurns = recommendationExpected
            bestWord = recommendation
        }
        
        // using the recommendation as a reasonable bound for cutting off branches, try everything else and see if something is better
        for guess in validGuesses {
            if guess == recommendation {
                continue
            }
            
            let expectedBelow = expectedTurnsForGuess(guess, validGuesses: validGuesses, wordlist: wordlist, minKnownTurns: bestExpectedTurns)
            if expectedBelow < bestExpectedTurns {
                bestExpectedTurns = expectedBelow
                bestWord = guess
            }
        }
        
        return (bestWord, bestExpectedTurns)
    }
    
    private func expectedTurnsForGuess(_ guess: String, validGuesses: [String], wordlist: Wordlist, minKnownTurns: Double) -> Double {
        // TODO: do we need base cases here or is it a safe assumption that the caller is passing in reasonable data?
        
        let answers = wordlist.allWords
        var totalExpectedTurns = 0.0
        for answer in answers {
            if answer == guess {
                continue
            }
            let response = Wordlist.responseForGuess(guess, answer: answer)
            if let reducedWords = try? wordlist.reducedWords(guess, rules: response), !reducedWords.isEmpty {
                let reducedList = Wordlist(reducedWords)
                let (_, expectedBelow) = expectedTurns(validGuesses, wordlist: reducedList, minKnownTurns: minKnownTurns - 1.0)
                totalExpectedTurns += expectedBelow
            } else {
                print("Unexpected empty reduced set for guess \"\(guess)\", answer \"\(answer)\"")
                preconditionFailure()
            }
        }
        
        let finalExpectedTurns = (totalExpectedTurns / Double(answers.count)) + 1.0
        let bestAnswer = min(finalExpectedTurns, minKnownTurns)
        return bestAnswer
    }
    
    func findExpectedTurnsForFirstGuess(_ guess: String, validGuesses: Set<String>, wordlist: Wordlist) -> Double {
        precondition(wordlist.allWords.count > 2, "Word list is too small")
        precondition(validGuesses.contains(guess), "Guess is not in valid list")
        let guessArray = Array<String>(validGuesses)
        let worstCase = Double(wordlist.allWords.count)
        let expected = expectedTurnsForGuess(guess, validGuesses: guessArray, wordlist: wordlist, minKnownTurns: worstCase)
        return expected
    }
}
