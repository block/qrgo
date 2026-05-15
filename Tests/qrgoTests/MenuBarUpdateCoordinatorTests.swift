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
    }

    func testOverlappingDailyCheckWaitsForLaunchCheckToFinish() async {
        let service = BlockingMenuBarUpdateService()
        let coordinator = makeCoordinator(service: service)

        coordinator.start()
        await drainTasks()
        coordinator.dailyCheckBecameDueForTesting()
        await drainTasks()

        XCTAssertEqual(service.checkCount, 1)

        service.completeCheck(with: .current)
        await drainTasks()

        XCTAssertEqual(service.checkCount, 2)
        service.completeCheck(with: .current)
        await drainTasks()
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

    private func makeCoordinator(
        service: MenuBarUpdateServicing,
        isIdleProvider: @escaping () -> Bool = { true },
        presentUpdate: @escaping (MenuBarUpdate) -> Void = { _ in },
        isLoginItemInstalled: @escaping () -> Bool = { false },
        isCurrentProcessManagedByLoginItem: @escaping () -> Bool = { false },
        installLoginItem: @escaping () -> Bool = { true }
    ) -> MenuBarUpdateCoordinator {
        MenuBarUpdateCoordinator(
            service: service,
            dailyInterval: 1_000,
            isIdleProvider: isIdleProvider,
            presentUpdate: presentUpdate,
            log: { _ in },
            logError: { _ in },
            isLoginItemInstalled: isLoginItemInstalled,
            isCurrentProcessManagedByLoginItem: isCurrentProcessManagedByLoginItem,
            installLoginItem: installLoginItem
        )
    }

    private func drainTasks() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}

private final class FakeMenuBarUpdateService: MenuBarUpdateServicing {
    private var checkResults: [MenuBarUpdateCheckResult]
    private var installResults: [MenuBarUpdateInstallResult]
    let mayUnloadLaunchAgentDuringInstall: Bool
    private(set) var checkCount = 0
    private(set) var installCount = 0

    init(
        checkResults: [MenuBarUpdateCheckResult],
        installResults: [MenuBarUpdateInstallResult] = [.installed],
        mayUnloadLaunchAgentDuringInstall: Bool = false
    ) {
        self.checkResults = checkResults
        self.installResults = installResults
        self.mayUnloadLaunchAgentDuringInstall = mayUnloadLaunchAgentDuringInstall
    }

    func checkForUpdate() async -> MenuBarUpdateCheckResult {
        checkCount += 1
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
    private(set) var checkCount = 0

    func checkForUpdate() async -> MenuBarUpdateCheckResult {
        checkCount += 1
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
}
