//
//  File.swift
//  
//
//  Created on 1/25/22.
//

import Foundation

class File {

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        close()
    }

    let fileURL: URL

    private var file: UnsafeMutablePointer<FILE>? = nil

    func open() throws {
        guard let f = fopen(fileURL.path, "r") else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        self.file = f
    }

    func close() {
        if let f = self.file {
            self.file = nil
            let success = fclose(f) == 0
            assert(success)
        }
    }

    func readLine(maxLength: Int = 4096) throws -> String? {
        guard let f = self.file else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EBADF), userInfo: nil)
        }
        var buffer = [CChar](repeating: 0, count: maxLength)
        guard fgets(&buffer, Int32(maxLength), f) != nil else {
            if feof(f) != 0 {
                return nil
            } else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            }
        }
        
        //Check that the line actually fit into the given buffer size
        let str = String(cString: buffer)
        var finishedLine = false
        if feof(f) != 0 {
            finishedLine = true
        } else {
            finishedLine = str.last == "\n"
        }
        
        if (!finishedLine) {
            throw SimpleErr("Encountered line longer than \(maxLength)")
        }
        return str
    }
    
    func readUntil(charIn: CharacterSet) throws -> String? {
        guard let f = self.file else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EBADF), userInfo: nil)
        }
        
        // Check that we haven't already reached the end or encountered a file error
        if feof(f) != 0 || ferror(f) != 0 {
            return nil
        }
        
        // Reserve a base "reasonable" size and rely on Swift's internal resizing logic for strings that exceed this
        let baseSize = 256
        var buffer = [CChar]()
        buffer.reserveCapacity(baseSize)
        while true {
            let c = fgetc(f)
            if (c == EOF) {
                // EOF could be the end of the file or a read error (check with feof() and ferror())
                // per man page
                if feof(f) != 0 {
                    // reached the end
                    break
                } else if ferror(f) != 0 {
                    // There's an error. Check errno
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
                } else {
                    // Not sure how or if this can happen
                    throw SimpleErr("An unknown error occurred during read")
                }
            } else if (c < 256) {
                let scalar = Unicode.Scalar(UInt8(c))
                if charIn.contains(scalar) {
                    break
                }
                buffer.append(CChar(c))
            } else {
                //Shouldn't happen. Documented to be unsigned char cast to int
                throw SimpleErr("Unexpected output of fgetc(): \(c)")
            }
        }
        
        // Always terminate
        buffer.append(0)
        let str = String(cString: buffer)
        return str
    }
}

