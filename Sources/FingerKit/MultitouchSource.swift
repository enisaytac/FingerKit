import CMultitouch
import Foundation
import FingerKitCore

/// Trackpad'lerden dokunma verisini alır ve kare kare ana iş parçacığına iletir.
final class MultitouchSource {
    struct Device {
        let id: Int
        let widthMM: Double
        let heightMM: Double
        let builtIn: Bool
    }

    static let shared = MultitouchSource()

    /// (aygıt numarası, kare) — ana iş parçacığında çağrılır
    var onFrame: ((Int, TouchFrame) -> Void)?
    private(set) var devices: [Device] = []
    /// Trackpad'e en son ne zaman dokunuldu
    var lastTrackpadTouch = Date.distantPast

    /// Şu anki kaydırma trackpad'den mi (parmaklar az önce trackpad'deydi; süzülmede biraz daha uzun)
    func scrollIsFromTrackpad(momentum: Bool) -> Bool {
        Date().timeIntervalSince(lastTrackpadTouch) < (momentum ? 3 : 0.3)
    }

    /// Trackpad bulunup dinlenmeye başlandıysa true
    @discardableResult
    func start() -> Bool {
        devices = []
        guard tm_load() else {
            Log.write("HATA: MultitouchSupport yüklenemedi")
            return false
        }
        tm_set_callback(frameCallback)
        let count = tm_refresh_devices()
        for i in 0..<count {
            guard let device = tm_device_at(Int32(i)) else { continue }
            var w: Int32 = 0
            var h: Int32 = 0
            let known = tm_device_size(device, &w, &h) && w > 0 && h > 0
            // Boyu bilinmiyorsa 13" MacBook trackpad'i varsayılır
            let widthMM = known ? Double(w) / 100 : 130
            let heightMM = known ? Double(h) / 100 : 80
            let builtIn = tm_device_is_builtin(device)
            // Touch Bar gibi ince şerit biçimli yüzeyler trackpad değil
            if widthMM / heightMM > 4 {
                Log.write("aygıt \(i) atlandı (şerit: \(widthMM)×\(heightMM) mm)")
                continue
            }
            tm_device_start(device)
            devices.append(Device(id: Int(bitPattern: device), widthMM: widthMM, heightMM: heightMM, builtIn: builtIn))
            Log.write("trackpad \(i): \(widthMM)×\(heightMM) mm, \(builtIn ? "dahili" : "harici")")
        }
        return !devices.isEmpty
    }

    func stop() {
        tm_stop_all()
        devices = []
    }

    func device(_ id: Int) -> Device? {
        devices.first { $0.id == id }
    }
}

/// MultitouchSupport'un kendi iş parçacığında çağrılır; veriyi kopyalayıp ana iş parçacığına yollar.
private let frameCallback: TMFrameCallback = { device, touches, count, timestamp in
    var list: [Touch] = []
    if let touches, count > 0 {
        list.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let t = touches[i]
            list.append(Touch(id: t.identifier,
                              x: Double(t.normalized.position.x),
                              y: Double(t.normalized.position.y),
                              size: Double(t.size),
                              state: t.state))
        }
    }
    let frame = TouchFrame(time: timestamp, touches: list)
    let id = Int(bitPattern: device)
    DispatchQueue.main.async {
        let source = MultitouchSource.shared
        // Trackpad yatayından geniştir; Magic Mouse'un yüzeyi uzundur. Kaydırmanın nereden geldiğini ayırmak için.
        if !frame.touches.isEmpty, let d = source.device(id), d.widthMM >= d.heightMM { source.lastTrackpadTouch = Date() }
        source.onFrame?(id, frame)
    }
}
