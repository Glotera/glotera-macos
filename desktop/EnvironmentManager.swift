import Foundation
import SystemConfiguration
import AppKit

class EnvironmentManager {
    
    static let shared = EnvironmentManager()
    
    private init() {
        Logger.info("EnvironmentManager initialized.")
    }

    /// Gathers all relevant environment information for API requests.
    func getEnvironmentInfo() -> [String: Any] {
        let info: [String: Any] = [
            "os_version": getOSVersion(),
            "app_version": getAppVersion(),
            "locale_id": getLocaleId(),
            "trigger_app": getTriggerAppInfo()
            //"cpu_architecture": getCPUArchitecture(),
            //"ip_address": getIPAddress() //get IP from server
        ]
        return info
    }
    
    /// Returns the operating system version.
    /// e.g., "14.5.0"
    func getOSVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osName = ProcessInfo.processInfo.operatingSystemVersionString
        let systemVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return "macOS \(systemVersion) (\(osName))"
    }
    
    /// Returns the application's version string.
    /// e.g., "1.0.0"
    func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let bundleId = Bundle.main.bundleIdentifier ?? "Unknown"
        return "\(bundleId) \(version)"
    }

    // 存储触发时的应用信息
    private var cachedTriggerAppInfo: String?
    
    /// 记录触发翻译时的应用信息（在翻译开始前调用）
    func recordTriggerApp() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            cachedTriggerAppInfo = "Unknown App -"
            Logger.warn("Failed to get frontmost application")
            return
        }
        
        let appBundleId = activeApp.bundleIdentifier ?? "Unknown"
        let appName = activeApp.localizedName ?? "Unknown"
        
        // 尝试多种方法获取应用版本号
        var appVersion = "-"
        
        // 方法1: 尝试通过 Bundle URL 获取版本号
        if let bundleURL = activeApp.bundleURL {
            if let bundle = Bundle(url: bundleURL) {
                appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? 
                           bundle.infoDictionary?["CFBundleVersion"] as? String ?? "-"
                Logger.debug("Got app version via Bundle URL: \(appVersion)")
            }
        }
        
        // 方法2: 如果方法1失败，尝试通过 Bundle identifier 获取（通常会失败，但作为备选）
        if appVersion == "-", let bundleId = activeApp.bundleIdentifier {
            if let bundle = Bundle(identifier: bundleId) {
                appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
                Logger.debug("Got app version via Bundle identifier: \(appVersion)")
            }
        }
        
        // 方法3: 对于一些系统应用，尝试从应用程序包内的Info.plist直接读取
        if appVersion == "-", let bundleURL = activeApp.bundleURL {
            let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
            if let plistData = try? Data(contentsOf: infoPlistURL),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                appVersion = plist["CFBundleShortVersionString"] as? String ?? 
                           plist["CFBundleVersion"] as? String ?? "-"
                Logger.debug("Got app version via direct Info.plist reading: \(appVersion)")
            }
        }
        
        cachedTriggerAppInfo = "\(appName) (\(appBundleId)) \(appVersion)"
        Logger.info("Recorded trigger app: \(cachedTriggerAppInfo!)")
    }
    
    /// 获取触发翻译时的应用信息
    func getTriggerAppInfo() -> String {
        return cachedTriggerAppInfo ?? "Unknown App"
    }
    
    /// 清除缓存的应用信息（翻译完成后调用）
    func clearTriggerAppInfo() {
        cachedTriggerAppInfo = nil
    }

    /// Returns the user's current locale identifier.
    /// e.g., "en_US" or "zh_CN"
    func getLocaleId() -> String {
        return Locale.current.identifier
    }

    /// Returns the CPU architecture.
    /// e.g., "arm64" (Apple Silicon) or "x86_64" (Intel)
    func getCPUArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// Returns the primary local IP address of the device.
    /// Prefers Wi-Fi/Ethernet (en0) and returns IPv4.
    private func getIPAddress() -> String {
        var address = "Not Available"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) { // IPv4
                let name = String(cString: interface.ifa_name)
                let flags = Int32(interface.ifa_flags)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                // Check for running interface that is not a loopback.
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                    if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        
                        // Prefer en0 for Wi-Fi or Ethernet
                        if name == "en0" {
                            address = ip
                            break
                        }
                        
                        // Otherwise, take the first valid one
                        if address == "Not Available" {
                            address = ip
                        }
                    }
                }
            }
        }
        
        freeifaddrs(ifaddr)
        
        return address
    }
} 