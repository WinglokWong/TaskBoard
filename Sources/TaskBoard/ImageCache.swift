import SwiftUI
import AppKit
import ImageIO

/// 附件缩略图缓存（按需降采样，避免加载原图）
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    private func key(_ attachment: Attachment, _ maxPixel: Int) -> NSString {
        "\(attachment.fileName)#\(maxPixel)" as NSString
    }

    /// 只查缓存，不读文件
    func cached(_ attachment: Attachment, maxPixel: Int = 600) -> NSImage? {
        cache.object(forKey: key(attachment, maxPixel))
    }

    /// 同步加载（会读文件）。界面中请使用 `load`。
    func thumbnail(for attachment: Attachment, maxPixel: Int = 600) -> NSImage? {
        if let hit = cached(attachment, maxPixel: maxPixel) { return hit }
        guard let cg = Self.decode(attachment.url, maxPixel: maxPixel) else { return nil }
        return store(cg, for: attachment, maxPixel: maxPixel)
    }

    /// 在后台线程解码，不阻塞界面
    @MainActor
    func load(_ attachment: Attachment, maxPixel: Int = 600) async -> NSImage? {
        if let hit = cached(attachment, maxPixel: maxPixel) { return hit }
        let url = attachment.url
        let cg = await Task.detached(priority: .userInitiated) {
            ImageCache.decode(url, maxPixel: maxPixel)
        }.value
        guard let cg else { return nil }
        return store(cg, for: attachment, maxPixel: maxPixel)
    }

    private func store(_ cg: CGImage, for attachment: Attachment, maxPixel: Int) -> NSImage {
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key(attachment, maxPixel))
        return image
    }

    private static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// 异步加载的附件缩略图：命中缓存时立即显示，否则先显示占位再后台加载
struct AttachmentThumbnail: View {
    let attachment: Attachment
    var maxPixel = 600

    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = image ?? ImageCache.shared.cached(attachment, maxPixel: maxPixel) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.12))
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .task(id: attachment.fileName) {
                image = await ImageCache.shared.load(attachment, maxPixel: maxPixel)
            }
    }
}
