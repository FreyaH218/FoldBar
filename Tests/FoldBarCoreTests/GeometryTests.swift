import XCTest
import CoreGraphics
@testable import FoldBarCore

final class GeometryTests: XCTestCase {
    func testSecondaryScreenAbovePrimaryUsesPrimaryCoordinateOrigin() {
        let upper = CGRect(x: -1440, y: 900, width: 1440, height: 900)
        XCTAssertEqual(BarGeometry.quartzRect(upper, primaryHeight: 900),
                       CGRect(x: -1440, y: -900, width: 1440, height: 900))
    }

    func testPanelStaysInsideScreenWithNotchClearance() {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        let size = CGSize(width: 440, height: 610)
        for anchorX in [-1700.0, -1500, -756, 0, 200] {
            let origin = BarGeometry.panelOrigin(anchor: CGPoint(x: anchorX, y: 1182), size: size,
                                                 screen: screen, topInset: 38)
            let panel = CGRect(origin: origin, size: size)
            XCTAssertTrue(screen.contains(panel))
            XCTAssertLessThanOrEqual(panel.maxY, screen.maxY - 38 - 8)
        }
    }

    func testNotchAndOffscreenItemsAreDetected() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = CGRect(x: 660, y: 0, width: 190, height: 38)
        XCTAssertTrue(BarGeometry.isObscured(CGRect(x: 665, y: 0, width: 30, height: 24), screens: [screen], notches: [notch]))
        XCTAssertTrue(BarGeometry.isObscured(CGRect(x: -4000, y: 0, width: 30, height: 24), screens: [screen], notches: [notch]))
        XCTAssertFalse(BarGeometry.isObscured(CGRect(x: 1200, y: 0, width: 30, height: 24), screens: [screen], notches: [notch]))
        XCTAssertTrue(BarGeometry.isObscured(.zero, screens: [screen], notches: [notch]))
    }

    func testDisplayToLeftIsNotMistakenForOffscreen() {
        XCTAssertFalse(BarGeometry.isObscured(CGRect(x: -500, y: 0, width: 24, height: 24),
            screens: [CGRect(x: -1920, y: 0, width: 1920, height: 1080)], notches: []))
    }

    func testSearchSupportsChineseWhitespaceAndCase() {
        XCTAssertTrue(ItemSearch.matches("  电池  ", name: "电池", detail: "控制中心"))
        XCTAssertTrue(ItemSearch.matches("cloud SYNC", name: "Cloud Drive", detail: "Sync"))
        XCTAssertFalse(ItemSearch.matches("VPN", name: "电池", detail: "控制中心"))
        XCTAssertTrue(ItemSearch.matches("", name: "", detail: ""))
    }
}
