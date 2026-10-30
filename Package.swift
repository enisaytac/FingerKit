// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FingerKit",
    platforms: [.macOS(.v15)],
    targets: [
        // macOS'un belgesiz dokunma parçasına (MultitouchSupport) bağlanan küçük C katmanı
        .target(name: "CMultitouch"),
        // Saf mantık: hareketler, hareket tanıma, kısayol ve ayar modeli (testlenebilir)
        .target(name: "FingerKitCore"),
        // Menü çubuğu uygulaması: pencere, izinler, tıklama yakalama, kısayol gönderme
        .executableTarget(
            name: "FingerKit",
            dependencies: ["CMultitouch", "FingerKitCore"]
        ),
        .testTarget(
            name: "FingerKitCoreTests",
            dependencies: ["FingerKitCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
