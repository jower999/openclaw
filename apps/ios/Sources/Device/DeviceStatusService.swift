import Darwin
import Foundation
import OpenClawKit
import UIKit

final class DeviceStatusService: DeviceStatusServicing {
    private let networkStatus: NetworkStatusService

    init(networkStatus: NetworkStatusService = NetworkStatusService()) {
        self.networkStatus = networkStatus
    }

    func status() async throws -> OpenClawDeviceStatusPayload {
        let battery = self.batteryStatus()
        let thermal = self.thermalStatus()
        let storage = self.storageStatus()
        let network = await self.networkStatus.currentStatus()
        let uptime = ProcessInfo.processInfo.systemUptime

        return OpenClawDeviceStatusPayload(
            battery: battery,
            thermal: thermal,
            storage: storage,
            network: network,
            uptimeSeconds: uptime)
    }

    func info() -> OpenClawDeviceInfoPayload {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let rawBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let appBuild = DeviceStatusService.fallbackAppBuild(rawBuild)
        let locale = Locale.preferredLanguages.first ?? Locale.current.identifier

        var systemInfo = utsname()
        uname(&systemInfo)
        let modelIdentifier = withUnsafeBytes(of: &systemInfo.machine) { ptr in
            String(bytes: ptr.prefix { $0 != 0 }, encoding: .utf8)
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModelIdentifier = (modelIdentifier?.isEmpty == false) ? modelIdentifier! : "unknown"

        return OpenClawDeviceInfoPayload(
            deviceName: device.name,
            modelIdentifier: resolvedModelIdentifier,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            appVersion: appVersion,
            appBuild: appBuild,
            locale: locale)
    }

    private func batteryStatus() -> OpenClawBatteryStatusPayload {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        let state: OpenClawBatteryState = switch device.batteryState {
        case .charging: .charging
        case .full: .full
        case .unplugged: .unplugged
        case .unknown: .unknown
        @unknown default: .unknown
        }
        return OpenClawBatteryStatusPayload(
            level: level,
            state: state,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    private func thermalStatus() -> OpenClawThermalStatusPayload {
        let state: OpenClawThermalState = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
        return OpenClawThermalStatusPayload(state: state)
    }

    private func storageStatus() -> OpenClawStorageStatusPayload {
        let attrs = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())) ?? [:]
        let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let used = max(0, total - free)
        return OpenClawStorageStatusPayload(totalBytes: total, freeBytes: free, usedBytes: used)
    }

    /// Fallback for payloads that require a non-empty build (e.g. "0").
    private static func fallbackAppBuild(_ build: String) -> String {
        build.isEmpty ? "0" : build
    }
}
