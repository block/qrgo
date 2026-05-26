import XCTest
@testable import qrgo

@MainActor
final class MenuBarUpdateCoordinatorTests: XCTestCase {
    func testLaunchCheckStartsImmediately() async {
        let service = FakeMenuBarUpdateService(checkResults: [.current])
        let coordinator = makeCoordinator(service: service)

        coordinator.start()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)
        XCTAssertEqual(service.checkModes, [.passive])
    }

    func testDailyCheckDefersUntilScreenWakes() async {
        let service = FakeMenuBarUpdateService(checkResults: [.current, .current])
        let coordinator = makeCoordinator(service: service)

        coordinator.start()
        await drainTasks()
        coordinator.screenDidSleepForTesting()
        coordinator.dailyCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)

        coordinator.screenDidWakeForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 2)
        XCTAssertEqual(service.checkModes, [.passive, .refreshIfDue])
    }

    func testInitialRefreshDefersUntilIdle() async {
        var isIdle = false
        let service = FakeMenuBarUpdateService(checkResults: [.current, .current])
        let coordinator = makeCoordinator(
            service: service,
            isIdleProvider: { isIdle }
        )

        coordinator.start()
        await drainTasks()
        coordinator.initialRefreshCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkModes, [.passive])

        isIdle = true
        coordinator.idleStateDidChange()

        await waitForCheckModes([.passive, .refreshIfDue], in: service)
    }

    func testDailyCheckDefersUntilIdle() async {
        var isIdle = false
        let service = FakeMenuBarUpdateService(checkResults: [.current, .current])
        let coordinator = makeCoordinator(
            service: service,
            isIdleProvider: { isIdle }
        )

        coordinator.start()
        await drainTasks()
        coordinator.dailyCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)

        isIdle = true
        coordinator.idleStateDidChange()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 2)
        XCTAssertEqual(service.checkModes, [.passive, .refreshIfDue])
    }

    func testDailyCheckDefersUntilSessionBecomesActive() async {
        let service = FakeMenuBarUpdateService(checkResults: [.current, .current])
        let coordinator = makeCoordinator(service: service)

        coordinator.start()
        await drainTasks()
        coordinator.sessionDidResignActiveForTesting()
        coordinator.dailyCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)

        coordinator.sessionDidBecomeActiveForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 2)
        XCTAssertEqual(service.checkModes, [.passive, .refreshIfDue])
    }

    func testAvailableUpdateToastDefersUntilIdle() async {
        var isIdle = false
        let update = MenuBarUpdate(installedVersion: "1.0.0", currentVersion: "2.0.0")
        let service = FakeMenuBarUpdateService(checkResults: [.available(update)])
        var presentedUpdates: [MenuBarUpdate] = []
        let coordinator = makeCoordinator(
            service: service,
            isIdleProvider: { isIdle },
            presentUpdate: { presentedUpdates.append($0) }
        )

        coordinator.start()
        await drainTasks()

        XCTAssertTrue(presentedUpdates.isEmpty)

        isIdle = true
        coordinator.idleStateDidChange()
        await drainTasks()

        XCTAssertEqual(presentedUpdates, [update])
    }

    func testSameUpdateVersionIsNotPresentedTwice() async {
        let update = MenuBarUpdate(installedVersion: "1.0.0", currentVersion: "2.0.0")
        let service = FakeMenuBarUpdateService(checkResults: [
            .available(update),
            .available(update)
        ])
        var presentedUpdates: [MenuBarUpdate] = []
        let coordinator = makeCoordinator(
            service: service,
            presentUpdate: { presentedUpdates.append($0) }
        )

        coordinator.start()
        await drainTasks()
        coordinator.dailyCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 2)
        XCTAssertEqual(presentedUpdates, [update])
        XCTAssertEqual(service.checkModes, [.passive, .refreshIfDue])
    }

    func testOverlappingDailyCheckWaitsForLaunchCheckToFinish() async {
        let service = BlockingMenuBarUpdateService()
        let coordinator = makeCoordinator(service: service)
        let launchCheckStarted = service.expectCheckCount(1)

        coordinator.start()
        await fulfillment(of: [launchCheckStarted], timeout: 1)
        coordinator.dailyCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)

        let dailyCheckStarted = service.expectCheckCount(2)
        service.completeCheck(with: .current)
        await fulfillment(of: [dailyCheckStarted], timeout: 1)

        XCTAssertEqual(service.checkCount, 2)
        service.completeCheck(with: .current)
        await drainTasks()
        XCTAssertEqual(service.checkModes, [.passive, .refreshIfDue])
    }

    func testBackgroundRefreshCancelsWhenQRGoBecomesBusy() async {
        var isIdle = true
        let service = BlockingMenuBarUpdateService()
        let coordinator = makeCoordinator(
            service: service,
            isIdleProvider: { isIdle }
        )
        let refreshCheckStarted = service.expectCheckCount(1)

        coordinator.initialRefreshCheckBecameDueForTesting()
        await fulfillment(of: [refreshCheckStarted], timeout: 1)

        XCTAssertEqual(service.checkModes, [.refreshIfDue])

        isIdle = false
        coordinator.idleStateDidChange()
        await drainTasks()
        service.completeCheck(with: .current)
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)

        isIdle = true
        coordinator.idleStateDidChange()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)

        let nextScheduledRefreshStarted = service.expectCheckCount(2)
        coordinator.dailyCheckBecameDueForTesting()
        await fulfillment(of: [nextScheduledRefreshStarted], timeout: 1)

        XCTAssertEqual(service.checkModes, [.refreshIfDue, .refreshIfDue])
    }

    func testBackgroundRefreshCancelsWhenScreenSleeps() async {
        let service = BlockingMenuBarUpdateService()
        let coordinator = makeCoordinator(service: service)
        let firstRefreshCheckStarted = service.expectCheckCount(1)

        coordinator.initialRefreshCheckBecameDueForTesting()
        await fulfillment(of: [firstRefreshCheckStarted], timeout: 1)
        coordinator.screenDidSleepForTesting()
        await drainTasks()
        service.completeCheck(with: .current)
        await drainTasks()

        XCTAssertEqual(service.checkModes, [.refreshIfDue])

        coordinator.screenDidWakeForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkModes, [.refreshIfDue])

        let nextScheduledRefreshStarted = service.expectCheckCount(2)
        coordinator.dailyCheckBecameDueForTesting()
        await fulfillment(of: [nextScheduledRefreshStarted], timeout: 1)

        XCTAssertEqual(service.checkModes, [.refreshIfDue, .refreshIfDue])
    }

    func testBackgroundRefreshCancelsWhenSessionResignsActive() async {
        let service = BlockingMenuBarUpdateService()
        let coordinator = makeCoordinator(service: service)
        let firstRefreshCheckStarted = service.expectCheckCount(1)

        coordinator.initialRefreshCheckBecameDueForTesting()
        await fulfillment(of: [firstRefreshCheckStarted], timeout: 1)
        coordinator.sessionDidResignActiveForTesting()
        await drainTasks()
        service.completeCheck(with: .current)
        await drainTasks()

        XCTAssertEqual(service.checkModes, [.refreshIfDue])

        coordinator.sessionDidBecomeActiveForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkModes, [.refreshIfDue])

        let nextScheduledRefreshStarted = service.expectCheckCount(2)
        coordinator.dailyCheckBecameDueForTesting()
        await fulfillment(of: [nextScheduledRefreshStarted], timeout: 1)

        XCTAssertEqual(service.checkModes, [.refreshIfDue, .refreshIfDue])
    }

    func testTerminationCancelsBackgroundRefreshWithoutDeferring() async {
        let service = BlockingMenuBarUpdateService()
        let coordinator = makeCoordinator(service: service)
        let refreshCheckStarted = service.expectCheckCount(1)

        coordinator.initialRefreshCheckBecameDueForTesting()
        await fulfillment(of: [refreshCheckStarted], timeout: 1)
        coordinator.cancelBackgroundChecksForTermination()
        service.completeCheck(with: .current)
        await drainTasks()
        coordinator.screenDidWakeForTesting()
        coordinator.sessionDidBecomeActiveForTesting()
        coordinator.idleStateDidChange()
        await drainTasks()

        XCTAssertEqual(service.checkModes, [.refreshIfDue])
    }

    func testTerminationCancelsPassiveLaunchCheckWithoutDeferring() async {
        let service = BlockingMenuBarUpdateService()
        let coordinator = makeCoordinator(service: service)
        let launchCheckStarted = service.expectCheckCount(1)

        coordinator.start()
        await fulfillment(of: [launchCheckStarted], timeout: 1)
        coordinator.cancelBackgroundChecksForTermination()
        service.completeCheck(with: .current)
        await drainTasks()
        coordinator.screenDidWakeForTesting()
        coordinator.sessionDidBecomeActiveForTesting()
        coordinator.idleStateDidChange()
        await drainTasks()

        XCTAssertEqual(service.checkModes, [.passive])
    }
}

@MainActor
final class MenuBarUpdateCoordinatorInstallTests: XCTestCase {
    func testExplicitInstallIsNotCancelledByIdleScreenOrSessionChanges() async {
        var isIdle = true
        let service = BlockingInstallMenuBarUpdateService()
        let coordinator = makeCoordinator(
            service: service,
            isIdleProvider: { isIdle }
        )
        let installStarted = service.expectInstallCount(1)

        let installTask = Task {
            await coordinator.installUpdate()
        }
        await fulfillment(of: [installStarted], timeout: 1)

        isIdle = false
        coordinator.idleStateDidChange()
        coordinator.screenDidSleepForTesting()
        coordinator.sessionDidResignActiveForTesting()
        await drainTasks()
        service.completeInstall(with: .installed)

        let result = await installTask.value

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(service.installCount, 1)
    }

    func testDailyCheckDefersWhileExplicitInstallIsRunning() async {
        let service = BlockingInstallMenuBarUpdateService()
        let coordinator = makeCoordinator(service: service)
        let installStarted = service.expectInstallCount(1)

        let installTask = Task {
            await coordinator.installUpdate()
        }
        await fulfillment(of: [installStarted], timeout: 1)

        coordinator.dailyCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertTrue(service.checkModes.isEmpty)

        service.completeInstall(with: .installed)
        let result = await installTask.value
        await drainTasks()

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(service.checkModes, [.refreshIfDue])
    }

    func testSuccessfulInstallRestoresLaunchAtLoginIfUpgradeRemovedIt() async {
        let service = FakeMenuBarUpdateService(checkResults: [], installResults: [.installed])
        var loginItemChecks = [true, false]
        var restoreCount = 0
        let coordinator = makeCoordinator(
            service: service,
            isLoginItemInstalled: { loginItemChecks.removeFirst() },
            installLoginItem: {
                restoreCount += 1
                return true
            }
        )

        let result = await coordinator.installUpdate()

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(service.installCount, 1)
        XCTAssertEqual(restoreCount, 1)
    }

    func testFailedInstallDoesNotRestoreLaunchAtLogin() async {
        let error = MenuBarUpdateCommandError(message: "Install failed.", details: "", timedOut: false)
        let service = FakeMenuBarUpdateService(checkResults: [], installResults: [.failed(error)])
        var restoreCount = 0
        let coordinator = makeCoordinator(
            service: service,
            isLoginItemInstalled: { true },
            installLoginItem: {
                restoreCount += 1
                return true
            }
        )

        let result = await coordinator.installUpdate()

        XCTAssertEqual(result, .failed(error))
        XCTAssertEqual(service.installCount, 1)
        XCTAssertEqual(restoreCount, 0)
    }

    func testHomebrewInstallRefusesToRunWhenCurrentProcessIsManagedByLoginItem() async {
        let service = FakeMenuBarUpdateService(
            checkResults: [],
            installResults: [.installed],
            mayUnloadLaunchAgentDuringInstall: true
        )
        let coordinator = makeCoordinator(
            service: service,
            isCurrentProcessManagedByLoginItem: { true }
        )

        let result = await coordinator.installUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed install result.")
        }
        XCTAssertEqual(
            error.message,
            "QRGo was started at login. Quit QRGo, open it from Applications, then retry the update."
        )
        XCTAssertEqual(service.installCount, 0)
    }
}

@MainActor
private func makeCoordinator(
    service: MenuBarUpdateServicing,
    isIdleProvider: @escaping () -> Bool = { true },
    presentUpdate: @escaping (MenuBarUpdate) -> Void = { _ in },
    isLoginItemInstalled: @escaping () -> Bool = { false },
    isCurrentProcessManagedByLoginItem: @escaping () -> Bool = { false },
    installLoginItem: @escaping () -> Bool = { true }
) -> MenuBarUpdateCoordinator {
    let coordinator = MenuBarUpdateCoordinator(
        service: service,
        initialRefreshDelay: 1_000,
        dailyInterval: 1_000,
        isIdleProvider: isIdleProvider,
        presentUpdate: presentUpdate,
        log: { _ in },
        logError: { _ in },
        isLoginItemInstalled: isLoginItemInstalled,
        isCurrentProcessManagedByLoginItem: isCurrentProcessManagedByLoginItem,
        installLoginItem: installLoginItem
    )
    coordinator.sessionDidBecomeActiveForTesting()
    return coordinator
}

private func drainTasks() async {
    for _ in 0..<20 {
        await Task.yield()
    }
}

@MainActor
private func waitForCheckModes(
    _ expectedModes: [MenuBarUpdateCheckMode],
    in service: FakeMenuBarUpdateService,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 where service.checkModes != expectedModes {
        await Task.yield()
    }
    XCTAssertEqual(service.checkModes, expectedModes, file: file, line: line)
}

private final class FakeMenuBarUpdateService: MenuBarUpdateServicing {
    private var checkResults: [MenuBarUpdateCheckResult]
    private var installResults: [MenuBarUpdateInstallResult]
    let mayUnloadLaunchAgentDuringInstall: Bool
    private(set) var checkCount = 0
    private(set) var installCount = 0
    private(set) var checkModes: [MenuBarUpdateCheckMode] = []

    init(
        checkResults: [MenuBarUpdateCheckResult],
        installResults: [MenuBarUpdateInstallResult] = [.installed],
        mayUnloadLaunchAgentDuringInstall: Bool = false
    ) {
        self.checkResults = checkResults
        self.installResults = installResults
        self.mayUnloadLaunchAgentDuringInstall = mayUnloadLaunchAgentDuringInstall
    }

    func checkForUpdate(mode: MenuBarUpdateCheckMode) async -> MenuBarUpdateCheckResult {
        checkCount += 1
        checkModes.append(mode)
        if checkResults.isEmpty {
            return .current
        }
        return checkResults.removeFirst()
    }

    func installUpdate() async -> MenuBarUpdateInstallResult {
        installCount += 1
        if installResults.isEmpty {
            return .installed
        }
        return installResults.removeFirst()
    }
}

private final class BlockingMenuBarUpdateService: MenuBarUpdateServicing {
    private var continuation: CheckedContinuation<MenuBarUpdateCheckResult, Never>?
    private var checkCountExpectations: [(Int, XCTestExpectation)] = []
    private(set) var checkCount = 0
    private(set) var checkModes: [MenuBarUpdateCheckMode] = []

    func checkForUpdate(mode: MenuBarUpdateCheckMode) async -> MenuBarUpdateCheckResult {
        checkCount += 1
        checkModes.append(mode)
        fulfillSatisfiedCheckCountExpectations()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func installUpdate() async -> MenuBarUpdateInstallResult {
        .installed
    }

    func completeCheck(with result: MenuBarUpdateCheckResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func expectCheckCount(_ expectedCount: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Check count reaches \(expectedCount)")
        if checkCount >= expectedCount {
            expectation.fulfill()
        } else {
            checkCountExpectations.append((expectedCount, expectation))
        }
        return expectation
    }

    private func fulfillSatisfiedCheckCountExpectations() {
        var pendingExpectations: [(Int, XCTestExpectation)] = []
        for (expectedCount, expectation) in checkCountExpectations {
            if checkCount >= expectedCount {
                expectation.fulfill()
            } else {
                pendingExpectations.append((expectedCount, expectation))
            }
        }
        checkCountExpectations = pendingExpectations
    }
}

private final class BlockingInstallMenuBarUpdateService: MenuBarUpdateServicing {
    private var continuation: CheckedContinuation<MenuBarUpdateInstallResult, Never>?
    private var installCountExpectations: [(Int, XCTestExpectation)] = []
    private(set) var installCount = 0
    private(set) var checkModes: [MenuBarUpdateCheckMode] = []

    func checkForUpdate(mode: MenuBarUpdateCheckMode) async -> MenuBarUpdateCheckResult {
        checkModes.append(mode)
        return .current
    }

    func installUpdate() async -> MenuBarUpdateInstallResult {
        installCount += 1
        fulfillSatisfiedInstallCountExpectations()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func completeInstall(with result: MenuBarUpdateInstallResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func expectInstallCount(_ expectedCount: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Install count reaches \(expectedCount)")
        if installCount >= expectedCount {
            expectation.fulfill()
        } else {
            installCountExpectations.append((expectedCount, expectation))
        }
        return expectation
    }

    private func fulfillSatisfiedInstallCountExpectations() {
        var pendingExpectations: [(Int, XCTestExpectation)] = []
        for (expectedCount, expectation) in installCountExpectations {
            if installCount >= expectedCount {
                expectation.fulfill()
            } else {
                pendingExpectations.append((expectedCount, expectation))
            }
        }
        installCountExpectations = pendingExpectations
    }
}
