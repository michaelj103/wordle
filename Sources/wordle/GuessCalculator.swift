//
//  GuessCalculator.swift
//  
//
//  Created on 1/27/22.
//

import Foundation
import Dispatch

fileprivate class GuessWorker {
    let wordlist: Wordlist
    let myGuesses: [String]
    let reportingRate: Int
    let progressCallback: (Int)->()
    init(_ w: Wordlist, guesses: [String], rate: Int, prog: @escaping (Int)->()) {
        wordlist = w
        myGuesses = guesses
        reportingRate = rate
        progressCallback = prog
    }
    
    func run(_ completion: ([String:Double])->()) {
        let possibleAnswers = wordlist.allWords
        var guessExpectation = [String: Double]()
        let denominator = Double(possibleAnswers.count)
        var completionCount = 0
        for answer in possibleAnswers {
            for guess in myGuesses {
                if guess == answer {
                    // special case for guessing correctly
                    // We eliminate everything so the reduction magnitude == possibleAnswers.count == denominator
                    // If we use the reducedWords function, it reduces to only the answer which doesn't account
                    // for the fact that we got it and don't have to guess again
                    guessExpectation[guess,default: 0.0] += 1.0
                    continue
                }
                
                let response = WordRules.responseForGuess(guess, answer: answer)
                if let reducedWords = try? wordlist.reducedWords(guess, rules: response), !reducedWords.isEmpty {
                    // Weight the magnitude of the reduction by the probability that this is the answer
                    // Assume all answers are equally likely
                    let reductionMagnitude = possibleAnswers.count - reducedWords.count
                    let reductionWeighted = Double(reductionMagnitude) / denominator
                    guessExpectation[guess,default:0.0] += reductionWeighted
                } else {
                    print("Unexpected empty result for guess \"\(guess)\", answer \"\(answer)\"")
                    preconditionFailure()
                }
            }
            completionCount += 1
            if completionCount == reportingRate {
                progressCallback(completionCount)
                completionCount = 0
            }
        }
        
        // report final progress if we didn't already
        if completionCount > 0 {
            progressCallback(completionCount)
        }
        
        completion(guessExpectation)
    }
}

class GuessCalculator {
    let wordlist: Wordlist
    let guesses: [String]
    private let answerQueue: DispatchQueue
    init(_ wordlist: Wordlist, guesses: [String]) {
        self.wordlist = wordlist
        self.guesses = guesses
        answerQueue = DispatchQueue(label: "GuessConsolidation", qos: .userInitiated)
    }
        
    private var expectedReductionByGuess = [String:Double]()
    private var totalProgress = 0
    
    private func _workerCompletion(_ reductionSubset: [String:Double], id: Int) {
        answerQueue.async {
            for (guess, reduction) in reductionSubset {
                self.expectedReductionByGuess[guess] = reduction
            }
        }
    }
    
    func run(progress: @escaping (Int)->(), completion: @escaping ([String:Double])->()) {
        let workerCount = 4
        let numGuesses = guesses.count
        let baseWorkload = numGuesses / 4
        let workloadRemainder = numGuesses % 4
        var position = 0
        let reportingRate = [2, 3, 5, 7]
        
        let group = DispatchGroup()
        
        func clientProgress(_ x: Int) {
            answerQueue.async {
                self.totalProgress += x
                progress(self.totalProgress / workerCount)
            }
        }
        
        for i in 0..<workerCount {
            // get the work for the worker
            let workload = baseWorkload + (i < workloadRemainder ? 1 : 0)
            let end = min(position + workload, guesses.count)
            let slice = guesses[position..<end]
            let workerGuesses = Array<String>(slice)
            position = end
            
            group.enter()
            // kick off the worker thread
            let worker = GuessWorker(wordlist, guesses: workerGuesses, rate: reportingRate[i], prog: clientProgress)
            let workQueue = DispatchQueue(label: "GuessWorker\(i)", qos: .userInitiated)
            workQueue.async {
                worker.run { self._workerCompletion($0, id: i) }
                group.leave()
            }
        }
        
        // when all the workers are done, notify completion
        group.notify(queue: answerQueue) {
            if #available(macOS 10.12, *) {
                dispatchPrecondition(condition: .onQueue(self.answerQueue))
            }
            completion(self.expectedReductionByGuess)
        }
    }
    
    func run(completion: @escaping ([String:Double])->()) {
        func emptyProgressHandler(_: Int) {}
        run(progress: emptyProgressHandler, completion: completion)
    }
}
