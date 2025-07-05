import Foundation
import SystemConfiguration

// MARK: - Performance Metrics Data Structures

struct PerformanceMetric {
    let name: String
    let value: Double
    let unit: MetricUnit
    let timestamp: Date
    let context: [String: Any]?
    
    enum MetricUnit: String, CaseIterable {
        case milliseconds = "ms"
        case seconds = "s"
        case bytes = "bytes"
        case count = "count"
        case percentage = "%"
        case ratio = "ratio"
    }
}

struct OperationTiming {
    let operationName: String
    let startTime: CFAbsoluteTime
    let duration: TimeInterval
    let success: Bool
    let context: [String: Any]?
    
    var metric: PerformanceMetric {
        return PerformanceMetric(
            name: "operation.\(operationName).duration",
            value: duration * 1000, // Convert to milliseconds
            unit: .milliseconds,
            timestamp: Date(),
            context: context
        )
    }
}

struct MemorySnapshot {
    let timestamp: Date
    let physicalMemory: UInt64
    let virtualMemory: UInt64
    let peakMemory: UInt64
    let availableMemory: UInt64
    
    var metrics: [PerformanceMetric] {
        return [
            PerformanceMetric(name: "memory.physical", value: Double(physicalMemory), unit: .bytes, timestamp: timestamp, context: nil),
            PerformanceMetric(name: "memory.virtual", value: Double(virtualMemory), unit: .bytes, timestamp: timestamp, context: nil),
            PerformanceMetric(name: "memory.peak", value: Double(peakMemory), unit: .bytes, timestamp: timestamp, context: nil),
            PerformanceMetric(name: "memory.available", value: Double(availableMemory), unit: .bytes, timestamp: timestamp, context: nil)
        ]
    }
}

// MARK: - Performance Timer

class PerformanceTimer {
    private let operationName: String
    private let startTime: CFAbsoluteTime
    private var context: [String: Any] = [:]
    
    init(operationName: String) {
        self.operationName = operationName
        self.startTime = CFAbsoluteTimeGetCurrent()
        Logger.debug("⏱️ Started timing: \(operationName)")
    }
    
    func addContext(_ key: String, _ value: Any) {
        context[key] = value
    }
    
    func finish(success: Bool = true) -> OperationTiming {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let timing = OperationTiming(
            operationName: operationName,
            startTime: startTime,
            duration: duration,
            success: success,
            context: context.isEmpty ? nil : context
        )
        
        Logger.debug("⏱️ Finished timing: \(operationName) - \(String(format: "%.2f", duration * 1000))ms (success: \(success))")
        PerformanceTelemetry.shared.recordTiming(timing)
        return timing
    }
}

// MARK: - Performance Telemetry Manager

class PerformanceTelemetry {
    static let shared = PerformanceTelemetry()
    
    private init() {
        setupPeriodicCollection()
        Logger.info("PerformanceTelemetry initialized with \(config.maxMetrics) metric buffer")
    }
    
    // MARK: - Configuration
    
    private struct TelemetryConfig {
        let enabled: Bool = true
        let maxMetrics: Int = 1000
        let collectionInterval: TimeInterval = 60.0 // 1 minute
        let memorySnapshotInterval: TimeInterval = 300.0 // 5 minutes
        let batchSize: Int = 50
        let compressionThreshold: Int = 500
    }
    
    private let config = TelemetryConfig()
    
    // MARK: - Storage
    
    private var metrics: [PerformanceMetric] = []
    private var operationTimings: [OperationTiming] = []
    private var memorySnapshots: [MemorySnapshot] = []
    private let metricsQueue = DispatchQueue(label: "performanceTelemetry", qos: .utility)
    
    // MARK: - System Information
    
    private lazy var deviceInfo: [String: Any] = {
        var info: [String: Any] = [:]
        
        // macOS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        info["os_version"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        
        // Hardware info
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        info["hardware_model"] = String(cString: model)
        
        // Memory info
        var memsize: UInt64 = 0
        size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memsize, &size, nil, 0)
        info["total_memory"] = memsize
        
        return info
    }()
    
    // MARK: - Public API
    
    /// Record a performance metric
    func recordMetric(_ metric: PerformanceMetric) {
        guard config.enabled else { return }
        
        metricsQueue.async {
            self.metrics.append(metric)
            self.enforceStorageLimits()
        }
    }
    
    /// Record operation timing
    func recordTiming(_ timing: OperationTiming) {
        guard config.enabled else { return }
        
        metricsQueue.async {
            self.operationTimings.append(timing)
            self.recordMetric(timing.metric)
            self.enforceStorageLimits()
        }
    }
    
    /// Start timing an operation
    func startTiming(_ operationName: String) -> PerformanceTimer {
        return PerformanceTimer(operationName: operationName)
    }
    
    /// Record a simple counter metric
    func recordCounter(_ name: String, value: Double = 1.0, context: [String: Any]? = nil) {
        let metric = PerformanceMetric(
            name: name,
            value: value,
            unit: .count,
            timestamp: Date(),
            context: context
        )
        recordMetric(metric)
    }
    
    /// Record a duration metric in milliseconds
    func recordDuration(_ name: String, milliseconds: Double, context: [String: Any]? = nil) {
        let metric = PerformanceMetric(
            name: name,
            value: milliseconds,
            unit: .milliseconds,
            timestamp: Date(),
            context: context
        )
        recordMetric(metric)
    }
    
    /// Record a size metric in bytes
    func recordSize(_ name: String, bytes: UInt64, context: [String: Any]? = nil) {
        let metric = PerformanceMetric(
            name: name,
            value: Double(bytes),
            unit: .bytes,
            timestamp: Date(),
            context: context
        )
        recordMetric(metric)
    }
    
    /// Record authentication cache performance
    func recordAuthCacheHit(_ hit: Bool) {
        recordCounter("auth.cache.\(hit ? "hit" : "miss")")
    }
    
    /// Get performance summary for the last interval
    func getPerformanceSummary(interval: TimeInterval = 300) -> [String: Any] {
        return metricsQueue.sync {
            let cutoffTime = Date().addingTimeInterval(-interval)
            let recentMetrics = metrics.filter { $0.timestamp >= cutoffTime }
            
            var summary: [String: Any] = [:]
            summary["device_info"] = deviceInfo
            summary["collection_time"] = Date()
            summary["interval_seconds"] = interval
            summary["total_metrics"] = recentMetrics.count
            
            // Group metrics by operation
            let groupedMetrics = Dictionary(grouping: recentMetrics) { $0.name }
            var operationStats: [String: [String: Any]] = [:]
            
            for (name, metrics) in groupedMetrics {
                let values = metrics.map { $0.value }
                let avg = values.reduce(0, +) / Double(values.count)
                let min = values.min() ?? 0
                let max = values.max() ?? 0
                
                operationStats[name] = [
                    "count": values.count,
                    "average": avg,
                    "min": min,
                    "max": max,
                    "unit": metrics.first?.unit.rawValue ?? "unknown"
                ]
            }
            
            summary["operations"] = operationStats
            
            // Recent timings summary
            let recentTimings = operationTimings.filter { Date(timeIntervalSinceReferenceDate: $0.startTime) >= cutoffTime }
            let successRate = recentTimings.isEmpty ? 1.0 : Double(recentTimings.filter { $0.success }.count) / Double(recentTimings.count)
            
            summary["success_rate"] = successRate
            summary["total_operations"] = recentTimings.count
            
            return summary
        }
    }
    
    /// Get critical performance indicators
    func getCriticalMetrics() -> [String: Double] {
        return metricsQueue.sync {
            var critical: [String: Double] = [:]
            
            // Authentication performance
            let authMetrics = metrics.suffix(100).filter { $0.name.hasPrefix("auth.") }
            let authCacheHits = authMetrics.filter { $0.name.contains("cache.hit") }.count
            let authCacheMisses = authMetrics.filter { $0.name.contains("cache.miss") }.count
            let totalAuthOperations = authCacheHits + authCacheMisses
            
            if totalAuthOperations > 0 {
                critical["auth_cache_hit_rate"] = Double(authCacheHits) / Double(totalAuthOperations)
            }
            
            // Translation performance
            let translationTimings = operationTimings.suffix(50).filter { $0.operationName.contains("translation") }
            if !translationTimings.isEmpty {
                let avgDuration = translationTimings.map { $0.duration }.reduce(0, +) / Double(translationTimings.count)
                critical["avg_translation_time_ms"] = avgDuration * 1000
                
                let successCount = translationTimings.filter { $0.success }.count
                critical["translation_success_rate"] = Double(successCount) / Double(translationTimings.count)
            }
            
            // Memory usage
            if let lastSnapshot = memorySnapshots.last {
                critical["memory_usage_mb"] = Double(lastSnapshot.physicalMemory) / (1024 * 1024)
                critical["memory_available_mb"] = Double(lastSnapshot.availableMemory) / (1024 * 1024)
            }
            
            // Stream processing
            let streamMetrics = metrics.suffix(100).filter { $0.name.contains("stream") }
            if !streamMetrics.isEmpty {
                let avgBufferUtilization = streamMetrics.compactMap { $0.name.contains("buffer") ? $0.value : nil }.reduce(0, +) / Double(streamMetrics.count)
                critical["stream_buffer_utilization"] = avgBufferUtilization
            }
            
            return critical
        }
    }
    
    // MARK: - Periodic Collection
    
    private func setupPeriodicCollection() {
        // Memory snapshot collection
        Timer.scheduledTimer(withTimeInterval: config.memorySnapshotInterval, repeats: true) { [weak self] _ in
            self?.collectMemorySnapshot()
        }
        
        // Performance summary logging
        Timer.scheduledTimer(withTimeInterval: config.collectionInterval, repeats: true) { [weak self] _ in
            self?.logPerformanceSummary()
        }
        
        Logger.info("PerformanceTelemetry: Periodic collection started (memory: \(config.memorySnapshotInterval)s, summary: \(config.collectionInterval)s)")
    }
    
    private func collectMemorySnapshot() {
        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            Logger.warn("PerformanceTelemetry: Failed to get memory info")
            return
        }
        
        // Get system memory info
        var vmStats = vm_statistics64()
        var vmStatsCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let vmResult = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmStatsCount)
            }
        }
        
        let pageSize = vm_kernel_page_size
        let availableMemory = vmResult == KERN_SUCCESS ? UInt64(vmStats.free_count) * UInt64(pageSize) : 0
        
        let snapshot = MemorySnapshot(
            timestamp: Date(),
            physicalMemory: UInt64(info.resident_size),
            virtualMemory: UInt64(info.virtual_size),
            peakMemory: UInt64(info.resident_size_max),
            availableMemory: availableMemory
        )
        
        metricsQueue.async {
            self.memorySnapshots.append(snapshot)
            
            // Record memory metrics
            for metric in snapshot.metrics {
                self.recordMetric(metric)
            }
            
            // Keep only recent snapshots
            let cutoffTime = Date().addingTimeInterval(-3600) // 1 hour
            self.memorySnapshots.removeAll { $0.timestamp < cutoffTime }
        }
        
        Logger.debug("PerformanceTelemetry: Memory snapshot - Physical: \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.physicalMemory), countStyle: .binary))")
    }
    
    private func logPerformanceSummary() {
        let summary = getPerformanceSummary()
        let critical = getCriticalMetrics()
        
        Logger.info("📊 Performance Summary:")
        Logger.info("  - Total metrics: \(summary["total_metrics"] ?? 0)")
        Logger.info("  - Total operations: \(summary["total_operations"] ?? 0)")
        Logger.info("  - Success rate: \(String(format: "%.1f", (summary["success_rate"] as? Double ?? 0) * 100))%")
        
        if let authCacheHitRate = critical["auth_cache_hit_rate"] {
            Logger.info("  - Auth cache hit rate: \(String(format: "%.1f", authCacheHitRate * 100))%")
        }
        
        if let avgTranslationTime = critical["avg_translation_time_ms"] {
            Logger.info("  - Avg translation time: \(String(format: "%.0f", avgTranslationTime))ms")
        }
        
        if let memoryUsage = critical["memory_usage_mb"] {
            Logger.info("  - Memory usage: \(String(format: "%.1f", memoryUsage))MB")
        }
    }
    
    // MARK: - Storage Management
    
    private func enforceStorageLimits() {
        // Enforce metric limits
        if metrics.count > config.maxMetrics {
            let excess = metrics.count - config.compressionThreshold
            metrics.removeFirst(excess)
        }
        
        // Enforce timing limits
        if operationTimings.count > config.maxMetrics {
            let excess = operationTimings.count - config.compressionThreshold
            operationTimings.removeFirst(excess)
        }
    }
}

// MARK: - Convenience Functions

extension PerformanceTelemetry {
    /// Time a block of code
    func time<T>(_ operationName: String, operation: () throws -> T) rethrows -> T {
        let timer = startTiming(operationName)
        do {
            let result = try operation()
            timer.finish(success: true)
            return result
        } catch {
            timer.finish(success: false)
            throw error
        }
    }
    
    /// Time an async operation
    func timeAsync<T>(_ operationName: String, operation: () async throws -> T) async rethrows -> T {
        let timer = startTiming(operationName)
        do {
            let result = try await operation()
            timer.finish(success: true)
            return result
        } catch {
            timer.finish(success: false)
            throw error
        }
    }
}

// MARK: - Global Convenience Functions

/// Time a synchronous operation
func measurePerformance<T>(_ operationName: String, operation: () throws -> T) rethrows -> T {
    return try PerformanceTelemetry.shared.time(operationName, operation: operation)
}

/// Record a simple performance counter
func recordPerformanceCounter(_ name: String, value: Double = 1.0) {
    PerformanceTelemetry.shared.recordCounter(name, value: value)
}

/// Record a duration in milliseconds
func recordPerformanceDuration(_ name: String, milliseconds: Double) {
    PerformanceTelemetry.shared.recordDuration(name, milliseconds: milliseconds)
}