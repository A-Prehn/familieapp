import XCTest
import UIKit
@testable import Mindebog

// Thumbs i lister (#62): lister viser det lille billede, og en model uden originaler må aldrig
// få lov at "gemme" billederne (det ville slette dem i iCloud).
final class ThumbnailTests: XCTestCase {
    private func jpeg(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // ellers tegnes der i skærmens skala (2×/3×), og 200 px bliver 400 px
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testThumbnailIsSmall() throws {
        let original = jpeg(width: 2400, height: 1800)
        let thumb = try XCTUnwrap(ImageTools.thumbnail(original))
        let image = try XCTUnwrap(UIImage(data: thumb))
        XCTAssertEqual(Int(max(image.size.width, image.size.height)), Int(ImageTools.thumbPixels))
        XCTAssertLessThan(thumb.count, original.count)
        XCTAssertFalse(ImageTools.isSmallThumb(thumb))
    }

    func testOldSmallThumbIsRecognised() throws {
        // Thumbs fra 1.3 var 400 px — de skal laves om af originalen, så Hjem ikke ser sløret ud.
        XCTAssertTrue(ImageTools.isSmallThumb(jpeg(width: 400, height: 300)))
        XCTAssertFalse(ImageTools.isSmallThumb(jpeg(width: 1200, height: 900)))
        XCTAssertTrue(ImageTools.isSmallThumb(jpeg(width: 400, height: 300), original: jpeg(width: 2400, height: 1800)))
    }

    func testThumbOfSmallOriginalIsNotRemade() throws {
        // En original under 1200 px (fx et gammelt skærmbillede) får et thumb i sin egen størrelse —
        // det er så stort, det kan blive, og må ikke laves om igen og igen.
        let original = jpeg(width: 800, height: 600)
        let thumb = try XCTUnwrap(ImageTools.thumbnail(original))
        XCTAssertEqual(ImageTools.longestSide(thumb), 800)
        XCTAssertFalse(ImageTools.isSmallThumb(thumb, original: original))
        XCTAssertTrue(ImageTools.isSmallThumb(thumb), "Uden originalen at sammenligne med ser det lille ud")
    }

    func testFingerprintTellsSimilarImagesApart() {
        // Samme længde og samme header, men andet indhold midt i og til sidst — `Data.hashValue` (kun
        // længde og de første bytes) ville forveksle dem. Kendemærket sampler start, midte og slutning.
        var a = Data(repeating: 0xFF, count: 4096)
        var b = a
        a[2048] = 1
        b[2048] = 2
        var c = a
        c[4095] = 3
        XCTAssertNotEqual(ImageTools.fingerprint(a), ImageTools.fingerprint(c))
        XCTAssertNotEqual(ImageTools.fingerprint(a), ImageTools.fingerprint(b))
        XCTAssertEqual(ImageTools.fingerprint(a), ImageTools.fingerprint(a))
    }

    func testThumbnailKeepsSmallImages() throws {
        let small = jpeg(width: 200, height: 100)
        let thumb = try XCTUnwrap(ImageTools.thumbnail(small))
        let image = try XCTUnwrap(UIImage(data: thumb))
        XCTAssertEqual(Int(image.size.width), 200)
    }

    func testPhotoSetWithOnlyThumbIsNotEmpty() {
        let set = PhotoSet(single: nil, thumb: Data([1, 2, 3]), loaded: false)
        XCTAssertFalse(set.isEmpty, "Et thumb er et billede i listen")
        XCTAssertEqual(set.listPhoto, Data([1, 2, 3]))
        XCTAssertNil(set.coverPhoto, "Originalen er ikke hentet")
    }

    func testListPhotoPrefersThumb() {
        var h = Highlight(id: "h1", date: nil, text: "x", photos: [Data([9])], createdAt: Date())
        XCTAssertEqual(h.listPhoto, Data([9]))
        h.thumb = Data([1])
        XCTAssertEqual(h.listPhoto, Data([1]))
        XCTAssertTrue(h.hasPhotos)
    }

    func testModelsDefaultToLoaded() {
        // Modeller, der laves i appen (fx efter et gem), har originalerne og må gemme dem igen.
        XCTAssertTrue(Highlight(id: "h", date: nil, text: "", photos: [], createdAt: Date()).photosLoaded)
        XCTAssertTrue(PhotoSet().loaded)
        XCTAssertTrue(DiaryEntry(id: "d", date: nil, text: "", photo: nil, createdAt: Date()).photoLoaded)
        XCTAssertTrue(Letter(id: "l", title: "", text: "", author: "", writtenAt: Date(), openDate: nil).photoLoaded)
    }
}
