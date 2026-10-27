// SCRATCH: the website's real app captures (CLAUDE.md, Assets, Screenshots). tools/capture/capture.sh copies it into
// ../softfill/SoftfillUITests/ for its build step and deletes it right after; never commit it to the app repo (its UI
// tests are Phase 2). This copy is the source.
//
// Sunny Meadow in Garden party, the hero's drawing. The seed colors every area except the hero's eleven, as a person
// would: pick a swatch, tap the areas of that color. Each capture opens the piece in one language, taps ten of the
// eleven (the last stays white, so the drawing never finishes and no celebration covers it), takes a still, and undoes
// the ten, so the next language starts from the same picture. On iPad the host records the screen meanwhile; the two
// sides take turns through files in $CAPTURE_DIR (TEST_RUNNER_CAPTURE_DIR on the xcodebuild line).
import XCTest

@MainActor
final class HeroCaptureScratchTests: XCTestCase {
    private static let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let drawings = source.appending(path: "Packages/SoftfillKit/Sources/Content/Resources/Drawings")

    private static let drawing = "sunny-meadow"
    private static let palette = "garden-party"
    private static let pack = "meadow-friends"
    /// The areas the hero fills, in order (the same as tools/art/recipe.json's hero video). The seed leaves them
    /// white; a capture taps all but the last.
    private static let sequence = [14, 15, 43, 23, 39, 34, 36, 31, 35, 30, 32]
    private static let taps = 10
    /// Uncounted areas smaller than this (in drawing pixels from the center to the nearest line) stay white.
    private static let smallestTapRadius = 4.0

    /// Seconds between taps, on top of the half second or so each tap takes to synthesize: about the old hero's pace
    /// (17 s for eleven fills). The ripple itself takes 0.65 s at the calm fill speed.
    private static let lead = 1.2
    private static let afterSwatch = 0.6
    private static let betweenTaps = 0.7
    private static let hold = 2.0

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var device: String { isPad ? "ipad" : "iphone" }
    private var captureDirectory: URL? {
        ProcessInfo.processInfo.environment["CAPTURE_DIR"].map { URL(filePath: $0) }
    }

    override func setUp() {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
    }

    // MARK: Content, read from the app's own files

    private struct Region {
        let id: Int, slot: Int, counts: Bool, x: Double, y: Double, radius: Double
    }

    private static let document: [String: Any] = {
        let url = drawings.appending(path: "\(drawing)/drawing.json")
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }()

    private static var imageSize: CGSize {
        let image = document["image"] as? [String: Any] ?? [:]
        return CGSize(width: image["width"] as? Double ?? 1, height: image["height"] as? Double ?? 1)
    }

    private static let regions: [Int: Region] = {
        var table: [Int: Region] = [:]
        for entry in document["regions"] as? [[String: Any]] ?? [] {
            guard let id = entry["id"] as? Int, let center = entry["center"] as? [String: Any] else { continue }
            table[id] = Region(
                id: id, slot: entry["slot"] as? Int ?? 1, counts: entry["counts"] as? Bool ?? false,
                x: center["x"] as? Double ?? 0, y: center["y"] as? Double ?? 0,
                radius: entry["centerRadius"] as? Double ?? 0)
        }
        return table
    }()

    private static let catalog: [String: [String: String]] = {
        var table: [String: [String: String]] = [:]
        let path = "Softfill/Localizable.xcstrings"
        guard let data = try? Data(contentsOf: source.appending(path: path)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = json["strings"] as? [String: Any]
        else { return table }
        for (key, entry) in strings {
            guard let locs = (entry as? [String: Any])?["localizations"] as? [String: Any] else { continue }
            var values: [String: String] = [:]
            for (lang, loc) in locs {
                if let unit = (loc as? [String: Any])?["stringUnit"] as? [String: Any],
                    let value = unit["value"] as? String
                {
                    values[lang] = value
                }
            }
            table[key] = values
        }
        return table
    }()

    private func t(_ key: String, _ lang: String) -> String { Self.catalog[key]?[lang] ?? key }

    private func localizedName(_ names: Any?, _ lang: String, fallback: String) -> String {
        let names = names as? [String: String] ?? [:]
        return names[lang] ?? names["en"] ?? fallback
    }

    private func drawingName(_ lang: String) -> String {
        localizedName(Self.document["name"], lang, fallback: Self.drawing)
    }

    private func paletteName(_ lang: String) -> String {
        let palettes = Self.document["palettes"] as? [[String: Any]] ?? []
        let entry = palettes.first { $0["id"] as? String == Self.palette }
        return localizedName(entry?["name"], lang, fallback: Self.palette)
    }

    private func packName(_ lang: String) -> String {
        let url = Self.drawings.deletingLastPathComponent().appending(path: "catalog.json")
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let packs = json["packs"] as? [[String: Any]]
        else { return Self.pack }
        let pack = packs.first { $0["id"] as? String == Self.pack }
        return localizedName(pack?["name"], lang, fallback: Self.pack)
    }

    // MARK: Driving

    private func launch(_ lang: String) -> XCUIApplication {
        let app = XCUIApplication()
        let locale = ["en": "en_US", "de": "de_DE", "ro": "ro_RO", "ru": "ru_RU"][lang] ?? "en_US"
        app.launchArguments = [
            "-AppleLanguages", "(\(lang))", "-AppleLocale", locale,
            "-softfill.hasSeenOnboarding", "<true/>", "-softfill.iCloudSync", "<false/>",
            "-softfill.hasSeenZoomHint", "<true/>", "-softfill.sounds", "<false/>", "-softfill.haptics", "<false/>",
            "-softfill.fillSpeed", "calm", "-library.level", "easy",
        ]
        app.launch()
        return app
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tapWhenReady(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        var found = element.waitForExistence(timeout: 4)
        var swipes = 0
        while !found && swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
            found = element.waitForExistence(timeout: 1.5)
        }
        guard found else {
            XCTFail("not found: \(element)", file: file, line: line)
            return
        }
        var tries = 0
        while !element.isHittable && tries < 6 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        element.tap()
    }

    private func shot(_ name: String, lang: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(device)-\(lang)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The paper: the drawing's name with its progress as the value; the top bar's title is the smaller element.
    private func paper(_ app: XCUIApplication, _ lang: String) -> XCUIElement {
        let named = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", drawingName(lang)))
        _ = named.firstMatch.waitForExistence(timeout: 20)
        let candidates = named.allElementsBoundByIndex
        let area = { (element: XCUIElement) in element.frame.width * element.frame.height }
        return candidates.max { area($0) < area($1) } ?? named.firstMatch
    }

    /// Opens the piece from its pack; a new piece picks its palette first.
    private func openCanvas(_ app: XCUIApplication, _ lang: String) -> XCUIElement {
        tapWhenReady(button(app, containing: packName(lang)))
        tapWhenReady(button(app, containing: drawingName(lang)))
        let start = app.buttons.matching(NSPredicate(format: "label == %@", t("Start coloring", lang)))
        if start.firstMatch.waitForExistence(timeout: 4) {
            let row = app.buttons[paletteName(lang)]
            if row.waitForExistence(timeout: 3) { row.tap() }
            Thread.sleep(forTimeInterval: 0.8)
            // The pack page's own hero button can say "Start coloring" too; the sheet's is the one that can be hit.
            guard let sheetButton = start.allElementsBoundByIndex.last(where: { $0.isHittable }) else {
                XCTFail("no hittable Start coloring")
                return app
            }
            sheetButton.tap()
        }
        let canvas = paper(app, lang)
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "the canvas did not open")
        Thread.sleep(forTimeInterval: 2.5)
        return canvas
    }

    /// The point on screen, relative to the canvas element, where a region's center is drawn at 100% zoom: the paper
    /// fits the canvas minus the controls' insets (CanvasContent: pad 8/112/120/112, phone 8/16/64/16), centered.
    private func point(of region: Region, in canvas: XCUIElement) -> XCUICoordinate {
        let frame = canvas.frame
        let insets: (top: Double, left: Double, bottom: Double, right: Double) =
            isPad ? (8, 112, 120, 112) : (8, 16, 64, 16)
        let freeWidth = frame.width - insets.left - insets.right
        let freeHeight = frame.height - insets.top - insets.bottom
        let image = Self.imageSize
        let scale = min(freeWidth / image.width, freeHeight / image.height)
        let originX = insets.left + (freeWidth - image.width * scale) / 2
        let originY = insets.top + (freeHeight - image.height * scale) / 2
        return canvas.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: originX + region.x * scale, dy: originY + region.y * scale))
    }

    private func swatch(_ app: XCUIApplication, slot: Int, _ lang: String) -> XCUIElement {
        let label = t("Color %lld", lang).replacingOccurrences(of: "%lld", with: "\(slot)")
        return app.buttons[label].firstMatch
    }

    private func progress(_ canvas: XCUIElement) -> [Int] {
        ((canvas.value as? String) ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// Only the iPad run talks to the host; the iPhone run takes its still without a recording.
    private func signal(_ name: String) {
        guard isPad, let directory = captureDirectory else { return }
        let stamp = String(Date().timeIntervalSince1970)
        try? stamp.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func wait(for name: String, timeout: TimeInterval = 60) -> Bool {
        guard let directory = captureDirectory else { return true }
        let url = directory.appending(path: name)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    // MARK: Seed (English, once per device)

    func test1Seed() {
        let app = launch("en")
        let canvas = openCanvas(app, "en")
        shot("seed-opened", lang: "en")
        let keep = Set(Self.sequence)
        let targets = Self.regions.values
            .filter { !keep.contains($0.id) && ($0.counts || $0.radius >= Self.smallestTapRadius) }
            .sorted { ($0.slot, $0.id) < ($1.slot, $1.id) }
        var slot = 0
        for region in targets {
            if region.slot != slot {
                slot = region.slot
                swatch(app, slot: slot, "en").tap()
            }
            point(of: region, in: canvas).tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
        let counted = Self.regions.values.filter(\.counts).count
        XCTAssertEqual(progress(canvas), [counted - keep.count, counted], "seed: \(canvas.value ?? "?")")
        shot("seed", lang: "en")
        // Leaving the foreground saves the piece.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
    }

    // MARK: Captures, one test per language

    func test2CaptureEnglish() { capture("en") }
    func test3CaptureGerman() { capture("de") }
    func test4CaptureRomanian() { capture("ro") }
    func test5CaptureRussian() { capture("ru") }

    private func capture(_ lang: String) {
        let app = launch(lang)
        let canvas = openCanvas(app, lang)
        let start = progress(canvas)
        shot("start", lang: lang)
        if isPad {
            signal("ready-\(lang)")
            XCTAssertTrue(wait(for: "recording-\(lang)"), "the host never started recording")
            Thread.sleep(forTimeInterval: Self.lead)
        }
        signal("first-\(lang)")
        var slot = 0
        for id in Self.sequence.prefix(Self.taps) {
            guard let region = Self.regions[id] else { continue }
            if region.slot != slot {
                slot = region.slot
                swatch(app, slot: slot, lang).tap()
                Thread.sleep(forTimeInterval: Self.afterSwatch)
            }
            point(of: region, in: canvas).tap()
            Thread.sleep(forTimeInterval: Self.betweenTaps)
        }
        Thread.sleep(forTimeInterval: Self.hold)
        signal("done-\(lang)")
        if isPad { XCTAssertTrue(wait(for: "stopped-\(lang)"), "the host never stopped recording") }
        shot("end", lang: lang)
        XCTAssertEqual(progress(canvas).first, (start.first ?? 0) + Self.taps, "\(canvas.value ?? "?")")
        let undo = app.buttons[t("Undo", lang)].firstMatch
        for _ in 0..<Self.taps { undo.tap() }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(progress(canvas), start, "undo did not return to the seed")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
    }
}
