import Foundation
import UIKit

/// Catalog of crash variants. Each entry is its own top-frame function so
/// bitdrift's crash issue grouper places them in distinct groups.
///
/// Rules for distinct grouping:
///  - Every crash needs a uniquely-named top-frame function, marked
///    `@inline(never)` so the optimiser cannot merge or inline them away in a
///    release build (the Android equivalent gets this for free from the JVM).
///  - Native signals must call `raise()` DIRECTLY — do not route them through a
///    shared helper, or they all group under the same frame.
///
/// This is the iOS analogue of `android/.../Crashes.kt`, not a transliteration:
/// Swift language traps, standard-library traps, and POSIX signals stand in for
/// the JVM exception types. Everything here is pure Swift — no Objective-C
/// runtime tricks (`NSException`, `perform(_:)`) are used to manufacture a crash.
enum Crashes {

    typealias Entry = (name: String, fire: () -> Void)

    /// Out-of-memory variants, each exercising a different allocation path or
    /// thread context so they land as distinct issue groups and cover different
    /// real-world OOM shapes.
    ///
    /// Note: iOS has no `OutOfMemoryError`. These end in a jetsam kill — the OS
    /// terminating the process under memory pressure — which bitdrift surfaces
    /// via out-of-memory / unexpected-termination detection rather than as a
    /// crash report with a stack. On the Simulator jetsam limits track the host
    /// machine, so these behave far more predictably on a physical device.
    private static let oomCrashes: [Entry] = [
        ("oom_allocator_thread", crashOomAllocatorThread),
        ("oom_main_thread", crashOomMainThread),
        ("oom_single_allocation", crashOomSingleAllocation),
        ("oom_thread_exhaustion", crashOomThreadExhaustion),
        ("oom_image_decode", crashOomImageDecode),
        ("oom_cache_growth", crashOomCacheGrowth),
    ]

    static let all: [Entry] = [
        // Main-thread Swift runtime traps — each trap kind is a distinct issue group
        ("force_unwrap_nil", crashForceUnwrapNil),
        ("array_index", crashArrayIndex),
        ("force_cast", crashForceCast),
        ("divide_by_zero", crashDivideByZero),
        ("number_format", crashNumberFormat),
        ("arithmetic_overflow", crashArithmeticOverflow),
        ("precondition_failure", crashPreconditionFailure),
        ("assertion_failure", crashAssertionFailure),
        ("fatal_error", crashFatalError),
        ("string_index", crashStringIndex),
        ("negative_array_size", crashNegativeArraySize),
        ("unowned_deallocated", crashUnownedDeallocated),
        ("stack_overflow", crashStackOverflow),
        // Standard-library traps — distinct failure sites from the language traps above
        ("dictionary_missing_key", crashDictionaryMissingKey),
        ("invalid_range", crashInvalidRange),
        ("decode_force_try", crashDecodeForceTry),
        // Off-main-thread — same failure, different stack and thread attribution
        ("background_queue", crashBackgroundQueue),
        ("detached_task", crashDetachedTask),
        // Lock contention — real, uncorrelated thread states across three threads
        ("lock_contention", crashLockContention),
        // Vendor SDK attribution — two distinct fake-vendor namespaces
        ("vendor_sdk_ads", crashVendorAdSDK),
        ("vendor_sdk_analytics", crashVendorAnalyticsSDK),
        // Watchdog terminations (0x8BADF00D, reported as App Hang) — the largest
        // class of real-world iOS crashes, and impossible to produce with a trap.
        // These arm a lifecycle hang rather than crashing inline; see WatchdogHangs.
        ("watchdog_scene_create", { WatchdogHangs.arm(.sceneCreate) }),
        ("watchdog_scene_update", { WatchdogHangs.arm(.sceneUpdate) }),
        ("watchdog_process_exit", { WatchdogHangs.arm(.processExit) }),
        // A genuine bad dereference, with a real fault address in the report —
        // unlike the raise()-based signals below, which carry none.
        ("exc_bad_access_null", crashExcBadAccessNull),
        // Native signals — each calls raise() directly so frames stay distinct
        ("native_sigsegv", crashNativeSigsegv),
        ("native_sigbus", crashNativeSigbus),
        ("native_sigabrt", crashNativeSigabrt),
        ("native_sigfpe", crashNativeSigfpe),
        ("native_sigill", crashNativeSigill),
    ] + oomCrashes

    /// Subset used by the "OOMs" crash-loop mode to cycle only memory crashes.
    /// Always available here, regardless of `ENABLE_OOM_CRASHES` — that flag only
    /// governs whether they appear in the *default* sweep.
    static let oomOnly: [Entry] = oomCrashes

    /// The default sweep. Excludes the memory variants unless explicitly enabled:
    /// each costs ~35s of blocked caller plus a 45s restart, so six of them turn a
    /// seconds-per-crash loop into minutes of apparently-hung app.
    static var defaultSweep: [Entry] {
        AppConfig.oomCrashesEnabled ? all : all.filter { !$0.name.hasPrefix("oom_") }
    }

    // MARK: - Combo indexing

    /// Combos per crash kind: foreground only, or foreground + background.
    ///
    /// Background crashes need an external actor to take the foreground first, so
    /// they are opt-in via `ENABLE_BACKGROUND_CRASHES` — see `AppConfig`.
    static var slotsPerCrash: Int { AppConfig.backgroundCrashesEnabled ? 2 : 1 }

    /// Decodes a persisted combo index into the crash it selects and which half
    /// of the sweep it belongs to.
    ///
    /// Centralised because the Welcome screen, the Advanced screen, and the
    /// simulator all decode this index. When they each did their own `/ 2` and
    /// `% 2` arithmetic, changing the number of slots would have quietly desynced
    /// the "next crash" the UI advertises from the one that actually fires.
    static func combo(atIndex index: Int, oomOnly useOomOnly: Bool)
        -> (name: String, fire: () -> Void, fireInBackground: Bool, totalCombos: Int) {
        let list = useOomOnly ? Crashes.oomOnly : Crashes.defaultSweep
        let slots = slotsPerCrash
        let total = max(list.count * slots, 1)
        let idx = ((index % total) + total) % total
        let entry = list[idx / slots]
        return (entry.name, entry.fire, slots > 1 && idx % slots == 1, total)
    }

    // MARK: - Main-thread Swift runtime traps

    @inline(never)
    private static func crashForceUnwrapNil() {
        let value: String? = opaque(nil)
        _ = value!.count
    }

    @inline(never)
    private static func crashArrayIndex() {
        let items = [Int](repeating: 0, count: 3)
        _ = items[opaque(99)]
    }

    @inline(never)
    private static func crashForceCast() {
        let any: Any = "not-a-number"
        _ = any as! Int
    }

    @inline(never)
    private static func crashDivideByZero() {
        let numerator = opaque(1)
        let denominator = opaque(0)
        _ = numerator / denominator
    }

    @inline(never)
    private static func crashNumberFormat() {
        _ = Int("not-a-number")!
    }

    @inline(never)
    private static func crashArithmeticOverflow() {
        var total = opaque(Int.max)
        total += opaque(1)
        _ = total
    }

    @inline(never)
    private static func crashPreconditionFailure() {
        precondition(opaque(false), "object in invalid state")
    }

    @inline(never)
    private static func crashAssertionFailure() {
        // `assert` is compiled out in release builds; `assertionFailure`'s
        // unconditional sibling keeps this crash present in both configurations.
        preconditionFailure("assertion failed in payment validator")
    }

    @inline(never)
    private static func crashFatalError() {
        fatalError("unrecoverable state in checkout coordinator")
    }

    @inline(never)
    private static func crashStringIndex() {
        let text = "hello"
        _ = text[text.index(text.startIndex, offsetBy: opaque(999))]
    }

    @inline(never)
    private static func crashNegativeArraySize() {
        _ = [Int](repeating: 0, count: opaque(-1))
    }

    private final class Owner { let label = "cart-session" }

    @inline(never)
    private static func crashUnownedDeallocated() {
        // Classic use-after-free shape in ARC: the referent is gone by the time
        // the unowned reference is read.
        var owner: Owner? = Owner()
        unowned let dangling = owner!
        owner = nil
        _ = dangling.label
    }

    @inline(never)
    private static func crashStackOverflow() {
        _ = infiniteRecurse(0)
    }

    @inline(never)
    private static func infiniteRecurse(_ n: Int) -> Int {
        // The unreachable base case exists only to keep the compiler's
        // infinite-recursion diagnostic quiet — `opaque` hides the condition, so
        // the recursion is every bit as unbounded at runtime.
        if opaque(false) { return n }
        return infiniteRecurse(n + 1) + 1
    }

    // MARK: - Standard-library traps

    @inline(never)
    private static func crashDictionaryMissingKey() {
        let inventory = ["prod_a1b2c3": 4, "prod_b2c3d4": 0]
        _ = inventory[opaque("prod_missing")]!
    }

    @inline(never)
    private static func crashInvalidRange() {
        // Forming a Range with upperBound < lowerBound traps at construction.
        _ = opaque(5)..<opaque(1)
    }

    private struct OrderReceipt: Decodable {
        let orderID: String
        let total: Double
    }

    @inline(never)
    private static func crashDecodeForceTry() {
        // `try!` on a payload that does not match the model — the shape of a real
        // crash from a backend response changing out from under a client.
        let payload = Data(#"{"orderID":"ORD-2026-00001"}"#.utf8)
        _ = try! JSONDecoder().decode(OrderReceipt.self, from: payload)
    }

    // MARK: - Off-main-thread

    @inline(never)
    private static func crashBackgroundQueue() {
        let queue = DispatchQueue(label: "ai.bitdrift.shop.worker-queue")
        queue.async {
            fatalError("unhandled failure on worker queue")
        }
        Thread.sleep(forTimeInterval: signalWait)
    }

    @inline(never)
    private static func crashDetachedTask() {
        Task.detached(priority: .utility) {
            preconditionFailure("illegal state in detached task")
        }
        Thread.sleep(forTimeInterval: signalWait)
    }

    // MARK: - Lock contention (three real, uncorrelated thread states)

    @inline(never)
    private static func crashLockContention() {
        let lock = NSLock()
        let holderReady = DispatchSemaphore(value: 0)

        // Holds the lock without crashing itself. Keeping "holds" and "crashes"
        // on separate threads means this thread is still genuinely blocked —
        // still holding `lock` — at snapshot time.
        let holder = Thread {
            lock.lock()
            holderReady.signal()
            Thread.sleep(forTimeInterval: lockHold)
            lock.unlock()
        }
        holder.name = "image-decode-thread"
        holder.start()
        holderReady.wait()

        // A watchdog thread, uninvolved in the lock itself, converts the block
        // into a crash after a short fixed delay — independent of `lockHold`, so
        // there is real margin against scheduler jitter rather than a race
        // against the same window the holder is using. Honest about what it is:
        // a synthetic stand-in for a hang, deliberately turned into a crash so it
        // lands in the crash-reporting pipeline.
        let watchdog = Thread {
            Thread.sleep(forTimeInterval: watchdogDelay)
            fatalError("hang-watchdog: main thread blocked on shared lock for \(Int(watchdogDelay * 1000))ms -- converting to a crash for reporting")
        }
        watchdog.name = "hang-watchdog-thread"
        watchdog.start()

        // Blocks the calling (main) thread on the same lock for the remainder of
        // image-decode-thread's hold window.
        lock.lock()
        lock.unlock()
    }

    // MARK: - Vendor SDK attribution

    @inline(never)
    private static func crashVendorAdSDK() {
        let url = URL(string: "https://ads.fake-vendor.example/init")!
        AdSDKFake.AdRequestInterceptor().intercept(url)
    }

    @inline(never)
    private static func crashVendorAnalyticsSDK() {
        let url = URL(string: "https://ping.fake-analytics.example/batch")!
        AnalyticsSDKFake.AnalyticsPingInterceptor().flushBatch(to: url)
    }

    // MARK: - Memory access faults

    /// A real bad dereference, rather than `raise(SIGSEGV)`.
    ///
    /// The distinction matters in a crash report: this produces a genuine
    /// `EXC_BAD_ACCESS` carrying the faulting address, which is what an engineer
    /// actually reads to work out *what* was dereferenced. A raised signal has no
    /// fault address at all — it only proves the signal handler works.
    ///
    /// Writes to a deliberately invalid low address rather than exactly 0, since
    /// `UnsafeMutableRawPointer(bitPattern: 0)` is nil and would trap as a Swift
    /// force-unwrap — a different crash entirely, and one already in the catalog.
    @inline(never)
    private static func crashExcBadAccessNull() {
        let pointer = UnsafeMutableRawPointer(bitPattern: opaque(0x10))!
        pointer.storeBytes(of: opaque(42), as: Int.self)
    }

    // MARK: - Native signals (no shared helper — distinct top frames)

    @inline(never)
    private static func crashNativeSigsegv() {
        let thread = Thread { Thread.sleep(forTimeInterval: 0.08); raise(SIGSEGV) }
        thread.name = "sig-sigsegv"
        thread.start()
        Thread.sleep(forTimeInterval: signalWait)
    }

    @inline(never)
    private static func crashNativeSigbus() {
        let thread = Thread { Thread.sleep(forTimeInterval: 0.08); raise(SIGBUS) }
        thread.name = "sig-sigbus"
        thread.start()
        Thread.sleep(forTimeInterval: signalWait)
    }

    @inline(never)
    private static func crashNativeSigabrt() {
        let thread = Thread { Thread.sleep(forTimeInterval: 0.08); raise(SIGABRT) }
        thread.name = "sig-sigabrt"
        thread.start()
        Thread.sleep(forTimeInterval: signalWait)
    }

    @inline(never)
    private static func crashNativeSigfpe() {
        let thread = Thread { Thread.sleep(forTimeInterval: 0.08); raise(SIGFPE) }
        thread.name = "sig-sigfpe"
        thread.start()
        Thread.sleep(forTimeInterval: signalWait)
    }

    @inline(never)
    private static func crashNativeSigill() {
        let thread = Thread { Thread.sleep(forTimeInterval: 0.08); raise(SIGILL) }
        thread.name = "sig-sigill"
        thread.start()
        Thread.sleep(forTimeInterval: signalWait)
    }

    // MARK: - OOM variants

    // A step delay is threaded through each gradual OOM loop so the climb takes
    // ~20–30s instead of well under a second. This is not "make it slower" for
    // its own sake: bitdrift's Resource Utilization panel is a periodic snapshot,
    // so a session that dies in under one capture interval never gets a sample,
    // and one that dies in ~5s gets a single point that reads as a flat line
    // rather than a graph. Pacing each loop across several capture ticks produces
    // an actual rising memory curve. `crashOomSingleAllocation` is deliberately
    // excluded — it represents the opposite case (one allocation failing at once)
    // and pacing it would destroy that contrast.

    /// Allocates and *touches* `bytes` so the pages are dirty and actually count
    /// against the process footprint. A plain `Data(count:)` can stay lazily
    /// mapped and never move the memory needle.
    private static func dirtyAllocate(_ bytes: Int) -> UnsafeMutableRawPointer {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 8)
        memset(pointer, 0xA5, bytes)
        return pointer
    }

    @inline(never)
    private static func crashOomAllocatorThread() {
        let thread = Thread {
            var sink: [UnsafeMutableRawPointer] = []
            while true {
                sink.append(dirtyAllocate(8 * 1024 * 1024))
                Thread.sleep(forTimeInterval: byteBufferStepDelay)
            }
        }
        thread.name = "oom-allocator"
        thread.start()
        Thread.sleep(forTimeInterval: oomGradualWait)
    }

    /// Same gradual accumulation as `crashOomAllocatorThread`, but on the calling
    /// (main) thread — different top frame and thread attribution.
    @inline(never)
    private static func crashOomMainThread() {
        var sink: [UnsafeMutableRawPointer] = []
        while true {
            sink.append(dirtyAllocate(8 * 1024 * 1024))
            Thread.sleep(forTimeInterval: byteBufferStepDelay)
        }
    }

    /// A single allocation far beyond what the OS will hand out, failing at once
    /// rather than by the "death of a thousand allocations" above. Deliberately
    /// not paced — see the note on the gradual loops.
    @inline(never)
    private static func crashOomSingleAllocation() {
        let giant = Int.max / 2
        _ = dirtyAllocate(giant)
    }

    /// Thread exhaustion rather than heap exhaustion: leaks threads (each parked
    /// forever, each with a large stack) until the OS refuses to create another.
    /// Common in real apps with a leaking thread pool.
    @inline(never)
    private static func crashOomThreadExhaustion() {
        let spawner = Thread {
            var leaked: [Thread] = []
            while true {
                let leakedThread = Thread { Thread.sleep(forTimeInterval: .greatestFiniteMagnitude) }
                leakedThread.name = "leaked-oom-thread"
                leakedThread.stackSize = 16 * 1024 * 1024
                leakedThread.start()
                leaked.append(leakedThread)
                Thread.sleep(forTimeInterval: threadSpawnStepDelay)
            }
        }
        spawner.name = "oom-thread-spawner"
        spawner.start()
        Thread.sleep(forTimeInterval: oomGradualWait)
    }

    /// Image buffers are one of the most common real-world memory sinks in
    /// image-heavy apps. Renders large bitmaps in a loop without releasing them,
    /// stressing the graphics allocation path rather than a plain byte buffer.
    @inline(never)
    private static func crashOomImageDecode() {
        let thread = Thread {
            var images: [UIImage] = []
            let size = CGSize(width: 4096, height: 4096) // ~64MB per image at 4 bytes/px
            while true {
                let renderer = UIGraphicsImageRenderer(size: size)
                images.append(renderer.image { context in
                    UIColor.systemPink.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                })
                Thread.sleep(forTimeInterval: imageStepDelay)
            }
        }
        thread.name = "oom-image-decode"
        thread.start()
        Thread.sleep(forTimeInterval: oomGradualWait)
    }

    /// Unbounded cache growth: many small string entries rather than a few large
    /// buffers. Representative of a real leak (an unbounded in-memory cache), and
    /// stresses the allocator with small, high-churn objects.
    ///
    /// Paced in batches rather than per-entry — these entries are cheap enough
    /// that a per-entry sleep would dominate wall time over actual allocation.
    @inline(never)
    private static func crashOomCacheGrowth() {
        let thread = Thread {
            var cache: [String: String] = [:]
            var i = 0
            while true {
                let key = "session-cache-key-\(i)"
                cache[key] = String(repeating: key, count: 64)
                i += 1
                if i % cacheGrowthBatchSize == 0 { Thread.sleep(forTimeInterval: cacheGrowthBatchDelay) }
            }
        }
        thread.name = "oom-cache-growth"
        thread.start()
        Thread.sleep(forTimeInterval: oomGradualWait)
    }

    // MARK: - Constants

    private static let signalWait: TimeInterval = 0.5
    private static let watchdogDelay: TimeInterval = 0.3  // fixed, independent of hold duration
    private static let lockHold: TimeInterval = 2.0       // wide margin vs. watchdogDelay

    /// How long the calling thread waits for a gradual OOM loop to actually kill
    /// the process before giving up and returning normally. Must stay under
    /// `SimulationManager.oomCrashRestartDelay` or the watchdog relaunches the
    /// still-alive app while the leaked thread keeps accumulating.
    static let oomGradualWait: TimeInterval = 35
    private static let byteBufferStepDelay: TimeInterval = 0.4
    private static let threadSpawnStepDelay: TimeInterval = 0.3
    private static let imageStepDelay: TimeInterval = 1.0
    private static let cacheGrowthBatchSize = 5_000
    private static let cacheGrowthBatchDelay: TimeInterval = 0.25

    /// Hides a constant from the optimiser so it cannot fold the trap away at
    /// compile time and turn the crash into dead code.
    @inline(never)
    private static func opaque<T>(_ value: T) -> T { value }
}
