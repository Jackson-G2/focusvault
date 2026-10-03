import Darwin
import Foundation
import VaultyCore

/// Pure parsing and temporary-file checks; never installs or contacts the guard.
enum CLIRefactorSelfTest {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw VaultyGuardInstallerError.commandFailed(message) }
        }
        let aliases: [(String, Command)] = [
            ("block", .block), ("BLOCK", .block), ("unblock", .unblock), ("un-block", .unblock),
            ("status", .status), ("short-form-block", .shortFormBlock), ("shortform-block", .shortFormBlock),
            ("shorts-block", .shortFormBlock), ("short-form-unblock", .shortFormUnblock),
            ("shortform-unblock", .shortFormUnblock), ("shorts-unblock", .shortFormUnblock),
            ("short-form-status", .shortFormStatus), ("shortform-status", .shortFormStatus),
            ("shorts-status", .shortFormStatus), ("allowlist", .allowlist), ("channels", .allowlist),
            ("help", .help), ("--help", .help), ("-h", .help), ("version", .version),
            ("--version", .version), ("-v", .version)
        ]
        for (alias, command) in aliases {
            try require(try CLIArgumentParser.parse([alias]).command == command, "CLI alias changed: \(alias)")
        }
        for prefix in ["short-form", "shortform"] {
            for (verb, command) in [("block", Command.shortFormBlock), ("unblock", .shortFormUnblock), ("un-block", .shortFormUnblock), ("status", .shortFormStatus)] {
                try require(try CLIArgumentParser.parse([prefix, verb]).command == command, "short-form subcommand changed")
            }
        }
        let parsed = try CLIArgumentParser.parse(["block", "--hosts-file", "/tmp/test-hosts", "--domain", "youtube.com", "--domain", "reddit.com", "--dry-run"])
        try require(parsed.hostsFileURL.path == "/tmp/test-hosts" && parsed.domains == ["youtube.com", "reddit.com"] && parsed.dryRun, "CLI block options changed")
        for invalid in [["block", "--hosts-file"], ["block", "--hosts-file", ""], ["block", "--domain"], ["unblock", "--domain", "example.com"], ["status", "--dry-run"], ["short-form", "block", "--domain", "example.com"], ["bogus"], ["block", "--bogus"]] {
            do { _ = try CLIArgumentParser.parse(invalid) }
            catch is CLIError { continue }
            throw VaultyGuardInstallerError.commandFailed("Invalid CLI input accepted: \(invalid)")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vaulty-cli-self-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("artifact")
        try CLIAtomicFileWriter.write(Data("original".utf8), to: destination, mode: 0o600, owner: geteuid(), group: getegid())
        try CLIAtomicFileWriter.write(Data("replacement".utf8), to: destination, mode: 0o640, owner: geteuid(), group: getegid())
        try require(try Data(contentsOf: destination) == Data("replacement".utf8), "CLI artifact replacement failed")
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        try require((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640, "CLI artifact metadata changed")
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do { try CLIAtomicFileWriter.write(Data("bad".utf8), to: destination, mode: 0o600, owner: geteuid(), group: getegid()) }
        catch {
            let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            let type = try FileManager.default.attributesOfItem(atPath: destination.path)[.type] as? FileAttributeType
            try require(entries == ["artifact"] && type == .typeDirectory, "CLI failed publication deleted destination or leaked staging")
            print("PASS: CLI aliases, argument errors, and atomic artifact fixture checks")
            return
        }
        throw VaultyGuardInstallerError.commandFailed("CLI artifact publication overwrote a directory")
    }
}
