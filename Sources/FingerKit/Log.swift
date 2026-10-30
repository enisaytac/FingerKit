import Foundation

/// Basit günlük: ~/Library/Logs/FingerKit.log. Hangi hareketin tanındığını, hangi kısayolun
/// gönderildiğini yazar; sorun ararken buraya bakılır.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FingerKit.log")
    private static let queue = DispatchQueue(label: "FingerKit.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            let fm = FileManager.default
            // 2 MB'ı geçince eskisi .old olur
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > 2_000_000 {
                let old = url.appendingPathExtension("old")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
