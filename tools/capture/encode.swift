// Turns tools/capture/capture.sh's raw captures into Home's assets, with the macOS frameworks only (AVFoundation,
// Core Image, ImageIO): no ffmpeg, nothing to install.
//
//   swiftc -O tools/capture/encode.swift -o encode && ./encode <work-dir> src/assets [lang ...]
//
// For each language:
// - the iPad screen recording (rec/ipad-<lang>.mp4, portrait pixels with a rotation) is turned upright, trimmed from
//   a second before the first tap to the end of the hold (sig/first-, done-, started-<lang>: Unix times from the test
//   and the host), resampled to a steady 30 fps, cross-faded back into its first frame so the loop has no jump, and
//   written as H.264 at 1152 and 768 px wide: video/hero-<lang>-<width>.mp4;
// - the first frame of that loop, from the full-size recording, is the poster: img/home/hero-poster-<lang>-<width>;
// - the stills after the taps, raw/ipad-<lang>-end.png and raw/iphone-<lang>-end.png (XCUITest screenshots, which
//   carry an orientation flag), become img/home/devices-ipad-<lang>-1032 and devices-iphone-<lang>-402 (a third
//   of the iPhone 17's 1206 × 2622 pixels, so both sides stay even).
// Stills are AVIF with a JPEG fallback, at the same qualities as tools/art/render.swift.
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("encode: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: encode <work-dir> <assets-dir> [lang ...]") }
let work = URL(fileURLWithPath: args[1])
let assets = URL(fileURLWithPath: args[2])
let langs = args.count > 3 ? Array(args[3...]) : ["en", "de", "ro", "ru"]

let fps = 30
/// The loop starts this long before the first tap (the first tap picks a swatch).
let leadIn = 1.0
/// The cross-fade from the last frame back into the first.
let fadeSeconds = 0.6
/// Width → average bitrate. The old rendered hero was 1.27 MB at 1152 and 0.74 MB at 768 for 17 s.
let videoWidths: [(width: Int, bitrate: Int)] = [(1152, 560_000), (768, 320_000)]
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])

func number(_ name: String) -> Double {
    let url = work.appendingPathComponent("sig/\(name)")
    guard let text = try? String(contentsOf: url, encoding: .utf8),
        let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    else { fail("missing or unreadable \(url.path)") }
    return value
}

func scaled(_ image: CIImage, toWidth width: Int) -> CIImage {
    let scale = Double(width) / image.extent.width
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(scale, forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    let out = filter.outputImage!
    let height = (image.extent.height * scale).rounded()
    return out.cropped(to: CGRect(x: out.extent.minX, y: out.extent.minY, width: Double(width), height: height))
        .transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
}

func writeStill(_ image: CGImage, base: URL) {
    // Chrome sizes an AVIF from ImageIO with an odd width or height but never paints it (checked 2026-10-27).
    guard image.width % 2 == 0, image.height % 2 == 0 else { fail("\(base.lastPathComponent): odd size") }
    try? FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
    for (ext, type, quality) in [("avif", UTType("public.avif")!, 0.62), ("jpg", UTType.jpeg, 0.86)] {
        let url = base.appendingPathExtension(ext)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            fail("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { fail("cannot finalize \(url.path)") }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("wrote \(url.lastPathComponent) (\(image.width)x\(image.height), \(size / 1024) KB)")
    }
}

func render(_ image: CIImage) -> CGImage {
    guard let cg = ci.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: srgb) else {
        fail("cannot render a frame")
    }
    return cg
}

/// An XCUITest screenshot drawn upright at `width` px.
func still(_ png: URL, width: Int) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
        let full = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 100_000,
        ] as CFDictionary)
    else { fail("cannot read \(png.path)") }
    return render(scaled(CIImage(cgImage: full), toWidth: width))
}

final class VideoWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let url: URL
    var frames = 0

    init(url: URL, width: Int, height: Int, bitrate: Int) {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { fail("cannot write \(url.path)") }
        writer = w
        writer.shouldOptimizeForNetworkUse = true
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { fail("cannot start \(url.path): \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CIImage) {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        guard let pool = adaptor.pixelBufferPool else {
            fail("no pixel buffer pool: \(String(describing: writer.error))")
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pb = buffer else { fail("no pixel buffer") }
        ci.render(image, to: pb, bounds: image.extent, colorSpace: srgb)
        guard adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps)))
        else { fail("cannot append frame \(frames): \(String(describing: writer.error))") }
        frames += 1
    }

    func finish() {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { fail("video failed: \(String(describing: writer.error))") }
        // Optimizing for network use can leave AVFoundation's scratch copies ("<name>.sb-…") behind.
        let dir = url.deletingLastPathComponent()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where name.hasPrefix(url.lastPathComponent + ".sb-") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("wrote \(url.lastPathComponent) (\(frames) frames, \(size / 1024) KB)")
    }
}

func encodeHero(_ lang: String) {
    let movie = work.appendingPathComponent("rec/ipad-\(lang).mp4")
    let started = number("started-\(lang)")
    let start = number("first-\(lang)") - started - leadIn
    let end = number("done-\(lang)") - started
    guard start >= 0, end > start else { fail("\(lang): the times don't make a clip (\(start) to \(end))") }

    let asset = AVURLAsset(url: movie)
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var loaded: (AVAssetTrack, CGAffineTransform)?
    Task {
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
            let transform = try? await track.load(.preferredTransform)
        {
            loaded = (track, transform)
        }
        semaphore.signal()
    }
    semaphore.wait()
    guard let (track, transform) = loaded, let reader = try? AVAssetReader(asset: asset) else {
        fail("cannot read \(movie.path)")
    }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    reader.add(output)
    reader.startReading()

    /// The recording upright, moved back to the origin. The track's transform is written for y-down pixels; Core
    /// Image's y axis points up, so the same turn is the inverse matrix there.
    func upright(_ buffer: CVPixelBuffer) -> CIImage {
        let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: srgb]).transformed(by: transform.inverted())
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    // Frames are streamed into both widths at once; a held sample buffer keeps its pixels alive.
    var writers: [(width: Int, video: VideoWriter)] = []
    var current: CIImage?
    var first: CIImage?
    var pending = output.copyNextSampleBuffer()
    var held: CMSampleBuffer?
    let count = Int(((end - start) * Double(fps)).rounded())
    for index in 0..<count {
        let time = start + Double(index) / Double(fps)
        // The recording only has frames where the screen changed: hold the latest one at or before `time`.
        while let sample = pending, CMSampleBufferGetPresentationTimeStamp(sample).seconds <= time {
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                held = sample
                current = upright(buffer)
            }
            pending = output.copyNextSampleBuffer()
        }
        guard let frame = current else { fail("\(lang): no frame by \(time) s") }
        if first == nil {
            guard abs(frame.extent.width / frame.extent.height - 4.0 / 3.0) < 0.01 else {
                fail("\(lang): the recording is \(frame.extent.size), not a landscape 4:3 iPad screen")
            }
            first = CIImage(cgImage: render(frame))
            writers = videoWidths.map { width, bitrate in
                let height = Int((frame.extent.height * Double(width) / frame.extent.width).rounded())
                let url = assets.appendingPathComponent("video/hero-\(lang)-\(width).mp4")
                return (width, VideoWriter(url: url, width: width, height: height, bitrate: bitrate))
            }
        }
        for (width, video) in writers { video.append(scaled(frame, toWidth: width)) }
    }
    _ = held
    reader.cancelReading()
    guard let first, let last = current else { fail("\(lang): empty clip") }

    let fadeFrames = Int(fadeSeconds * Double(fps))
    for (width, video) in writers {
        let small = scaled(first, toWidth: width)
        let lastSmall = scaled(last, toWidth: width)
        for f in 1...fadeFrames {
            let t = Double(f) / Double(fadeFrames)
            let eased = 1 - pow(1 - t, 3)
            let dissolve = CIFilter(name: "CIDissolveTransition")!
            dissolve.setValue(lastSmall, forKey: kCIInputImageKey)
            dissolve.setValue(small, forKey: kCIInputTargetImageKey)
            dissolve.setValue(eased, forKey: kCIInputTimeKey)
            video.append(dissolve.outputImage!.cropped(to: small.extent))
        }
        video.finish()
        writeStill(render(small), base: assets.appendingPathComponent("img/home/hero-poster-\(lang)-\(width)"))
    }
    print("\(lang): \(String(format: "%.1f", Double(count + fadeFrames) / Double(fps))) s loop")
}

for lang in langs {
    encodeHero(lang)
    writeStill(
        still(work.appendingPathComponent("raw/ipad-\(lang)-end.png"), width: 1032),
        base: assets.appendingPathComponent("img/home/devices-ipad-\(lang)-1032"))
    writeStill(
        still(work.appendingPathComponent("raw/iphone-\(lang)-end.png"), width: 402),
        base: assets.appendingPathComponent("img/home/devices-iphone-\(lang)-402"))
}
