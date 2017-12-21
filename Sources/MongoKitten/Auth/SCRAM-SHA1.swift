//
// This source file is part of the MongoKitten open source project
//
// Copyright (c) 2016 - 2017 OpenKitten and the MongoKitten project authors
// Licensed under MIT
//
// See https://github.com/OpenKitten/MongoKitten/blob/mongokitten31/LICENSE.md for license information
// See https://github.com/OpenKitten/MongoKitten/blob/mongokitten31/CONTRIBUTORS.md for the list of MongoKitten project authors
//

import Foundation
import Crypto

/// Authenticates over SCRAM-SHA-1 to authenticate a user with the provided password
final class SCRAMContext {
    /// Constant GS2BindFlag
    let gs2BindFlag = "n,,"
    
    /// Caches the password hash for this server's authentication details
    var cachedLoginData: (password: Data, clientKey: Data, serverKey: Data)? = nil
    
    init() {}
    
    /// Fixes the username to not contain variables that are essential to the SCRAM message structure
    ///
    /// - returns: The fixed username
    private func fixUsername(username user: String) -> String {
        return user.replacingOccurrences(of: "=", with: "=3D").replacingOccurrences(of: ",", with: "=2C")
    }
    
    /// Parses the SCRAM challenge and returns the values in there as a tuple
    ///
    /// - returns: The values in there as a tuple
    /// - throws: Unable to parse this message to a sever signature
    private func parse(challenge response: String) throws -> (nonce: String, salt: String, iterations: Int) {
        var nonce: String? = nil
        var iterations: Int? = nil
        var salt: String? = nil
        
        for part in response.split(separator: ",") where String(part).count >= 3 {
            let part = String(part)
            
            if let first = part.first {
                let data = part[part.index(part.startIndex, offsetBy: 2)..<part.endIndex]
                
                switch first {
                case "r":
                    nonce = String(data)
                case "i":
                    iterations = Int(String(data))
                case "s":
                    salt = String(data)
                default:
                    break
                }
            }
        }
        
        if let nonce = nonce, let iterations = iterations, let salt = salt {
            return (nonce: nonce, salt: salt, iterations: iterations)
        }
        
        throw AuthenticationError.challengeParseError(challenge: response)
    }
    
    /// Parses the final response and returns the server signature
    ///
    /// - returns: The server signature
    /// - throws: Unable to parse this message to a sever signature
    private func parse(finalResponse response: String) throws -> [UInt8] {
        var signature: [UInt8]? = nil
        
        for part in response.split(separator: ",") where String(part).count >= 3 {
            let part = String(part)
            
            if let first = part.first {
                let data = part[part.index(part.startIndex, offsetBy: 2)..<part.endIndex]
                
                switch first {
                case "v":
                    signature = Array(try Base64Decoder().decode(string: String(data)))
                default:
                    break
                }
            }
        }
        
        if let signature = signature {
            return signature
        }
        
        throw AuthenticationError.responseParseError(response: response)
    }
    
    /// Generates an initial SCRAM-SHA-1 authentication String
    func authenticate(_ username: String, usingNonce nonce: String) -> String {
        return "\(gs2BindFlag)n=\(fixUsername(username: username)),r=\(nonce)"
    }
    
    /// Processes the challenge and responds with the proof that we are the user we claim to be
    ///
    /// - returns: A tuple where the proof is to be sent to the server and the signature is to be verified in the server's responses.
    /// - throws: When unable to parse the challenge
    func process(_ challenge: String, username: String, password: Data, usingNonce nonce: String) throws -> (proof: String, serverSignature: Data) {
        func xor(_ lhs: Data, _ rhs: Data) -> Data {
            var result = Data(repeating: 0, count: min(lhs.count, rhs.count))
            
            for i in 0..<result.count {
                result[i] = lhs[i] ^ rhs[i]
            }
            
            return result
        }
        
        let encodedHeader = Base64Encoder().encode(string: gs2BindFlag)
        
        let parsedResponse = try parse(challenge: challenge)

        let remoteNonce = parsedResponse.nonce
        let endIndex = remoteNonce.index(remoteNonce.startIndex, offsetBy: 24)
        
        guard remoteNonce.endIndex >= endIndex, String(remoteNonce[remoteNonce.startIndex..<endIndex]) == nonce else {
            throw AuthenticationError.invalidNonce(nonce: parsedResponse.nonce)
        }
        
        let noProof = "c=\(encodedHeader),r=\(parsedResponse.nonce)"
        
        let salt = try Base64Decoder().decode(string: parsedResponse.salt)
        let saltedPassword: Data
        let clientKey: Data
        let serverKey: Data
        
        if let cachedLoginData = cachedLoginData {
            saltedPassword = cachedLoginData.password
            clientKey = cachedLoginData.clientKey
            serverKey = cachedLoginData.serverKey
        } else {
            saltedPassword = try PBKDF2<SHA1>.deriveKey(fromPassword: password, saltedWith: salt, iterating: parsedResponse.iterations, derivedKeyLength: SHA1.digestSize)
            
            let ck = Data("Client Key".utf8)
            let sk = Data("Server Key".utf8)
                
            clientKey = HMAC<SHA1>.authenticate(ck, withKey: saltedPassword)
            serverKey = HMAC<SHA1>.authenticate(sk, withKey: saltedPassword)
            
            cachedLoginData = (saltedPassword, clientKey, serverKey)
        }
        
        let storedKey = SHA1.hash(clientKey)

        let authenticationMessage = "n=\(fixUsername(username: username)),r=\(nonce),\(challenge),\(noProof)"

        let authenticationMessageBytes = Data(authenticationMessage.utf8)
        
        let clientSignature = HMAC<SHA1>.authenticate(authenticationMessageBytes, withKey: storedKey)
        let clientProof = xor(clientKey, clientSignature)
        let serverSignature = HMAC<SHA1>.authenticate(authenticationMessageBytes, withKey: serverKey)
        
        let proof = String(data: Base64Encoder().encode(data: clientProof), encoding: .utf8)!
        
        return (proof: "\(noProof),p=\(proof)", serverSignature: serverSignature)
    }
    
    /// Validates the server's signature
    ///
    /// - returns: An empty string to proceed the process indefinitely until complete as per protocol definition
    /// - throws: When the server's signature is invalid
    func complete(fromResponse response: String, verifying signature: [UInt8]) throws -> String {
        let sig = try parse(finalResponse: response)

        if sig != signature {
            throw AuthenticationError.serverSignatureInvalid
        }
        
        return ""
    }
}
