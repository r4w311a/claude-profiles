import Darwin
import Foundation

enum ProcessLookup {
    static func pid(executable: String) -> pid_t? {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return nil }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)

        for pid in pids.prefix(max(0, count)) where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            if String(cString: path) == executable { return pid }
        }
        return nil
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
