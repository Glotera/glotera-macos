import Foundation

// MARK: - Lock-Free Circular Buffer for Stream Processing

/// High-performance lock-free circular buffer for streaming data processing
class LockFreeCircularBuffer {
    private let capacity: Int
    private var buffer: [StreamChunk]
    private var writeIndex = 0
    private var readIndex = 0
    private let indexQueue = DispatchQueue(label: "circularBuffer.index", qos: .userInteractive)
    
    init(capacity: Int = 256) {
        self.capacity = capacity
        self.buffer = Array(repeating: StreamChunk.empty, count: capacity)
        Logger.debug("LockFreeCircularBuffer initialized with capacity: \(capacity)")
    }
    
    /// Write data to buffer (lock-free, single writer)
    func write(_ chunk: StreamChunk) -> Bool {
        let nextWriteIndex = (writeIndex + 1) % capacity
        
        // Check if buffer is full
        if nextWriteIndex == readIndex {
            Logger.warn("StreamBuffer: Buffer overflow, dropping chunk")
            return false
        }
        
        buffer[writeIndex] = chunk
        writeIndex = nextWriteIndex
        return true
    }
    
    /// Read all available chunks (lock-free batch read)
    func readBatch() -> [StreamChunk] {
        var chunks: [StreamChunk] = []
        
        while readIndex != writeIndex {
            let chunk = buffer[readIndex]
            chunks.append(chunk)
            readIndex = (readIndex + 1) % capacity
        }
        
        return chunks
    }
    
    /// Get current buffer utilization for monitoring
    var utilization: Double {
        let used = writeIndex >= readIndex ? 
                   writeIndex - readIndex : 
                   capacity - readIndex + writeIndex
        return Double(used) / Double(capacity)
    }
    
    var count: Int {
        return writeIndex >= readIndex ? 
               writeIndex - readIndex : 
               capacity - readIndex + writeIndex
    }
    
    var isEmpty: Bool {
        return readIndex == writeIndex
    }
}

// MARK: - Stream Data Structures

struct StreamChunk {
    let type: StreamEventType
    let content: String
    let fullContent: String?
    let metadata: [String: Any]?
    let timestamp: TimeInterval
    
    static let empty = StreamChunk(
        type: .empty,
        content: "",
        fullContent: nil,
        metadata: nil
    )
    
    init(type: StreamEventType, content: String, fullContent: String? = nil, metadata: [String: Any]? = nil) {
        self.type = type
        self.content = content
        self.fullContent = fullContent
        self.metadata = metadata
        self.timestamp = CFAbsoluteTimeGetCurrent()
    }
}

enum StreamEventType {
    case empty
    case connected
    case heartbeat
    case chunk
    case end
    case error
    
    var priority: Int {
        switch self {
        case .error: return 0      // Highest priority
        case .end: return 1
        case .chunk: return 2
        case .connected: return 3
        case .heartbeat: return 4
        case .empty: return 5      // Lowest priority
        }
    }
}

// MARK: - Batch Processing Engine

class StreamBatchProcessor {
    private let buffer: LockFreeCircularBuffer
    private let processingQueue: DispatchQueue
    private let uiUpdateQueue: DispatchQueue
    private var isProcessing = false
    private var batchTimer: Timer?
    
    // Configuration
    private let maxBatchSize: Int = 10
    private let batchTimeoutMs: TimeInterval = 16.67 // ~60 FPS (16.67ms)
    private let maxProcessingTime: TimeInterval = 8.0 // 8ms max processing per batch
    
    // Performance tracking
    private var processedChunks = 0
    private var droppedChunks = 0
    private var averageProcessingTime: TimeInterval = 0
    
    init() {
        self.buffer = LockFreeCircularBuffer()
        self.processingQueue = DispatchQueue(
            label: "streamProcessor.batch",
            qos: .userInteractive,
            attributes: .concurrent
        )
        self.uiUpdateQueue = DispatchQueue(
            label: "streamProcessor.ui",
            qos: .userInteractive
        )
        
        setupBatchTimer()
        Logger.info("StreamBatchProcessor initialized - max batch: \(maxBatchSize), timeout: \(batchTimeoutMs)ms")
    }
    
    deinit {
        batchTimer?.invalidate()
    }
    
    // MARK: - Public Interface
    
    func addChunk(_ chunk: StreamChunk) {
        let success = buffer.write(chunk)
        if !success {
            droppedChunks += 1
            PerformanceTelemetry.shared.recordCounter("stream.chunk_dropped")
            Logger.warn("StreamBatchProcessor: Dropped chunk (total dropped: \(droppedChunks))")
        } else {
            PerformanceTelemetry.shared.recordCounter("stream.chunk_added")
        }
        
        // Trigger immediate processing for high-priority events
        if chunk.type.priority <= 1 { // error or end events
            PerformanceTelemetry.shared.recordCounter("stream.priority_processing_triggered")
            triggerImmediateProcessing()
        }
    }
    
    func addRawData(_ dataString: String) {
        let lines = dataString.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedLine.isEmpty && trimmedLine != "data: [DONE]" else {
                continue
            }
            
            if trimmedLine.hasPrefix("data: ") {
                let jsonString = String(trimmedLine.dropFirst(6))
                if let chunk = parseStreamChunk(jsonString) {
                    addChunk(chunk)
                }
            }
        }
    }
    
    func getPerformanceStats() -> (processed: Int, dropped: Int, bufferUtilization: Double, avgProcessingTime: TimeInterval) {
        // Record telemetry metrics
        PerformanceTelemetry.shared.recordMetric(PerformanceMetric(
            name: "stream.processed_chunks",
            value: Double(processedChunks),
            unit: .count,
            timestamp: Date(),
            context: nil
        ))
        
        PerformanceTelemetry.shared.recordMetric(PerformanceMetric(
            name: "stream.dropped_chunks",
            value: Double(droppedChunks),
            unit: .count,
            timestamp: Date(),
            context: nil
        ))
        
        PerformanceTelemetry.shared.recordMetric(PerformanceMetric(
            name: "stream.buffer_utilization",
            value: buffer.utilization,
            unit: .percentage,
            timestamp: Date(),
            context: nil
        ))
        
        PerformanceTelemetry.shared.recordMetric(PerformanceMetric(
            name: "stream.avg_processing_time",
            value: averageProcessingTime * 1000, // Convert to ms
            unit: .milliseconds,
            timestamp: Date(),
            context: nil
        ))
        
        return (processedChunks, droppedChunks, buffer.utilization, averageProcessingTime)
    }
    
    // MARK: - Batch Processing
    
    private func setupBatchTimer() {
        batchTimer = Timer.scheduledTimer(withTimeInterval: batchTimeoutMs / 1000.0, repeats: true) { [weak self] _ in
            self?.processBatch()
        }
        
        // Use a high-priority run loop mode
        if let timer = batchTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func triggerImmediateProcessing() {
        guard !isProcessing else { return }
        
        processingQueue.async { [weak self] in
            self?.processBatch()
        }
    }
    
    private func processBatch() {
        guard !isProcessing, !buffer.isEmpty else { return }
        
        isProcessing = true
        let startTime = CFAbsoluteTimeGetCurrent()
        
        processingQueue.async { [weak self] in
            self?.processBatchInternal(startTime: startTime)
        }
    }
    
    private func processBatchInternal(startTime: TimeInterval) {
        defer {
            isProcessing = false
            
            // Update performance metrics
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            averageProcessingTime = (averageProcessingTime * 0.9) + (processingTime * 0.1)
            
            // Record telemetry for batch processing
            PerformanceTelemetry.shared.recordMetric(PerformanceMetric(
                name: "stream.batch_processing_time",
                value: processingTime * 1000, // Convert to ms
                unit: .milliseconds,
                timestamp: Date(),
                context: nil
            ))
        }
        
        let chunks = buffer.readBatch()
        guard !chunks.isEmpty else { return }
        
        // Sort chunks by priority and timestamp
        let sortedChunks = chunks.sorted { chunk1, chunk2 in
            if chunk1.type.priority != chunk2.type.priority {
                return chunk1.type.priority < chunk2.type.priority
            }
            return chunk1.timestamp < chunk2.timestamp
        }
        
        // Process chunks in batches to avoid UI blocking
        let batchSize = min(maxBatchSize, sortedChunks.count)
        let currentBatch = Array(sortedChunks.prefix(batchSize))
        
        // Group UI updates for better performance
        var uiUpdates: [StreamUIUpdate] = []
        var completionUpdate: StreamUIUpdate?
        var errorUpdate: StreamUIUpdate?
        
        for chunk in currentBatch {
            processedChunks += 1
            PerformanceTelemetry.shared.recordCounter("stream.chunk_processed")
            
            switch chunk.type {
            case .chunk:
                if let fullContent = chunk.fullContent {
                    uiUpdates.append(.contentUpdate(chunk.content, fullContent))
                }
                
            case .end:
                var quotaInfo: QuotaInfo?
                var finalTranslated: String?
                
                // Parse quota info from metadata
                if let metadata = chunk.metadata {
                    quotaInfo = parseQuotaInfo(metadata)
                    
                    // Try to extract final translated result from metadata (legacy format)
                    if let result = metadata["result"] as? [String: Any],
                       let translated = result["translated"] as? String {
                        finalTranslated = translated
                    }
                }
                
                // Use finalTranslated if available, otherwise use chunk.content
                let completionContent = finalTranslated ?? (chunk.content.isEmpty ? nil : chunk.content)
                completionUpdate = .completion(completionContent, quotaInfo)
                
            case .error:
                errorUpdate = .error(chunk.content)
                
            case .connected, .heartbeat:
                Logger.debug("StreamBatchProcessor: \(chunk.type) event processed")
                
            case .empty:
                break
            }
            
            // Check if we've exceeded our processing time budget
            let currentTime = CFAbsoluteTimeGetCurrent()
            if (currentTime - startTime) > maxProcessingTime {
                Logger.debug("StreamBatchProcessor: Processing time limit reached, deferring remaining chunks")
                break
            }
        }
        
        // Batch UI updates to main queue
        if !uiUpdates.isEmpty || completionUpdate != nil || errorUpdate != nil {
            uiUpdateQueue.async {
                DispatchQueue.main.async {
                    self.applyUIUpdates(uiUpdates, completion: completionUpdate, error: errorUpdate)
                }
            }
        }
        
        // If there are remaining chunks, schedule next batch
        if chunks.count > batchSize {
            let remainingChunks = Array(sortedChunks.dropFirst(batchSize))
            for chunk in remainingChunks {
                _ = buffer.write(chunk)
            }
            
            // Schedule next batch with a small delay to prevent blocking
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
                self?.processBatch()
            }
        }
    }
    
    // MARK: - UI Update Application
    
    private var streamCallbacks: StreamProcessorCallbacks?
    private var quotaDelegate: TranslatorQuotaDelegate?
    private var accumulatedContent: String = ""
    
    func setCallbacks(_ callbacks: StreamProcessorCallbacks, quotaDelegate: TranslatorQuotaDelegate?) {
        self.streamCallbacks = callbacks
        self.quotaDelegate = quotaDelegate
        self.accumulatedContent = ""
    }
    
    private func applyUIUpdates(_ updates: [StreamUIUpdate], completion: StreamUIUpdate?, error: StreamUIUpdate?) {
        // Apply error first (highest priority)
        if case .error(let message) = error {
            streamCallbacks?.onError(message)
            return
        }
        
        // Apply content updates and track accumulated content
        for update in updates {
            if case .contentUpdate(let chunk, let fullContent) = update {
                accumulatedContent = fullContent // Track the latest full content
                streamCallbacks?.onChunk(chunk, fullContent)
            }
        }
        
        // Apply completion last
        if case .completion(let finalContent, let quotaInfo) = completion {
            // Handle quota info
            if let quotaInfo = quotaInfo {
                quotaDelegate?.didReceiveQuotaUpdate(quotaInfo)
                if quotaInfo.isLowQuota {
                    quotaDelegate?.didReceiveQuotaWarning(quotaInfo)
                }
            }
            
            // Use completion logic that matches legacy behavior:
            // 1. Try finalContent from completion event first
            // 2. Fall back to accumulated content if finalContent is empty
            // 3. Pass nil if accumulated content is also empty
            let resultContent: String?
            if let finalContent = finalContent, !finalContent.isEmpty {
                resultContent = finalContent
                Logger.debug("StreamBatchProcessor: Using finalContent for completion: '\(finalContent.prefix(50))...'")
            } else if !accumulatedContent.isEmpty {
                resultContent = accumulatedContent
                Logger.debug("StreamBatchProcessor: Using accumulatedContent for completion: '\(accumulatedContent.prefix(50))...'")
            } else {
                resultContent = nil
                Logger.warn("StreamBatchProcessor: No content available for completion - both finalContent and accumulatedContent are empty")
            }
            
            streamCallbacks?.onComplete(resultContent, quotaInfo)
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseStreamChunk(_ jsonString: String) -> StreamChunk? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let typeString = json["type"] as? String else {
            Logger.error("Failed to parse stream JSON: \(jsonString)")
            return nil
        }
        
        let type: StreamEventType
        switch typeString {
        case "connected": type = .connected
        case "heartbeat": type = .heartbeat
        case "chunk": type = .chunk
        case "end": type = .end
        case "error": type = .error
        default:
            Logger.warn("Unknown stream event type: \(typeString)")
            return nil
        }
        
        let content = json["content"] as? String ?? ""
        let fullContent = json["fullContent"] as? String
        
        return StreamChunk(type: type, content: content, fullContent: fullContent, metadata: json)
    }
    
    private func parseQuotaInfo(_ metadata: [String: Any]) -> QuotaInfo? {
        guard let quotaData = metadata["quota_info"] as? [String: Any] else {
            return nil
        }
        return QuotaInfo(from: quotaData)
    }
}

// MARK: - Supporting Types

enum StreamUIUpdate {
    case contentUpdate(String, String) // chunk, fullContent
    case completion(String?, QuotaInfo?)
    case error(String)
}

struct StreamProcessorCallbacks {
    let onChunk: (String, String) -> Void
    let onComplete: (String?, QuotaInfo?) -> Void
    let onError: (String) -> Void
}