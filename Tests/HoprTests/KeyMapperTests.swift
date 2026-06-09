import XCTest

// Tests for KeyMapper label assignment logic.
// These test the pure functions only — no AX API needed.

final class KeyMapperTests: XCTestCase {

    func testLabelLengthForZeroElements() {
        // With 0 elements, should still return 1 (minimum label length)
        let length = KeyMapper.labelLength(for: 0)
        XCTAssertEqual(length, 1)
    }

    func testLabelLengthForSingleElement() {
        let length = KeyMapper.labelLength(for: 1)
        XCTAssertEqual(length, 1)
    }

    func testLabelLengthFor26Elements() {
        // Exactly 26 → 1 char (A-Z)
        let length = KeyMapper.labelLength(for: 26)
        XCTAssertEqual(length, 1)
    }

    func testLabelLengthFor27Elements() {
        // 27 → needs 2 chars (AA-ZZ)
        let length = KeyMapper.labelLength(for: 27)
        XCTAssertEqual(length, 2)
    }

    func testLabelLengthFor676Elements() {
        // 676 = 26*26 → 2 chars
        let length = KeyMapper.labelLength(for: 676)
        XCTAssertEqual(length, 2)
    }

    func testLabelLengthFor677Elements() {
        // 677 → needs 3 chars
        let length = KeyMapper.labelLength(for: 677)
        XCTAssertEqual(length, 3)
    }

    func testUniformLabelLength() {
        let label = KeyMapper.uniformLabel(index: 0, length: 1)
        XCTAssertEqual(label.count, 1)
    }

    func testUniformLabelTwoChar() {
        let label = KeyMapper.uniformLabel(index: 0, length: 2)
        XCTAssertEqual(label.count, 2)
    }

    func testUniformLabelFirst26AreSingleChar() {
        // First 26 labels with length 1 should be A-Z
        let charArray = Array(KeyMapper.chars)
        for i in 0..<26 {
            let label = KeyMapper.uniformLabel(index: i, length: 1)
            XCTAssertEqual(label, String(charArray[i]), "Label at index \(i) should be \(charArray[i])")
        }
    }
}
