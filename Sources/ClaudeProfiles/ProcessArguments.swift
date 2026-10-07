import Darwin
import Foundation

enum ProcessArguments {
    static let dataDirFlag = "--user-data-dir"

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func userDataDir(of pid: pid_t) -> String? {
        guard let args = read(pid: pid) else { return nil }
        for (index, arg) in args.enumerated() {
            if arg.hasPrefix("\(dataDirFlag)=") {
                return normalize(String(arg.dropFirst(dataDirFlag.count + 1)))
            }
            if arg == dataDirFlag, index + 1 < args.count {
                return normalize(args[index + 1])
            }
        }
        return nil
    }

    static func read(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let count = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var args: [String] = []
        while args.count < count, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }
}
