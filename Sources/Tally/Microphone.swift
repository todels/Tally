import CoreAudio
import Foundation

/// Answers one question: is *something* on this Mac currently using the input
/// device?
///
/// This reads a single boolean device property from CoreAudio. It does not open
/// a stream, does not capture audio, and needs no microphone permission —
/// listening is exactly what it avoids doing. It's the same signal the little
/// orange dot in the menu bar uses.
enum Microphone {

    static func isInUse() -> Bool {
        guard let device = defaultInputDevice() else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)

        return status == noErr && running != 0
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)

        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }
}
