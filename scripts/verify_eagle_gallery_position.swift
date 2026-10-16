import Foundation

enum Fixture {
    static let suiteName = "EaglePositionQA-" + UUID().uuidString
    // The private suite is used synchronously only. Detached checks below use pure values.
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: suiteName)!
}

func identical(_ a: Double, _ b: Double) -> Bool {
    a.bitPattern == b.bitPattern || (a.isNaN && b.isNaN)
}

func verifyValues() -> Int {
    let edges: [Double] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude,
        -.greatestFiniteMagnitude, 0.0, -0.0, 12.nextDown, 12.nextUp, (-12).nextDown, (-12).nextUp,
        0.125, -0.125, 11.875, -11.875]
    let inputs = edges + (-384...384).map { Double($0) / 16 }
    var count = 0
    for x in inputs {
        precondition(identical(PublicPosition.component(x), EagleGalleryPosition.component(x)))
        for y in inputs {
            let old = PublicPosition(x: x, y: y), owned = EagleGalleryPosition(x: x, y: y)
            precondition(identical(old.x, owned.x) && identical(old.y, owned.y))
            precondition(owned.x.isFinite && owned.y.isFinite)
            precondition((-12...12).contains(owned.x) && (-12...12).contains(owned.y))
            precondition(owned.x * 4 == (owned.x * 4).rounded())
            precondition(owned.y * 4 == (owned.y * 4).rounded())
            count += 1
        }
    }
    precondition(EagleGalleryPosition(x: 0.125, y: -0.125) == EagleGalleryPosition(x: 0.25, y: -0.25))
    precondition(EagleGalleryPosition(x: 100, y: -.infinity) == EagleGalleryPosition(x: 12, y: 0))
    return count
}

@main struct Runner {
    static func main() async {
        let direct = verifyValues()
        let detached = await Task.detached { verifyValues() }.value
        let defaults = Fixture.defaults
        defer { defaults.removePersistentDomain(forName: Fixture.suiteName) }
        let values: [Any?] = [nil, 0, true, false, "1.125", "-14.25", "invalid", 0.13, 18.5, -18.5]
        var saved = 0
        for surface in ["island", "dock", "icons", "Island", "", "unknown", "custom.🦅"] {
            let xKey = "eagle.\(surface)Gallery.positionX", yKey = "eagle.\(surface)Gallery.positionY"
            for x in values {
                for y in values {
                    if let x { defaults.set(x, forKey: xKey) } else { defaults.removeObject(forKey: xKey) }
                    if let y { defaults.set(y, forKey: yKey) } else { defaults.removeObject(forKey: yKey) }
                    let old = PublicPosition.saved(surface), owned = EagleGalleryPosition.saved(surface)
                    precondition(identical(old.x, owned.x) && identical(old.y, owned.y))
                    saved += 1
                }
            }
        }
        defaults.set(3.125, forKey: "eagle.islandGallery.positionX")
        defaults.set(-2.125, forKey: "eagle.islandGallery.positionY")
        defaults.set(-4.125, forKey: "eagle.dockGallery.positionX")
        defaults.set(5.125, forKey: "eagle.dockGallery.positionY")
        precondition(EagleGalleryPosition.saved("island") == EagleGalleryPosition(x: 3.25, y: -2.25))
        precondition(EagleGalleryPosition.saved("dock") == EagleGalleryPosition(x: -4.25, y: 5.25))
        print("PASS: \(direct) public/owned position pairs + \(detached) detached; \(saved) private-suite reads, separate surface keys, malformed preferences; suite removed")
    }
}
