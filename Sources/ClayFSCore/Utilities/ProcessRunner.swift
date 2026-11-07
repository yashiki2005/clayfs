import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }
}

public enum ProcessRunner {
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory = currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    public static func hdiutil(_ args: String...) throws -> ProcessResult {
        try run(executable: "/usr/bin/hdiutil", arguments: args)
    }

    public static func diskutil(_ args: String...) throws -> ProcessResult {
        try run(executable: "/usr/sbin/diskutil", arguments: args)
    }
}
