import XCTest
import Combine
@testable import SlapMe

final class MotionEngineTests: XCTestCase {
    var engine: MotionEngine!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        engine = MotionEngine()
        cancellables = []
    }

    override func tearDown() {
        engine.stopDetection()
        cancellables = nil
    }

    // MARK: - Force Normalization

    func testForceClampedToZeroOne() {
        // Simulate forces outside range
        engine.simulateForce(-0.5)
        XCTAssertGreaterThanOrEqual(engine.currentForce, 0.0)
        XCTAssertLessThanOrEqual(engine.currentForce, 1.0)

        engine.simulateForce(5.0)
        XCTAssertGreaterThanOrEqual(engine.currentForce, 0.0)
        XCTAssertLessThanOrEqual(engine.currentForce, 1.0)
    }

    func testForceCategorization() {
        XCTAssertEqual(MotionEngine.ForceCategory(force: 0.1), .tap)
        XCTAssertEqual(MotionEngine.ForceCategory(force: 0.29), .tap)
        XCTAssertEqual(MotionEngine.ForceCategory(force: 0.3), .hit)
        XCTAssertEqual(MotionEngine.ForceCategory(force: 0.5), .hit)
        XCTAssertEqual(MotionEngine.ForceCategory(force: 0.69), .hit)
        XCTAssertEqual(MotionEngine.ForceCategory(force: 0.7), .slap)
        XCTAssertEqual(MotionEngine.ForceCategory(force: 1.0), .slap)
    }

    // MARK: - Simulation

    func testSimulateForcePublishesEvent() {
        let expectation = XCTestExpectation(description: "Force event received")

        engine.forceEvent
            .sink { event in
                XCTAssertEqual(event.force, 0.5, accuracy: 0.01)
                XCTAssertEqual(event.category, .hit)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        engine.simulateForce(0.5)
        wait(for: [expectation], timeout: 1.0)
    }

    func testSimulateForceIncrementsCombo() {
        engine.simulateForce(0.5)
        XCTAssertEqual(engine.comboCount, 1)

        engine.simulateForce(0.5)
        XCTAssertEqual(engine.comboCount, 2)
    }

    // MARK: - Settings Integration

    func testForceThresholdScalesWithSensitivity() {
        let settings = SettingsManager()

        settings.sensitivity = 0.0
        XCTAssertGreaterThan(settings.forceThreshold, 0.4)

        settings.sensitivity = 1.0
        XCTAssertLessThan(settings.forceThreshold, 0.1)
    }
}
