// Renders the Home page's art from the app's own drawings: line art, region map, region slots and palettes
// from ../softfill/Packages/SoftfillKit/Sources/Content/Resources/Drawings/<id>/. Nothing is drawn by hand: a
// region is filled with its palette color by slot, exactly as the app fills it, and the line art is
// multiplied on top.
//
//   swiftc -O tools/art/render.swift -o /tmp/softfill-render
//   /tmp/softfill-render tools/art/recipe.json [output-id ...]       (tools/art/build.sh does both)
//   /tmp/softfill-render --debug <drawing-id> <out.png>              (regions numbered, colored by slot)
//
// Stills are written as AVIF plus a JPEG fallback, videos as H.264 MP4. See tools/art/recipe.json.
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - App data

struct DrawingDoc: Decodable {
    struct Size: Decodable { let width: Int; let height: Int }
    struct Rect: Decodable { let x: Int; let y: Int; let width: Int; let height: Int }
    struct Point: Decodable { let x: Double; let y: Double }
    struct Region: Decodable {
        let id: Int; let area: Int; let bounds: Rect; let center: Point; let centerRadius: Double
        let counts: Bool; let slot: Int
    }
    struct Palette: Decodable { let id: String; let colors: [String]; let secondColors: [String]? }
    let id: String
    let image: Size
    let regions: [Region]
    let palettes: [Palette]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

final class Drawing {
    let doc: DrawingDoc
    let width: Int
    let height: Int
    /// Region label per pixel, line pixels grown into their neighbours so color reaches under the lines.
    let owner: [UInt16]
    let lineArt: CGImage
    let regionsByID: [Int: DrawingDoc.Region]

    init(id: String, app: URL) {
        let dir = app.appendingPathComponent("Packages/SoftfillKit/Sources/Content/Resources/Drawings/\(id)")
        guard let json = try? Data(contentsOf: dir.appendingPathComponent("drawing.json")),
              let doc = try? JSONDecoder().decode(DrawingDoc.self, from: json) else { fail("cannot read \(id)/drawing.json") }
        self.doc = doc
        guard let source = CGImageSourceCreateWithURL(dir.appendingPathComponent("lineart.png") as CFURL, nil),
              let art = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(id)/lineart.png") }
        lineArt = art
        let (labels, w, h) = Drawing.readRegionMap(dir.appendingPathComponent("regions.bin"))
        width = w; height = h
        // Grow regions into line pixels (label 0), three passes, as the design mock does.
        var grown = labels
        for _ in 0..<3 {
            let previous = grown
            for i in 0..<(w * h) where previous[i] == 0 {
                let x = i % w
                var v: UInt16 = 0
                if x > 0, previous[i - 1] != 0 { v = previous[i - 1] }
                else if x < w - 1, previous[i + 1] != 0 { v = previous[i + 1] }
                else if i >= w, previous[i - w] != 0 { v = previous[i - w] }
                else if i < w * (h - 1), previous[i + w] != 0 { v = previous[i + w] }
                if v != 0 { grown[i] = v }
            }
        }
        owner = grown
        regionsByID = Dictionary(uniqueKeysWithValues: doc.regions.map { ($0.id, $0) })
    }

    /// `regions.bin`: "SFRG" raw or "SFR2" LZFSE, then width and height as little-endian UInt32, then one
    /// little-endian UInt16 label per pixel (the app's RegionMapFile.swift).
    static func readRegionMap(_ url: URL) -> ([UInt16], Int, Int) {
        guard let data = try? Data(contentsOf: url), data.count >= 12 else { fail("cannot read \(url.path)") }
        let magic = String(decoding: data.prefix(4), as: UTF8.self)
        func u32(_ at: Int) -> Int { (0..<4).reduce(0) { $0 | Int(data[data.startIndex + at + $1]) << (8 * $1) } }
        let w = u32(4), h = u32(8)
        var body = Data(data.dropFirst(12))
        if magic == "SFR2" {
            guard let raw = try? (body as NSData).decompressed(using: .lzfse) as Data else { fail("bad LZFSE in \(url.path)") }
            body = raw
        } else if magic != "SFRG" { fail("bad region map magic in \(url.path)") }
        guard body.count == w * h * 2 else { fail("region map size mismatch in \(url.path)") }
        var labels = [UInt16](repeating: 0, count: w * h)
        labels.withUnsafeMutableBytes { _ = body.copyBytes(to: $0) }
        return (labels.map { UInt16(littleEndian: $0) }, w, h)
    }

    func palette(_ id: String) -> [RGB] {
        guard let p = doc.palettes.first(where: { $0.id == id }) else {
            fail("\(doc.id) has no palette \(id); it has \(doc.palettes.map(\.id).joined(separator: ", "))")
        }
        // The app's `Palette.swatches`: with second tones, each main color followed by its second.
        let swatches = p.secondColors.map { seconds in
            seconds.count == p.colors.count ? zip(p.colors, seconds).flatMap { [$0, $1] } : p.colors
        } ?? p.colors
        return swatches.map(RGB.init(hex:))
    }

    func region(_ id: Int) -> DrawingDoc.Region {
        guard let r = regionsByID[id] else { fail("\(doc.id) has no region \(id)") }
        return r
    }
}

struct RGB {
    var r: UInt8, g: UInt8, b: UInt8
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { fail("bad color \(hex)") }
        r = UInt8(v >> 16 & 0xFF); g = UInt8(v >> 8 & 0xFF); b = UInt8(v & 0xFF)
    }
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    static let white = RGB(255, 255, 255)
}

// MARK: - Paint: the color layer under the line art

final class Paint {
    let drawing: Drawing
    let colors: [RGB]
    let context: CGContext
    let pixels: UnsafeMutablePointer<UInt8>

    init(_ drawing: Drawing, palette: String) {
        self.drawing = drawing
        colors = drawing.palette(palette)
        guard let ctx = CGContext(data: nil, width: drawing.width, height: drawing.height, bitsPerComponent: 8,
                                  bytesPerRow: drawing.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = ctx.data else { fail("cannot make a bitmap") }
        context = ctx
        pixels = data.bindMemory(to: UInt8.self, capacity: drawing.width * drawing.height * 4)
        clear()
    }

    func color(of region: Int) -> RGB {
        swatch(forSlot: drawing.region(region).slot)
    }

    /// The app's `Palette.swatch(forSlot:)`: slots count from 1 and wrap past the end.
    func swatch(forSlot slot: Int) -> RGB {
        colors[max(slot - 1, 0) % colors.count]
    }

    @inline(__always) func set(_ i: Int, _ c: RGB) {
        let p = i * 4
        pixels[p] = c.r; pixels[p + 1] = c.g; pixels[p + 2] = c.b; pixels[p + 3] = 255
    }

    func clear() {
        for i in 0..<(drawing.width * drawing.height) { set(i, .white) }
    }

    /// Fills whole regions.
    func fill(_ regions: Set<Int>) {
        var lookup = [RGB?](repeating: nil, count: Int(UInt16.max) + 1)
        for id in regions { lookup[id] = color(of: id) }
        for i in 0..<(drawing.width * drawing.height) {
            if let c = lookup[Int(drawing.owner[i])] { set(i, c) }
        }
    }

    /// Fills the part of a region inside a circle: the app's tap-to-fill ripple at one moment.
    func ripple(_ id: Int, center: (Double, Double), radius: Double, color: RGB? = nil) {
        let r = drawing.region(id), c = color ?? self.color(of: id)
        let x0 = max(0, r.bounds.x - 3), y0 = max(0, r.bounds.y - 3)
        let x1 = min(drawing.width - 1, r.bounds.x + r.bounds.width + 3)
        let y1 = min(drawing.height - 1, r.bounds.y + r.bounds.height + 3)
        let r2 = radius * radius
        for y in y0...y1 {
            let dy = Double(y) - center.1
            for x in x0...x1 {
                let i = y * drawing.width + x
                guard Int(drawing.owner[i]) == id else { continue }
                let dx = Double(x) - center.0
                if dx * dx + dy * dy <= r2 { set(i, c) }
            }
        }
    }

    /// Brush strokes clipped to one region, as Draw mode with "Stay inside the lines" paints them.
    func strokes(_ list: [Recipe.Stroke]) {
        let w = drawing.width, h = drawing.height
        for stroke in list {
            guard let mask = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let data = mask.data else { fail("cannot make a mask") }
            mask.setFillColor(gray: 0, alpha: 1); mask.fill(CGRect(x: 0, y: 0, width: w, height: h))
            mask.setStrokeColor(gray: 1, alpha: 1)
            mask.setLineWidth(stroke.width); mask.setLineCap(.round); mask.setLineJoin(.round)
            let pts = stroke.points.map { CGPoint(x: $0[0], y: Double(h) - $0[1]) }
            mask.move(to: pts[0])
            if pts.count > 2 {
                for i in 1..<(pts.count - 1) {
                    let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
                    mask.addQuadCurve(to: mid, control: pts[i])
                }
            }
            mask.addLine(to: pts[pts.count - 1]); mask.strokePath()
            let m = data.bindMemory(to: UInt8.self, capacity: w * h)
            let c = stroke.color.map(RGB.init(hex:)) ?? swatch(forSlot: stroke.slot ?? 1)
            let allowed = Set(stroke.regions)
            for i in 0..<(w * h) where m[i] > 0 && allowed.contains(Int(drawing.owner[i])) {
                let a = Int(m[i]), p = i * 4
                pixels[p] = UInt8((Int(c.r) * a + Int(pixels[p]) * (255 - a)) / 255)
                pixels[p + 1] = UInt8((Int(c.g) * a + Int(pixels[p + 1]) * (255 - a)) / 255)
                pixels[p + 2] = UInt8((Int(c.b) * a + Int(pixels[p + 2]) * (255 - a)) / 255)
            }
        }
    }

    func image() -> CGImage {
        guard let img = context.makeImage() else { fail("cannot snapshot paint") }
        return img
    }
}

// MARK: - Recipe

struct Recipe: Decodable {
    struct FillSpec: Decodable {
        var all: Bool?
        var only: [Int]?
        var except: [Int]?
    }
    struct Stroke: Decodable {
        var regions: [Int]
        var slot: Int?
        var color: String?
        var width: Double
        var points: [[Double]]
    }
    struct Ripple: Decodable {
        var region: Int
        var progress: Double
        var ring: Bool?
        var at: [Double]?
    }
    struct Output: Decodable {
        var id: String
        var type: String              // "still", "fillVideo", "timelapse"
        var drawing: String
        var palette: String
        var out: String               // path without extension, relative to the repo root
        var widths: [Int]?            // stills: one file per width; videos: the first
        var crop: [Double]?           // x, y, width, height in drawing pixels
        var fill: FillSpec?           // stills and the start of a fillVideo
        var ripple: Ripple?
        var strokes: [Stroke]?
        var quality: Double?
        // fillVideo
        var sequence: [Int]?
        var fps: Int?
        var leadMs: Int?
        var rippleMs: Int?
        var gapMs: Int?
        var holdMs: Int?
        var fadeMs: Int?
        var bitrate: Int?
        // timelapse
        var seconds: Double?
    }
    var app: String
    var outputs: [Output]
}

func regions(_ spec: Recipe.FillSpec?, in drawing: Drawing) -> Set<Int> {
    let every = Set(drawing.doc.regions.map(\.id))
    guard let spec else { return [] }
    if spec.all == true { return every.subtracting(spec.except ?? []) }
    if let only = spec.only { return Set(only) }
    if let except = spec.except { return every.subtracting(except) }
    return []
}

// MARK: - Compositing

struct Frame {
    let width: Int
    let height: Int
    let crop: CGRect
    var scale: Double { Double(width) / crop.width }

    init(drawing: Drawing, crop: [Double]?, width: Int) {
        let c = crop.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
            ?? CGRect(x: 0, y: 0, width: drawing.width, height: drawing.height)
        self.crop = c
        self.width = width
        height = Int((c.height * Double(width) / c.width).rounded())
    }

    /// Draws the paint, then the line art multiplied on top, then an optional touch ring.
    func draw(into ctx: CGContext, paint: CGImage, drawing: Drawing, ring: (x: Double, y: Double, radius: Double, alpha: Double)? = nil,
              overlay: CGImage? = nil, overlayAlpha: Double = 0) {
        let s = scale
        let rect = CGRect(x: -crop.minX * s, y: Double(height) + crop.minY * s - Double(drawing.height) * s,
                          width: Double(drawing.width) * s, height: Double(drawing.height) * s)
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(paint, in: rect)
        if let overlay, overlayAlpha > 0 {
            ctx.saveGState(); ctx.setAlpha(overlayAlpha); ctx.draw(overlay, in: rect); ctx.restoreGState()
        }
        ctx.setBlendMode(.multiply)
        ctx.draw(drawing.lineArt, in: rect)
        ctx.setBlendMode(.normal)
        if let ring, ring.alpha > 0 {
            let cx = (ring.x - crop.minX) * s, cy = Double(height) - (ring.y - crop.minY) * s
            ctx.setStrokeColor(CGColor(srgbRed: 28 / 255, green: 31 / 255, blue: 37 / 255, alpha: 0.55 * ring.alpha))
            ctx.setLineWidth(5 * s)
            ctx.strokeEllipse(in: CGRect(x: cx - ring.radius * s, y: cy - ring.radius * s, width: 2 * ring.radius * s, height: 2 * ring.radius * s))
            ctx.setFillColor(CGColor(srgbRed: 28 / 255, green: 31 / 255, blue: 37 / 255, alpha: 0.18 * ring.alpha))
            ctx.fillEllipse(in: CGRect(x: cx - 16 * s, y: cy - 16 * s, width: 32 * s, height: 32 * s))
        }
    }
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    else { fail("cannot make a \(w)x\(h) context") }
    return ctx
}

func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        fail("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fail("cannot finalize \(url.path)") }
}

/// The point a finger lands on: the region's visual center from drawing.json, or the recipe's own.
func touchPoint(_ r: DrawingDoc.Region, at: [Double]?) -> (Double, Double) {
    if let at { return (at[0], at[1]) }
    return (r.center.x, r.center.y)
}

/// The radius at which a ripple from `p` covers the whole region.
func fullRadius(_ r: DrawingDoc.Region, from p: (Double, Double)) -> Double {
    let xs = [Double(r.bounds.x - 3), Double(r.bounds.x + r.bounds.width + 3)]
    let ys = [Double(r.bounds.y - 3), Double(r.bounds.y + r.bounds.height + 3)]
    var best = 0.0
    for x in xs { for y in ys { best = max(best, ((x - p.0) * (x - p.0) + (y - p.1) * (y - p.1)).squareRoot()) } }
    return best
}

func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }

// MARK: - Outputs

func renderStill(_ o: Recipe.Output, root: URL, drawing: Drawing) {
    let paint = Paint(drawing, palette: o.palette)
    paint.fill(regions(o.fill, in: drawing))
    var ring: (x: Double, y: Double, radius: Double, alpha: Double)? = nil
    if let rp = o.ripple {
        let r = drawing.region(rp.region), p = touchPoint(r, at: rp.at)
        paint.ripple(rp.region, center: p, radius: fullRadius(r, from: p) * rp.progress)
        if rp.ring ?? true { ring = (p.0, p.1, 30, 1) }
    }
    if let strokes = o.strokes { paint.strokes(strokes) }
    let img = paint.image()
    for width in o.widths ?? [drawing.width] {
        let frame = Frame(drawing: drawing, crop: o.crop, width: width)
        let ctx = makeContext(frame.width, frame.height)
        frame.draw(into: ctx, paint: img, drawing: drawing, ring: ring)
        guard let out = ctx.makeImage() else { fail("cannot render \(o.id)") }
        let base = root.appendingPathComponent("\(o.out)-\(width)")
        write(out, to: base.appendingPathExtension("avif"), type: UTType("public.avif")!, quality: o.quality ?? 0.62)
        write(out, to: base.appendingPathExtension("jpg"), type: .jpeg, quality: 0.86)
        print("wrote \(o.out)-\(width).avif/.jpg (\(frame.width)x\(frame.height))")
    }
}

final class VideoWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int
    var frameIndex = 0

    init(url: URL, width: Int, height: Int, fps: Int, bitrate: Int) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { fail("cannot write \(url.path)") }
        writer = w
        writer.shouldOptimizeForNetworkUse = true
        self.width = width; self.height = height; self.fps = fps
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

    func append(_ draw: (CGContext) -> Void) {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        guard let pool = adaptor.pixelBufferPool else { fail("no pixel buffer pool: \(String(describing: writer.error))") }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pb = buffer else { fail("no pixel buffer") }
        CVPixelBufferLockBaseAddress(pb, [])
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { fail("cannot draw into a pixel buffer") }
        draw(ctx)
        CVPixelBufferUnlockBaseAddress(pb, [])
        guard adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))) else {
            fail("cannot append frame \(frameIndex): \(String(describing: writer.error))")
        }
        frameIndex += 1
    }

    func finish() {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { fail("video failed: \(String(describing: writer.error))") }
        // Optimizing for network use leaves AVFoundation's scratch copies ("<name>.sb-…") behind here.
        let dir = writer.outputURL.deletingLastPathComponent()
        let scratch = writer.outputURL.lastPathComponent + ".sb-"
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(scratch) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}

/// Fills the regions of `sequence` one after another with the tap ripple, holds, then cross-fades back to
/// the first frame so the loop has no jump.
func renderFillVideo(_ o: Recipe.Output, root: URL, drawing: Drawing) {
    guard let sequence = o.sequence, !sequence.isEmpty else { fail("\(o.id) needs a sequence") }
    let fps = o.fps ?? 30
    let frame = Frame(drawing: drawing, crop: o.crop, width: o.widths?.first ?? 1152)
    let paint = Paint(drawing, palette: o.palette)
    let start = regions(o.fill, in: drawing)
    paint.fill(start)
    let first = paint.image()
    let ms = { (v: Int) in Int((Double(v) / 1000 * Double(fps)).rounded()) }
    let lead = ms(o.leadMs ?? 1000), gap = ms(o.gapMs ?? 450), hold = ms(o.holdMs ?? 2200), fade = ms(o.fadeMs ?? 600)
    let ringFrames = ms(450)
    let url = root.appendingPathComponent(o.out + ".mp4")
    let video = VideoWriter(url: url, width: frame.width, height: frame.height, fps: fps, bitrate: o.bitrate ?? 900_000)

    for _ in 0..<lead { video.append { frame.draw(into: $0, paint: first, drawing: drawing) } }
    for id in sequence {
        let r = drawing.region(id), p = touchPoint(r, at: nil), full = fullRadius(r, from: p)
        let duration = ms(o.rippleMs ?? (r.area > 40_000 ? 900 : 650))
        let total = max(duration, ringFrames)
        for f in 1...total {
            let t = Double(f) / Double(duration)
            paint.ripple(id, center: p, radius: max(1, full * easeOutCubic(t)))
            let rt = Double(f) / Double(ringFrames)
            let ring = rt < 1 ? (x: p.0, y: p.1, radius: 18 + 34 * rt, alpha: 1 - rt) : nil
            let img = paint.image()
            video.append { frame.draw(into: $0, paint: img, drawing: drawing, ring: ring) }
        }
        paint.ripple(id, center: p, radius: full + 4)
        let img = paint.image()
        for _ in 0..<gap { video.append { frame.draw(into: $0, paint: img, drawing: drawing) } }
    }
    let last = paint.image()
    for _ in 0..<hold { video.append { frame.draw(into: $0, paint: last, drawing: drawing) } }
    for f in 1...max(1, fade) {
        let a = easeOutCubic(Double(f) / Double(max(1, fade)))
        video.append { frame.draw(into: $0, paint: last, drawing: drawing, overlay: first, overlayAlpha: a) }
    }
    video.finish()
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("wrote \(o.out).mp4 (\(frame.width)x\(frame.height), \(video.frameIndex) frames, \(size / 1024) KB)")
}

/// A replay from blank paper to the finished drawing, region by region in slot order, as the Gallery's
/// time-lapse plays a session back.
func renderTimelapse(_ o: Recipe.Output, root: URL, drawing: Drawing) {
    let fps = o.fps ?? 30
    let frame = Frame(drawing: drawing, crop: o.crop, width: o.widths?.first ?? 768)
    let paint = Paint(drawing, palette: o.palette)
    let order = o.sequence ?? drawing.doc.regions.sorted {
        ($0.slot, $0.bounds.x + $0.bounds.width / 2) < ($1.slot, $1.bounds.x + $1.bounds.width / 2)
    }.map(\.id)
    let seconds = o.seconds ?? 5.2
    let ripple = Double(o.rippleMs ?? 260) / 1000
    let step = order.count > 1 ? (seconds - ripple) / Double(order.count - 1) : 0
    let total = Int((seconds * Double(fps)).rounded())
    let hold = Int((Double(o.holdMs ?? 800) / 1000 * Double(fps)).rounded())
    let url = root.appendingPathComponent(o.out + ".mp4")
    let video = VideoWriter(url: url, width: frame.width, height: frame.height, fps: fps, bitrate: o.bitrate ?? 700_000)
    var done = 0
    for f in 0...total {
        let now = Double(f) / Double(fps)
        for (i, id) in order.enumerated() {
            let start = Double(i) * step
            guard now >= start, i >= done else { continue }
            let r = drawing.region(id), p = touchPoint(r, at: nil), full = fullRadius(r, from: p)
            let t = (now - start) / ripple
            paint.ripple(id, center: p, radius: max(1, full * easeOutCubic(t)))
            if t >= 1 && i == done { done += 1 }
        }
        let img = paint.image()
        video.append { frame.draw(into: $0, paint: img, drawing: drawing) }
    }
    paint.fill(Set(order))
    let finished = paint.image()
    for _ in 0..<hold { video.append { frame.draw(into: $0, paint: finished, drawing: drawing) } }
    video.finish()
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("wrote \(o.out).mp4 (\(frame.width)x\(frame.height), \(video.frameIndex) frames, \(size / 1024) KB)")
}

/// Every region filled with its slot color and numbered at its center, for choosing regions in a recipe.
func renderDebug(id: String, app: URL, out: URL) {
    let drawing = Drawing(id: id, app: app)
    let paint = Paint(drawing, palette: drawing.doc.palettes[0].id)
    paint.fill(Set(drawing.doc.regions.map(\.id)))
    let frame = Frame(drawing: drawing, crop: nil, width: drawing.width)
    let ctx = makeContext(frame.width, frame.height)
    frame.draw(into: ctx, paint: paint.image(), drawing: drawing)
    for r in drawing.doc.regions {
        let label = "\(r.id)·\(r.slot)\(r.counts ? "" : "*")"
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, r.area > 4000 ? 22 : 13, nil)
        let attr = NSAttributedString(string: label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0.85, green: 0, blue: 0.3, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attr)
        let b = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(x: r.center.x - b.width / 2, y: Double(drawing.height) - r.center.y - b.height / 3)
        CTLineDraw(line, ctx)
    }
    guard let img = ctx.makeImage() else { fail("cannot render debug") }
    write(img, to: out, type: .png, quality: 1)
    print("wrote \(out.path): label·slot, * = not counted")
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
if args.first == "--debug" {
    guard args.count == 3 else { fail("usage: render --debug <drawing-id> <out.png>") }
    renderDebug(id: args[1], app: cwd.appendingPathComponent("../softfill").standardized, out: URL(fileURLWithPath: args[2]))
    exit(0)
}
guard let recipePath = args.first else { fail("usage: render <recipe.json> [output-id ...] | --debug <drawing-id> <out.png>") }
let recipeURL = URL(fileURLWithPath: recipePath, relativeTo: cwd)
guard let recipeData = try? Data(contentsOf: recipeURL) else { fail("cannot read \(recipePath)") }
let recipe: Recipe
do { recipe = try JSONDecoder().decode(Recipe.self, from: recipeData) } catch { fail("bad recipe: \(error)") }
func resolve(_ path: String) -> URL {
    path.hasPrefix("/") ? URL(fileURLWithPath: path) : cwd.appendingPathComponent(path).standardized
}
let root = cwd
let app = resolve(recipe.app)
let wanted = Set(args.dropFirst())
var cache: [String: Drawing] = [:]
for o in recipe.outputs where wanted.isEmpty || wanted.contains(o.id) {
    let drawing = cache[o.drawing] ?? Drawing(id: o.drawing, app: app)
    cache[o.drawing] = drawing
    switch o.type {
    case "still": renderStill(o, root: root, drawing: drawing)
    case "fillVideo": renderFillVideo(o, root: root, drawing: drawing)
    case "timelapse": renderTimelapse(o, root: root, drawing: drawing)
    default: fail("\(o.id): unknown type \(o.type)")
    }
}
