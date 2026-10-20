import Combine
import PhotosUI
import SwiftUI
import UIKit

/// Optional profile photo kept on this device only. It is never uploaded: the server only stores avatar_color.
@MainActor
final class ProfileAvatarStore: ObservableObject {
    @Published private(set) var image: UIImage?

    private static let fileNameKey = "profile_avatar_image_file"
    private static let fileName = "profile_avatar.jpg"
    private static let maxPixelSize: CGFloat = 512

    init() {
        image = Self.loadStoredImage()
    }

    func save(_ picked: UIImage) {
        let resized = Self.downscaled(picked)
        guard let data = resized.jpegData(compressionQuality: 0.85),
              let url = Self.fileURL(named: Self.fileName) else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        UserDefaults.standard.set(Self.fileName, forKey: Self.fileNameKey)
        image = resized
    }

    func remove() {
        if let name = UserDefaults.standard.string(forKey: Self.fileNameKey),
           let url = Self.fileURL(named: name) {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: Self.fileNameKey)
        image = nil
    }

    private static func loadStoredImage() -> UIImage? {
        guard let name = UserDefaults.standard.string(forKey: fileNameKey),
              let url = fileURL(named: name) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    private static func fileURL(named name: String) -> URL? {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory?.appendingPathComponent(name)
    }

    /// Redraws the photo upright with its longest side at most 512 px.
    private static func downscaled(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > 0 else {
            return image
        }
        let ratio = min(1, maxPixelSize / longestSide)
        let targetSize = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

/// System photo picker (PHPickerViewController): needs no photo library permission and works on iOS 15.
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            let onPick = self.onPick
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                DispatchQueue.main.async {
                    onPick(image)
                }
            }
        }
    }
}
