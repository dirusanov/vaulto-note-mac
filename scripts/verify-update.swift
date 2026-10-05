#!/usr/bin/env swift
import Foundation
import CryptoKit

// Verify release artifacts using only the app's public key, without Keychain
// access. Usage: swift scripts/verify-update.swift <app> <appcast.xml> <zip>
final class Feed: NSObject, XMLParserDelegate {
    var enclosure: [String: String]?
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        if elementName == "enclosure", enclosure == nil { enclosure = attributeDict }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Update verification failed: \(message)\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("usage: verify-update.swift <app> <appcast.xml> <zip>")
}
let app = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    let infoData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
    guard let encodedKey = info?["SUPublicEDKey"] as? String,
          let keyData = Data(base64Encoded: encodedKey) else { fail("missing public key") }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let feedData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    guard let marker = feedData.range(of: Data("<!-- sparkle-signatures:\n".utf8), options: .backwards),
          let footer = String(data: feedData[marker.lowerBound...], encoding: .utf8) else {
        fail("missing signed feed footer")
    }
    let fields = Dictionary(footer.components(separatedBy: "\n").compactMap { line -> (String, String)? in
        guard let split = line.range(of: ": ") else { return nil }
        return (String(line[..<split.lowerBound]), String(line[split.upperBound...]))
    }, uniquingKeysWith: { first, _ in first })
    guard let encodedSignature = fields["edSignature"],
          let signature = Data(base64Encoded: encodedSignature),
          let rawLength = fields["length"], let length = Int(rawLength),
          length == marker.lowerBound,
          key.isValidSignature(signature, for: feedData.prefix(length)) else {
        fail("invalid feed signature or signed length")
    }
    let feed = Feed()
    let parser = XMLParser(data: feedData)
    parser.delegate = feed
    guard parser.parse(), let enclosure = feed.enclosure,
          let archiveSignature = enclosure["sparkle:edSignature"],
          let signatureData = Data(base64Encoded: archiveSignature),
          let expectedLength = enclosure["length"].flatMap(Int.init) else { fail("invalid enclosure") }
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    guard expectedLength == archive.count, key.isValidSignature(signatureData, for: archive) else {
        fail("invalid ZIP signature or length")
    }
    print("Verified signed feed and ZIP against the app's public key.")
} catch { fail(error.localizedDescription) }
