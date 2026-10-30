// Yerel HTML sayfasının tam boy resmini çeker (Safari'ye dokunmadan, kendin bakmak için).
// Kullanım: swift Araclar/sayfa-resmi.swift <sayfa.html> <çıktı.png> [genişlik] [js]
import AppKit
import WebKit

let args = CommandLine.arguments
let page = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let width = args.count > 3 ? Double(args[3])! : 1280
let script = args.count > 4 ? args[4] : ""

final class Loader: NSObject, WKNavigationDelegate {
    func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
        web.evaluateJavaScript(script + ";document.documentElement.scrollHeight") { h, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                let height = min((h as? Double) ?? 2000, 16000)
                web.frame.size.height = height
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: width, height: height)
                web.takeSnapshot(with: config) { image, error in
                    if let image, let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: out); print("Yazıldı: \(out.path) (\(Int(width))×\(Int(height)))")
                    } else { print("Hata: \(String(describing: error))") }
                    exit(0)
                }
            }
        }
    }
}
let app = NSApplication.shared
let web = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = web
let loader = Loader()
web.navigationDelegate = loader
web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
app.run()
