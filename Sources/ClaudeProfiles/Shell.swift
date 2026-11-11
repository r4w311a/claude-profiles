import Foundation

enum Shell {
    struct Result {
        let status: Int32
        let output: Data
        let error: String

        var succeeded: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) -> Result {
        let process = Process()
        process.currentDirectoryURL = directory
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: Data(), error: error.localizedDescription)
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: outputData,
                      error: String(decoding: errorData, as: UTF8.self))
    }
}
