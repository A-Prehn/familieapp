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
        let original = jpeg(width: 1600, height: 1200)
        let thumb = try XCTUnwrap(ImageTools.thumbnail(original))
        let image = try XCTUnwrap(UIImage(data: thumb))
        XCTAssertEqual(Int(max(image.size.width, image.size.height)), 400)
        XCTAssertLessThan(thumb.count, original.count)
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
