import ArgumentParser
import Foundation

struct WordleTool: ParsableCommand {
    @Option(name: .shortAndLong, help: "Wordlist. One word per line. Lowercase letters") var wordlist: String
    @Option(name: .shortAndLong, help: "Wordlist of \"reasonable\" words. One per line. Lowercase letters") var reasonable: String?
    @Option(name: .shortAndLong, help: "Best guess cutoff. Will suggest a best guess when reduced below this count if supplied") var cutoff: Int?
    @Flag(name: .shortAndLong, help: "Assume the word is in the reasonable wordlist") var simplified: Bool = false
    @Flag(help: "Run in optimize mode to find the best initial guess") var optimize: Bool = false
    
    func validate() throws {
        if let c = cutoff, c <= 0 {
            throw ValidationError("Cutoff must be a positive integer")
        }
        
        if simplified && (reasonable == nil) {
            throw ValidationError("Can only use the simplified heuristic if a reasonable wordlist is supplied")
        }
    }
    
    private func getInput() throws -> (String, [LetterRule]) {
        print("Next guess: ")
        guard let guess = readLine() else {
            throw SimpleErr("Expected a guess")
        }
        guard Wordlist.wordIsValid(guess) else {
            throw SimpleErr("Invalid guess")
        }
        
        print("Result: ")
        guard let result = readLine() else {
            throw SimpleErr("Expected a result")
        }
        let rules = try Wordlist.rulesFromString(result)
        return (guess, rules)
    }
    
    private func _printBestGuess(_ scoreByGuess: [String:Double], allWords: [String]) {
        let sorted = allWords.sorted { scoreByGuess[$0,default: 0.0] > scoreByGuess[$1,default: 0.0] }
        let best = sorted.prefix(5)
        print("Recommended guesses: ")
        for b in best {
            print("\(b):\(scoreByGuess[b,default:0.0])",terminator: ", ")
        }
        print("")
    }
    
    private func _runInteractiveGuessInternal(_ allWords: [String], wordlist: Wordlist) throws {
        let (word, result) = try getInput()
        let reduced = try wordlist.reducedWords(word, rules: result)
        let remainingCount = reduced.count
        let currentWordlist = Wordlist(reduced)
        print("Reduced to \(remainingCount) remaining words")
        if remainingCount <= 10 {
            print("Remaining word(s):")
            for word in reduced {
                print(word)
            }
        }
        if remainingCount <= 1 {
            // end game
            WordleTool.exit(withError: nil)
        } else if let c = cutoff, remainingCount <= c && remainingCount > 2 {
            // there's best guess cutoff and we meet it. Run async computation
            print("Computing recommendation...")
            let calculator = GuessCalculator(currentWordlist, guesses: allWords)
            calculator.run { numComplete in
                DispatchQueue.main.async {
                    fputs("\r\(numComplete)/\(currentWordlist.allWords.count)", stderr)
                    fflush(stderr)
                }
            } completion: { scoreByGuess in
                DispatchQueue.main.async {
                    fputs("\n", stderr)
                    _printBestGuess(scoreByGuess, allWords: allWords)
                    _runInteractiveGuess(allWords, wordlist: currentWordlist)
                }
            }
        } else {
            // no async work to do. Just dispatch the next guess
            DispatchQueue.main.async {
                _runInteractiveGuess(allWords, wordlist: currentWordlist)
            }
        }
    }
    
    private func _runInteractiveGuess(_ allWords: [String], wordlist: Wordlist) {
        do {
            try _runInteractiveGuessInternal(allWords, wordlist: wordlist)
        } catch let e as SimpleErr {
            print("Error: \(e.description)")
        } catch {
            print("Error: \(error)")
        }
    }
    
    private func runInteractive(_ allWords: Set<String>, reasonable: Set<String>?) {
        // validation should require that simplified may only be true when reasonable is non-nil
        let wordlist = simplified ? Wordlist(reasonable!) : Wordlist(allWords)
        print("Running with \(wordlist.allWords.count) possible words and \(allWords.count) valid guesses")
        let allWordsArray = Array<String>(allWords)
        
        DispatchQueue.main.async {
            _runInteractiveGuess(allWordsArray, wordlist: wordlist)
        }
        
        dispatchMain()
    }
    
    private func runInteractiveOld(_ allWords: Set<String>, reasonable: Set<String>?) {
        // validation should require that simplified may only be true when reasonable is non-nil
        let wordlist = simplified ? Wordlist(reasonable!) : Wordlist(allWords)
        print("Running with \(wordlist.allWords.count) possible words and \(allWords.count) valid guesses")
        let allWordsArray = Array<String>(allWords)

        var currentWordlist = wordlist
        while true {
            do {
                let (word, result) = try getInput()
                let reduced = try currentWordlist.reducedWords(word, rules: result)
                let remainingCount = reduced.count
                currentWordlist = Wordlist(reduced)
                print("Reduced to \(remainingCount) remaining words")
                if remainingCount <= 10 {
                    print("Remaining word(s):")
                    for word in reduced {
                        print(word)
                    }
                }
                if remainingCount <= 1 {
                    break
                }

                if let c = cutoff, remainingCount <= c && remainingCount > 2 {
                    print("Computing recommendation...")
                    let best = currentWordlist.bestGuesses(allWordsArray, reasonable: reasonable, showProgress: true)
                    print("Recommended guesses: \(best)")
                }
            } catch {
                print("Error: \(error)")
            }
        }
    }
    
    private func _bestGuessOutput(_ scoreByGuess: [String:Double], allWords: [String]) {
        let sorted = allWords.sorted { scoreByGuess[$0,default: Double.infinity] > scoreByGuess[$1,default: Double.infinity] }
        for (idx, word) in sorted.enumerated() {
            print("\(idx+1). \(word): \(scoreByGuess[word, default: Double.infinity])")
        }
    }
    
    private func runBestGuess(_ allWords: Set<String>, reasonable: Set<String>?) {
        // validation should require that simplified may only be true when reasonable is non-nil
        let wordlist = simplified ? Wordlist(reasonable!) : Wordlist(allWords)
        print("Running with \(wordlist.allWords.count) possible words and \(allWords.count) valid guesses")
        let wordArray = Array<String>(allWords)
        
        // method 1
//        wordlist.printBestGuessList(wordArray, reasonable: reasonable)
        
        // method 2
        let calculator = GuessCalculator(wordlist, guesses: wordArray)
        calculator.run { numComplete in
            DispatchQueue.main.async {
                fputs("\r\(numComplete)/\(wordlist.allWords.count)", stderr)
                fflush(stderr)
            }
        } completion: { finalScoreByGuesses in
            DispatchQueue.main.async {
                fputs("\n", stderr)
                _bestGuessOutput(finalScoreByGuesses, allWords: wordArray)
                WordleTool.exit(withError: nil)
            }
        }
        dispatchMain()
    }
    
    private func _readValidWords(_ file: File) throws -> Set<String> {
        var words = Set<String>()
        while let line = try file.readLine() {
            let word: String
            if line.hasSuffix("\n") {
                word = String(line.dropLast(1))
            } else {
                word = line
            }
            
            if Wordlist.wordIsValid(word) {
                words.insert(word)
            }
        }
        return words
    }
    
    func run() throws {
        let file = File(fileURL: URL(fileURLWithPath: wordlist))
        try file.open()
        var completeWords = try _readValidWords(file)
        
        let reasonableWords: Set<String>?
        if let reasonablePath = reasonable {
            let reasonableFile = File(fileURL: URL(fileURLWithPath: reasonablePath))
            try reasonableFile.open()
            reasonableWords = try _readValidWords(reasonableFile)
        } else {
            reasonableWords = nil
        }
        
        // all the reasonable words should be in the complete wordlist
        if let rWords = reasonableWords {
            let countBefore = completeWords.count
            completeWords.formUnion(rWords)
            if completeWords.count > countBefore {
                // it won't affect anything, but you should look into the data
                print("Warning: \(completeWords.count - countBefore) word(s) in reasonable wordlist not in wordlist")
            }
        }
        
        if optimize {
            runBestGuess(completeWords, reasonable: reasonableWords)
        } else {
            runInteractive(completeWords, reasonable: reasonableWords)
        }
    }
}

WordleTool.main()
