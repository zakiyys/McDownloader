import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake while transfers are running, and releases the assertion
/// the moment they stop. The assertion is a real IOPMAssertion, not a shell call.
final class SleepGuard {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    func acquire() {
        guard !active else { return }
        let reason = "McDownloader is transferring files" as CFString
        let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertionID)
        if result == kIOReturnSuccess {
            active = true
            Log.info("sleep assertion acquired")
        }
    }

    func release() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        active = false
        Log.info("sleep assertion released")
    }

    deinit { release() }

    /// Puts the machine to sleep after the queue drains. Used by the
    /// "sleep when queue finishes" option, which the user turns on explicitly.
    static func scheduleSleepIfIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            Log.info("queue complete, requesting sleep")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
            try? process.run()
        }
    }
}
