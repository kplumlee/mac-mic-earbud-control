import Foundation
import CoreAudio
import RoutingCore

final class AudioDeviceManager {
    private let system = AudioObjectID(kAudioObjectSystemObject)

    // MARK: - Reading defaults

    func defaultOutputDevice() -> DeviceID? {
        readSystemDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func defaultInputDevice() -> DeviceID? {
        readSystemDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    private func readSystemDeviceID(selector: AudioObjectPropertySelector) -> DeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &dev)
        guard status == noErr, dev != 0 else { return nil }
        return DeviceID(dev)
    }

    // MARK: - Enumerating devices

    func allDevices() -> [AudioDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let actualCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        return ids.prefix(actualCount).map { info(for: $0) }
    }

    private func info(for id: AudioDeviceID) -> AudioDeviceInfo {
        let sr: Double = {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var value: Float64 = 0
            var size = UInt32(MemoryLayout<Float64>.size)
            let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
            return status == noErr ? Double(value) : 0
        }()
        let inputStreams = streamCount(id, scope: kAudioObjectPropertyScopeInput)
        return AudioDeviceInfo(
            id: DeviceID(id),
            name: deviceName(id) ?? "Unknown",
            transport: deviceTransport(id),
            hasOutput: streamCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
            hasInput: inputStreams > 0,
            sampleRate: sr,
            inputChannels: inputStreams)
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfName)
        guard status == noErr, let cf = cfName?.takeRetainedValue() else { return nil }
        return cf as String
    }

    private func deviceTransport(_ id: AudioDeviceID) -> DeviceTransport {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else {
            return .other
        }
        if transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE {
            return .bluetooth
        }
        return .other
    }

    private func streamCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    // MARK: - Device properties

    func nominalSampleRate(for id: DeviceID) -> Double? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(AudioDeviceID(id), &addr, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return Double(value)
    }

    func isDefaultInputInUse() -> Bool {
        guard let id = defaultInputDevice() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(AudioDeviceID(id), &addr, 0, nil, &size, &value)
        guard status == noErr else { return false }
        return value != 0
    }

    // MARK: - Writing

    @discardableResult
    func setDefaultInputDevice(_ id: DeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(id)
        let status = AudioObjectSetPropertyData(
            system, &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
        return status == noErr
    }

    // MARK: - Listening

    private var listenerAddresses: [AudioObjectPropertyAddress] = []
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    func startListening(onChange: @escaping () -> Void) {
        if listenerBlock != nil { stopListening() }
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDevices,
        ]
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            onChange()
        }
        listenerBlock = block
        for selector in selectors {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main, block)
            listenerAddresses.append(addr)
        }
    }

    func stopListening() {
        guard let block = listenerBlock else { return }
        for var addr in listenerAddresses {
            AudioObjectRemovePropertyListenerBlock(system, &addr, DispatchQueue.main, block)
        }
        listenerAddresses.removeAll()
        listenerBlock = nil
    }
}
