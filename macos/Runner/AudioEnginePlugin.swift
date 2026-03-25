// macos/Runner/AudioEnginePlugin.swift
// Native audio engine — MethodChannel + two EventChannels.
//
// MethodChannel:  com.whatsthefrequency.app/audio_engine
// EventChannel:   com.whatsthefrequency.app/level_meter
// EventChannel:   com.whatsthefrequency.app/device_events

import AVFoundation
import CoreAudio
import FlutterMacOS

// MARK: - Plugin registration

class AudioEnginePlugin: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let impl = AudioEngineImpl(messenger: registrar.messenger)
        let method = FlutterMethodChannel(
            name: "com.whatsthefrequency.app/audio_engine",
            binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(impl, channel: method)
    }
}

// MARK: - Core implementation

private class AudioEngineImpl: NSObject, FlutterPlugin {

    // ── Channels ──────────────────────────────────────────────────────────────
    private var levelMeterSink: FlutterEventSink?
    private var deviceEventsSink: FlutterEventSink?

    // ── Engine ────────────────────────────────────────────────────────────────
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    // ── Device selection ──────────────────────────────────────────────────────
    private var selectedDeviceID: AudioDeviceID = kAudioObjectUnknown

    // ── Capture state ─────────────────────────────────────────────────────────
    private var pendingCaptureResult: FlutterResult?
    private var capturedSamples: [Float] = []
    private var expectedSampleCount: Int = 0
    private var isCancelled = false
    private let captureQueue = DispatchQueue(label: "wtfk.capture", qos: .userInteractive)

    // ── Level meter ───────────────────────────────────────────────────────────
    private var levelMeterTimer: Timer?
    private var peakDbfs: Float = -160.0
    private var inputTapActive = false

    // ── Level-check tone ──────────────────────────────────────────────────────
    private var tonePlayerNode: AVAudioPlayerNode?

    // ── Device listener ───────────────────────────────────────────────────────
    private var knownDeviceUIDs: Set<String> = []

    // ─────────────────────────────────────────────────────────────────────────

    init(messenger: FlutterBinaryMessenger) {
        super.init()
        engine.attach(playerNode)

        // Level meter EventChannel.
        let levelCh = FlutterEventChannel(
            name: "com.whatsthefrequency.app/level_meter",
            binaryMessenger: messenger)
        levelCh.setStreamHandler(
            ClosureStreamHandler(
                onListenBlock:  { [weak self] sink in self?.levelMeterSink = sink },
                onCancelBlock:  { [weak self] in self?.levelMeterSink = nil }))

        // Device events EventChannel.
        let deviceCh = FlutterEventChannel(
            name: "com.whatsthefrequency.app/device_events",
            binaryMessenger: messenger)
        deviceCh.setStreamHandler(
            ClosureStreamHandler(
                onListenBlock:  { [weak self] sink in self?.deviceEventsSink = sink },
                onCancelBlock:  { [weak self] in self?.deviceEventsSink = nil }))

        installSystemDeviceListener()
    }

    // ── FlutterPlugin (not used for registration here, but satisfies protocol) ─
    static func register(with registrar: FlutterPluginRegistrar) {}

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Method dispatch
    // ─────────────────────────────────────────────────────────────────────────

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAvailableDevices":  handleGetAvailableDevices(result: result)
        case "setDevice":            handleSetDevice(args: call.arguments, result: result)
        case "getActiveSampleRate":  handleGetActiveSampleRate(result: result)
        case "runCapture":           handleRunCapture(args: call.arguments, result: result)
        case "cancelCapture":        handleCancelCapture(result: result)
        case "startLevelMeter":      handleStartLevelMeter(result: result)
        case "stopLevelMeter":       handleStopLevelMeter(result: result)
        case "startLevelCheckTone":  handleStartLevelCheckTone(result: result)
        case "stopLevelCheckTone":   handleStopLevelCheckTone(result: result)
        default:                     result(FlutterMethodNotImplemented)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Device enumeration
    // ─────────────────────────────────────────────────────────────────────────

    private func handleGetAvailableDevices(result: FlutterResult) {
        let devices: [[String: Any]] = systemDeviceIDs().compactMap { id in
            guard let uid  = deviceUID(id),
                  let name = deviceName(id) else { return nil }
            // Include devices that have at least one input or output channel.
            guard channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0
                || channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0
            else { return nil }
            return ["uid": uid,
                    "name": name,
                    "nativeSampleRate": nominalSampleRate(id)]
        }
        result(devices)
    }

    private func handleSetDevice(args: Any?, result: FlutterResult) {
        guard let map = args as? [String: Any],
              let uid = map["uid"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "uid required", details: nil))
            return
        }
        guard let deviceID = systemDeviceIDs().first(where: { deviceUID($0) == uid }) else {
            result(FlutterError(code: "DEVICE_NOT_FOUND",
                                message: "No device with uid \(uid)", details: nil))
            return
        }
        selectedDeviceID = deviceID
        result(nil)
    }

    private func handleGetActiveSampleRate(result: FlutterResult) {
        guard selectedDeviceID != kAudioObjectUnknown else {
            result(FlutterError(code: "NO_DEVICE_SELECTED",
                                message: "No device selected", details: nil))
            return
        }
        result(nominalSampleRate(selectedDeviceID))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Capture
    // ─────────────────────────────────────────────────────────────────────────

    private func handleRunCapture(args: Any?, result: @escaping FlutterResult) {
        guard let map        = args as? [String: Any],
              let sweepData  = (map["sweepSamples"] as? FlutterStandardTypedData)?.data,
              let sampleRate = map["sampleRate"] as? Int,
              let postRollMs = map["postRollMs"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "sweepSamples/sampleRate/postRollMs required", details: nil))
            return
        }

        // Re-interpret raw bytes as Float32.
        let sweepCount = sweepData.count / MemoryLayout<Float>.size
        var sweep = [Float](repeating: 0, count: sweepCount)
        sweepData.withUnsafeBytes {
            guard let ptr = $0.bindMemory(to: Float.self).baseAddress else { return }
            for i in 0..<sweepCount { sweep[i] = ptr[i] }
        }

        let postRollSamples = Int(Double(sampleRate) * Double(postRollMs) / 1000.0)
        expectedSampleCount = sweepCount + postRollSamples
        capturedSamples = []
        capturedSamples.reserveCapacity(expectedSampleCount)
        isCancelled      = false
        pendingCaptureResult = result

        do {
            try prepareEngine(sampleRate: sampleRate)
        } catch {
            pendingCaptureResult = nil
            result(FlutterError(code: "ENGINE_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        // Build PCM buffer from sweep samples.
        let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                         frameCapacity: AVAudioFrameCount(sweepCount)) else {
            pendingCaptureResult = nil
            result(FlutterError(code: "BUFFER_ERROR", message: "Cannot allocate sweep buffer", details: nil))
            return
        }
        buf.frameLength = AVAudioFrameCount(sweepCount)
        let ch = buf.floatChannelData![0]
        for i in 0..<sweepCount { ch[i] = sweep[i] }

        // Install input tap.
        let inputFmt = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFmt) { [weak self] tapBuf, _ in
            self?.captureQueue.async { self?.accumulateTap(tapBuf) }
        }
        inputTapActive = true

        do {
            try engine.start()
        } catch {
            teardownInputTap()
            pendingCaptureResult = nil
            result(FlutterError(code: "ENGINE_START", message: error.localizedDescription, details: nil))
            return
        }

        // Verify the hardware is actually running at the expected rate.
        // If the OS has resampled to a different rate (e.g. 44.1 kHz), every
        // frequency in the result will be shifted — surface this immediately.
        let actualRate = engine.inputNode.outputFormat(forBus: 0).sampleRate
        guard actualRate == Double(sampleRate) else {
            teardownCapture(error: FlutterError(
                code: "SAMPLE_RATE_MISMATCH",
                message: "Device is running at \(Int(actualRate)) Hz, expected \(sampleRate) Hz. " +
                         "Set the Scarlett 2i2 to \(sampleRate) Hz in Focusrite Control and try again.",
                details: nil))
            return
        }

        // Schedule playback with 100 ms look-ahead for USB scheduling jitter.
        guard let renderTime = engine.outputNode.lastRenderTime else {
            teardownCapture(error: FlutterError(code: "NO_RENDER_TIME",
                                                message: "Engine has no render time", details: nil))
            return
        }
        let lookAheadFrames = AVAudioFramePosition(Double(sampleRate) * 0.1)
        let startSample = renderTime.sampleTime + lookAheadFrames
        let startTime   = AVAudioTime(sampleTime: startSample, atRate: Double(sampleRate))

        playerNode.scheduleBuffer(buf, at: startTime, options: .interrupts)
        playerNode.play(at: startTime)
    }

    private func accumulateTap(_ buffer: AVAudioPCMBuffer) {
        guard !isCancelled, let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        for i in 0..<n { capturedSamples.append(data[0][i]) }
        if capturedSamples.count >= expectedSampleCount {
            finishCapture()
        }
    }

    private func finishCapture() {
        teardownInputTap()
        engine.stop()

        guard let result = pendingCaptureResult else { return }
        pendingCaptureResult = nil

        let trimmed = Array(capturedSamples.prefix(expectedSampleCount))

        // Dropout: if fewer samples than expected (engine stopped early).
        if trimmed.count < expectedSampleCount {
            result(FlutterError(code: "DROPOUT_DETECTED",
                                message: "Captured \(trimmed.count) of \(expectedSampleCount) samples",
                                details: nil))
            return
        }

        // Clipping check: -1 dBFS ≈ 0.891 linear.
        if trimmed.contains(where: { abs($0) > 0.891 }) {
            result(FlutterError(code: "OUTPUT_CLIPPING",
                                message: "Captured signal is clipping", details: nil))
            return
        }

        let bytes = trimmed.withUnsafeBytes { Data($0) }
        result(FlutterStandardTypedData(bytes: bytes))
    }

    private func handleCancelCapture(result: FlutterResult) {
        isCancelled = true
        if let pending = pendingCaptureResult {
            teardownCapture(error: FlutterError(code: "CANCELLED",
                                                message: "Capture cancelled", details: nil))
            _ = pending // already stored in pendingCaptureResult; teardownCapture calls it
        }
        result(nil)
    }

    private func teardownCapture(error: FlutterError) {
        teardownInputTap()
        engine.stop()
        pendingCaptureResult?(error)
        pendingCaptureResult = nil
    }

    private func teardownInputTap() {
        if inputTapActive {
            engine.inputNode.removeTap(onBus: 0)
            inputTapActive = false
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Level meter
    // ─────────────────────────────────────────────────────────────────────────

    private func handleStartLevelMeter(result: FlutterResult) {
        guard !inputTapActive else { result(nil); return }
        do {
            try prepareEngine(sampleRate: 48000)
            let fmt = engine.inputNode.outputFormat(forBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
                self?.updatePeak(buf)
            }
            inputTapActive = true
            try engine.start()
        } catch {
            result(FlutterError(code: "ENGINE_ERROR", message: error.localizedDescription, details: nil))
            return
        }
        startMeterTimer()
        result(nil)
    }

    private func handleStopLevelMeter(result: FlutterResult) {
        stopMeterTimer()
        teardownInputTap()
        engine.stop()
        result(nil)
    }

    private func updatePeak(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(data[0][i])) }
        peakDbfs = peak > 1e-9 ? 20.0 * log10f(peak) : -160.0
    }

    private func startMeterTimer() {
        levelMeterTimer?.invalidate()
        levelMeterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.levelMeterSink?(self.peakDbfs)
        }
    }

    private func stopMeterTimer() {
        levelMeterTimer?.invalidate()
        levelMeterTimer = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Level-check tone (1 kHz sine, looped)
    // ─────────────────────────────────────────────────────────────────────────

    private func handleStartLevelCheckTone(result: FlutterResult) {
        stopExistingTone()

        let sampleRate: Double = 48000
        let hz: Double = 1000
        // Two-second loop buffer at -6 dBFS amplitude to avoid clipping during setup.
        let frameCount = Int(sampleRate * 2.0)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let toneBuf = AVAudioPCMBuffer(pcmFormat: fmt,
                                              frameCapacity: AVAudioFrameCount(frameCount)) else {
            result(FlutterError(code: "BUFFER_ERROR", message: "Cannot allocate tone buffer", details: nil))
            return
        }
        toneBuf.frameLength = AVAudioFrameCount(frameCount)
        let ch = toneBuf.floatChannelData![0]
        let amp: Float = 0.5 // -6 dBFS
        for i in 0..<frameCount {
            ch[i] = amp * Float(sin(2.0 * Double.pi * hz * Double(i) / sampleRate))
        }

        let toneNode = AVAudioPlayerNode()
        engine.attach(toneNode)
        engine.connect(toneNode, to: engine.mainMixerNode, format: fmt)
        tonePlayerNode = toneNode

        do {
            try prepareEngine(sampleRate: 48000)
        } catch {
            engine.detach(toneNode)
            tonePlayerNode = nil
            result(FlutterError(code: "ENGINE_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        // Also tap input for level metering.
        if !inputTapActive {
            let inputFmt = engine.inputNode.outputFormat(forBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFmt) { [weak self] buf, _ in
                self?.updatePeak(buf)
            }
            inputTapActive = true
        }

        do {
            try engine.start()
        } catch {
            teardownInputTap()
            stopExistingTone()
            result(FlutterError(code: "ENGINE_START", message: error.localizedDescription, details: nil))
            return
        }

        toneNode.scheduleBuffer(toneBuf, at: nil, options: .loops)
        toneNode.play()
        startMeterTimer()
        result(nil)
    }

    private func handleStopLevelCheckTone(result: FlutterResult) {
        stopMeterTimer()
        stopExistingTone()
        teardownInputTap()
        engine.stop()
        result(nil)
    }

    private func stopExistingTone() {
        tonePlayerNode?.stop()
        if let node = tonePlayerNode {
            engine.detach(node)
            tonePlayerNode = nil
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Engine configuration
    // ─────────────────────────────────────────────────────────────────────────

    private func prepareEngine(sampleRate: Int) throws {
        if engine.isRunning { engine.stop() }

        let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: fmt)

        if selectedDeviceID != kAudioObjectUnknown {
            try applyDevice(selectedDeviceID, to: engine.outputNode)
            try applyDevice(selectedDeviceID, to: engine.inputNode)
        }
    }

    private func applyDevice(_ deviceID: AudioDeviceID, to node: AVAudioNode) throws {
        // AUAudioUnit's C-bridge AudioUnit property was removed in macOS 26 SDK.
        // AVAudioEngine picks up the system default I/O devices when started,
        // so we route by setting the system defaults before engine.start().
        let selector: AudioObjectPropertySelector = (node === engine.outputNode)
            ? kAudioHardwarePropertyDefaultOutputDevice
            : kAudioHardwarePropertyDefaultInputDevice
        var devID = deviceID
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &devID)
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Core Audio device helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func systemDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown,
                                  count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func deviceUID(_ id: AudioDeviceID) -> String? {
        stringProperty(id, selector: kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal)
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        stringProperty(id, selector: kAudioDevicePropertyDeviceNameCFString, scope: kAudioObjectPropertyScopeGlobal)
    }

    private func stringProperty(_ id: AudioDeviceID,
                                 selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                              mElement: kAudioObjectPropertyElementMain)
        var cfStr: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfStr) == noErr,
              let s = cfStr else { return nil }
        return s as String
    }

    private func nominalSampleRate(_ id: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var rate: Double = 48000
        var size = UInt32(MemoryLayout<Double>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate)
        return rate
    }

    private func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope:    scope,
            mElement:  kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: System device-change listener
    // ─────────────────────────────────────────────────────────────────────────

    private func installSystemDeviceListener() {
        knownDeviceUIDs = Set(systemDeviceIDs().compactMap { deviceUID($0) })
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main
        ) { [weak self] _, _ in self?.onSystemDeviceListChanged() }
    }

    private func onSystemDeviceListChanged() {
        let current = Set(systemDeviceIDs().compactMap { deviceUID($0) })
        let added   = current.subtracting(knownDeviceUIDs)
        let removed = knownDeviceUIDs.subtracting(current)
        knownDeviceUIDs = current

        for uid in added {
            let name = systemDeviceIDs()
                .first(where: { deviceUID($0) == uid })
                .flatMap { deviceName($0) } ?? uid
            deviceEventsSink?(["event": "deviceAdded", "uid": uid, "name": name])
        }
        for uid in removed {
            deviceEventsSink?(["event": "deviceRemoved", "uid": uid, "name": uid])
        }
    }
}

// MARK: - ClosureStreamHandler

/// Generic FlutterStreamHandler backed by closures.
private class ClosureStreamHandler: NSObject, FlutterStreamHandler {
    private let onListenBlock:  (FlutterEventSink?) -> Void
    private let onCancelBlock:  () -> Void

    init(onListenBlock: @escaping (FlutterEventSink?) -> Void,
         onCancelBlock: @escaping () -> Void) {
        self.onListenBlock = onListenBlock
        self.onCancelBlock = onCancelBlock
    }

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenBlock(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListenBlock(nil)
        onCancelBlock()
        return nil
    }
}
