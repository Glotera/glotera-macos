import Cocoa

class ChatMessagesUtil {
       /// Parse timestamp string into Date object for proper comparison
    /// Expected format: "July 30, 14:30" or "July 30, 02:30"
    static func parseTimestamp(_ timestamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        
        // Try different timestamp formats
        let formats = [
            "MMMM d, HH:mm",    // "July 30, 14:30"
            "MMMM d, H:mm",     // "July 30, 2:30"
            "MMM d, HH:mm",     // "Jul 30, 14:30"
            "MMM d, H:mm",      // "Jul 30, 2:30"
            "yyyy-MM-dd HH:mm", // "2024-07-30 14:30"
            "dd/MM/yyyy HH:mm", // "30/07/2024 14:30"
            "MM/dd/yyyy HH:mm"  // "07/30/2024 14:30"
        ]
        
        let currentYear = Calendar.current.component(.year, from: Date())
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: timestamp) {
                // If the parsed date doesn't have a year (month/day only), add current year
                let calendar = Calendar.current
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                
                // Check if year is reasonable (not 1, 2000, or nil)
                let year = components.year ?? 1
                if year < 2020 {
                    // Date without year or with invalid year, add current year
                    var newComponents = components
                    newComponents.year = currentYear
                    if let dateWithYear = calendar.date(from: newComponents) {
                        Logger.debug("Parsed timestamp '\(timestamp)' as \(dateWithYear) (added current year)")
                        return dateWithYear
                    }
                }
                
                Logger.debug("Parsed timestamp '\(timestamp)' as \(date)")
                return date
            }
        }
        
        Logger.warn("Failed to parse timestamp: '\(timestamp)'")
        return nil
    }
       
    /// Print the entire element tree for debugging in JSON format
    static func printElementTree(_ element: AXUIElement, depth: Int = -1) {
        // 重置访问状态，防止多次调用时的状态残留
        visitedElements.removeAll()
        
        let jsonString = buildOrderedJSON(element, currentDepth: 0, maxDepth: depth) 
        Logger.info(jsonString) 
        
        // 清理访问状态，释放内存
        visitedElements.removeAll()
    }
    
    /// Visited elements to prevent infinite recursion
    private static var visitedElements: Set<String> = []
    private static let maxRecursionDepth = 50  // Maximum recursion depth
    
    /// Extract element data recursively and build JSON structure
    private static func extractElementData(_ element: AXUIElement, currentDepth: Int, maxDepth: Int) -> [String: Any] {
        // 防止过深的递归
        if currentDepth > maxRecursionDepth {
            Logger.warn("Maximum recursion depth (\(maxRecursionDepth)) reached, stopping traversal")
            return ["error": "max_depth_reached", "depth": currentDepth]
        }
        
        // 创建元素的唯一标识符
        let elementPointer = Unmanaged.passUnretained(element).toOpaque()
        let elementId = "\(elementPointer)"
        
        // 检查是否已经访问过这个元素（防止循环引用）
        if visitedElements.contains(elementId) {
            Logger.warn("Circular reference detected for element at depth \(currentDepth), skipping")
            return ["error": "circular_reference", "depth": currentDepth, "elementId": elementId]
        }
        
        // 标记这个元素为已访问
        visitedElements.insert(elementId)
        
        var elementData: [String: Any] = [:]
        
        // Get element role
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = (roleResult == .success) ? (role as? String ?? "unknown") : "unknown"
        elementData["role"] = roleString
        
        // Get element title
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        let titleString = (titleResult == .success) ? (title as? String ?? "") : ""
        elementData["title"] = titleString
        
        // Get element value
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        let valueString = (valueResult == .success) ? (value as? String ?? "") : ""
        elementData["value"] = valueString
        
        // Get element description
        var description: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        let descString = (descResult == .success) ? (description as? String ?? "") : ""
        elementData["description"] = descString
        
        // Get element subrole
        var subrole: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        let subroleString = (subroleResult == .success) ? (subrole as? String ?? "") : ""
        elementData["subrole"] = subroleString
        
        // Add depth information
        elementData["depth"] = currentDepth
        
        // Get children if not at max depth
        if maxDepth == -1 || currentDepth < maxDepth {
            var children: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            
            if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
                var childrenData: [[String: Any]] = []
                
                for (index, child) in childrenArray.enumerated() {
                    var childData = extractElementData(child, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                    childData["index"] = index
                    childrenData.append(childData)
                }
                
                // Add children information at the end for better readability
                elementData["childrenCount"] = childrenData.count
                elementData["children"] = childrenData
            } else {
                elementData["childrenCount"] = 0
                elementData["children"] = []
            }
        }
        
        // Create ordered dictionary to ensure children appears last
        var orderedData: [String: Any] = [:]
        orderedData["role"] = elementData["role"] ?? ""
        orderedData["title"] = elementData["title"] ?? ""
        orderedData["value"] = elementData["value"] ?? ""
        orderedData["description"] = elementData["description"] ?? ""
        orderedData["subrole"] = elementData["subrole"] ?? ""
        orderedData["depth"] = elementData["depth"] ?? 0
        orderedData["childrenCount"] = elementData["childrenCount"] ?? 0
        orderedData["children"] = elementData["children"] ?? []
        
        // 回溯时移除访问标记，允许在不同路径中重新访问同一元素
        visitedElements.remove(elementId)
        
        return orderedData
    }
    
    /// Build ordered JSON string manually to ensure proper key ordering
    private static func buildOrderedJSON(_ element: AXUIElement, currentDepth: Int, maxDepth: Int) -> String {
        let elementData = extractElementData(element, currentDepth: currentDepth, maxDepth: maxDepth)
        return buildOrderedJSONString(elementData, indent: 0)
    }
    
    /// Recursively build ordered JSON string with proper indentation
    private static func buildOrderedJSONString(_ data: [String: Any], indent: Int) -> String {
        let indentString = String(repeating: "  ", count: indent)
        var jsonParts: [String] = []
        
        // Add basic attributes in order
        if let role = data["role"] as? String {
            jsonParts.append("\(indentString)\"role\": \"\(role)\"")
        }
        
        if let title = data["title"] as? String, !title.isEmpty {
            jsonParts.append("\(indentString)\"title\": \"\(title)\"")
        }
        
        if let value = data["value"] as? String, !value.isEmpty {
            jsonParts.append("\(indentString)\"value\": \"\(value)\"")
        }
        
        if let description = data["description"] as? String, !description.isEmpty {
            jsonParts.append("\(indentString)\"description\": \"\(description)\"")
        }
        
        if let subrole = data["subrole"] as? String, !subrole.isEmpty {
            jsonParts.append("\(indentString)\"subrole\": \"\(subrole)\"")
        }
        
        if let depth = data["depth"] as? Int {
            jsonParts.append("\(indentString)\"depth\": \(depth)")
        }
        
        if let childrenCount = data["childrenCount"] as? Int {
            jsonParts.append("\(indentString)\"childrenCount\": \(childrenCount)")
        }
        
        // Add children at the end
        if let children = data["children"] as? [[String: Any]], !children.isEmpty {
            let childrenJson = children.map { childData in
                buildOrderedJSONString(childData, indent: indent + 1)
            }.joined(separator: ",\n")
            
            jsonParts.append("\(indentString)\"children\": [\n\(childrenJson)\n\(indentString)]")
        } else {
            jsonParts.append("\(indentString)\"children\": []")
        }
        
        return "{\n" + jsonParts.joined(separator: ",\n") + "\n\(String(repeating: "  ", count: max(0, indent - 1)))}"
    }
}
