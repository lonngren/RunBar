import Foundation
import Darwin

/// Samples *system-wide* CPU utilisation on macOS.
///
/// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` hands back a buffer of cumulative
/// per-core tick counters laid out as `[user, system, idle, nice]` per core. We
/// diff two consecutive reads, which yields the same utilisation figure `top`
/// reports.
///
/// The kernel allocates that buffer inside our task, so it has to be released
/// again — otherwise a sampler running at 4 Hz leaks a page every 250 ms.
final class SystemCPUSampler {

    /// Number of tick counters per core: user, system, idle, nice.
    private static let ticksPerCore = 4

    private var previous: [UInt64] = []
    private var hasBaseline = false

    /// Current utilisation across every core, `0...1`.
    func sample() -> Double {
        guard let ticks = readTicks() else { return 0 }
        defer {
            previous = ticks
            hasBaseline = true
        }
        guard hasBaseline, previous.count == ticks.count, previous.count >= 4 else { return 0 }

        var totalDelta: UInt64 = 0
        var idleDelta: UInt64 = 0
        for i in stride(from: 0, to: ticks.count, by: Self.ticksPerCore) {
            let now = ticks[i] &+ ticks[i + 1] &+ ticks[i + 2] &+ ticks[i + 3]
            let before = previous[i] &+ previous[i + 1] &+ previous[i + 2] &+ previous[i + 3]
            totalDelta &+= now &- before
            idleDelta &+= ticks[i + 2] &- previous[i + 2]
        }
        guard totalDelta > 0 else { return 0 }
        return min(1, max(0, Double(totalDelta - idleDelta) / Double(totalDelta)))
    }

    /// Flattens the kernel buffer into `[user, system, idle, nice]` per core.
    private func readTicks() -> [UInt64]? {
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &info,
            &infoCount
        )
        guard kr == KERN_SUCCESS, let info else { return nil }

        let loadInfo = UnsafeRawPointer(info).assumingMemoryBound(to: processor_cpu_load_info.self)
        let coreCount = Int(infoCount) / Self.ticksPerCore

        var ticks: [UInt64] = []
        ticks.reserveCapacity(coreCount * Self.ticksPerCore)
        for i in 0..<coreCount {
            let counter = loadInfo[i].cpu_ticks
            ticks.append(UInt64(counter.0))
            ticks.append(UInt64(counter.1))
            ticks.append(UInt64(counter.2))
            ticks.append(UInt64(counter.3))
        }

        release(info, infoCount: infoCount)
        return ticks
    }

    /// Frees the page-aligned block the kernel allocated for us.
    private func release(_ info: processor_info_array_t, infoCount: mach_msg_type_number_t) {
        var pageSize = vm_size_t(0)
        if host_page_size(mach_host_self(), &pageSize) != KERN_SUCCESS || pageSize == 0 {
            pageSize = 4096
        }
        // The kernel rounds its allocation up to a whole page.
        let bytes = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
        let size = ((bytes + pageSize - 1) / pageSize) * pageSize
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
    }
}
