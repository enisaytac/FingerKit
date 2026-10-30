import AppKit
import Observation
import SQLite3
import FingerKitCore

/// Mac'in Ekran Süresi kaydından son 30 günde en çok önde kalan uygulamalar.
/// Kayıt `knowledgeC.db` dosyasında; okumak için Tam Disk Erişimi izni gerekebilir.
@Observable
final class AppUsage {
    static let shared = AppUsage()

    struct Entry: Hashable {
        let bundleID: String
        let hours: Double
    }

    /// En çok kullanılan başta
    private(set) var ranked: [Entry] = []
    /// nil: henüz okunmadı; false: okunamadı
    private(set) var readable: Bool?

    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var reading = false

    private static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db").path

    func hours(_ bundleID: String) -> Double? {
        ranked.first { $0.bundleID == bundleID }?.hours
    }

    /// Son okumadan 10 dakika geçtiyse yeniden okur
    func refreshIfStale() {
        if let lastRead, Date().timeIntervalSince(lastRead) < 600 { return }
        refresh()
    }

    func refresh() {
        guard !reading else { return }
        reading = true
        DispatchQueue.global(qos: .utility).async {
            let result = Self.read()
            DispatchQueue.main.async { [self] in
                reading = false
                lastRead = Date()
                switch result {
                case .success(let list):
                    if readable != true || list.first != ranked.first {
                        Log.write("Kullanım kaydı okundu: \(list.prefix(6).map(\.bundleID).joined(separator: ", "))")
                    }
                    ranked = list
                    readable = true
                case .failure(let error):
                    if readable != false { Log.write("HATA: kullanım kaydı okunamadı: \(error.message)") }
                    readable = false
                }
            }
        }
    }

    struct ReadError: Error {
        let message: String
    }

    private static func read() -> Result<[Entry], ReadError> {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return .failure(ReadError(message: String(cString: sqlite3_errmsg(db))))
        }
        let sql = """
            SELECT ZVALUESTRING, SUM(ZENDDATE - ZSTARTDATE) FROM ZOBJECT
            WHERE ZSTREAMNAME = '/app/usage' AND ZSTARTDATE > ? AND ZVALUESTRING IS NOT NULL
            GROUP BY ZVALUESTRING ORDER BY 2 DESC LIMIT 40
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return .failure(ReadError(message: String(cString: sqlite3_errmsg(db))))
        }
        // Kayıttaki zamanlar 2001'den beri saniye
        sqlite3_bind_double(statement, 1, Date().timeIntervalSinceReferenceDate - 30 * 86400)
        var list: [Entry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            list.append(Entry(bundleID: String(cString: text), hours: sqlite3_column_double(statement, 1) / 3600))
        }
        return .success(list)
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
