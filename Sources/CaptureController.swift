import AppKit
import AVFoundation
import os

/// One serial queue owns both the capture graph and writer state. Preview remains a native layer;
/// recording outputs and microphone are active only during a recording.
final class CaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "SimpleVideoRecorder.capture", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var microphone: AVCaptureDeviceInput?
    private var configured = false
    private var desiredRunning = false
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var firstTime: CMTime?
    private var finishing = false
    private var captureError: String?
    private var requestedAt: TimeInterval = 0
    private let logger = Logger(subsystem: "local.hanskruger.SimpleVideoRecorder", category: "Capture")
    var onError: ((String) -> Void)?
    var onStarted: (() -> Void)?
    var onFinished: ((URL?, String?) -> Void)?
    var onReady: (() -> Void)?
    var onPermissionRequest: (() -> Void)?

    private func error(_ message: String) { DispatchQueue.main.async { self.onError?(message) } }
    func start() {
        queue.async { self.desiredRunning = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                if allowed { self.configureAndStart() }
                else { self.error("Enable camera access in System Settings → Privacy & Security → Camera, then reopen the app.") }
            }
        default: error("Enable camera access in System Settings → Privacy & Security → Camera, then reopen the app.")
        }
    }
    private func configureAndStart() {
        queue.async {
            guard self.desiredRunning else { return }
            do {
                if !self.configured {
                    guard let camera = AVCaptureDevice.default(for: .video) else {
                        self.error("No camera available. Connect a camera, then click Live to retry."); return
                    }
                    let input = try AVCaptureDeviceInput(device: camera)
                    self.session.beginConfiguration()
                    if self.session.canSetSessionPreset(.hd1280x720) { self.session.sessionPreset = .hd1280x720 }
                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.videoOutput) else {
                        self.session.commitConfiguration(); self.error("Cannot configure this camera."); return
                    }
                    self.session.addInput(input); self.session.addOutput(self.videoOutput)
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
                    self.session.commitConfiguration()
                    self.configured = true
                    try camera.lockForConfiguration()
                    if let format = camera.formats.first(where: {
                        let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                        return size.width == 1280 && size.height == 720 && $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
                    }) { camera.activeFormat = format }
                    if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                    }
                    camera.unlockForConfiguration()
                }
                if self.writer == nil { self.releaseRecordingResources() }
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.onReady?() }
            } catch { self.error(error.localizedDescription) }
        }
    }
    private func prepareMicrophone() throws {
        guard microphone == nil else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone available."])
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(audioOutput) else {
            session.commitConfiguration()
            throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot connect the microphone."])
        }
        session.addInput(input); session.addOutput(audioOutput)
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        microphone = input
        session.commitConfiguration()
    }
    private func releaseRecordingResources() {
        videoOutput.connection(with: .video)?.isEnabled = false
        audioOutput.connection(with: .audio)?.isEnabled = false
        if let microphone {
            session.beginConfiguration()
            session.removeInput(microphone)
            session.removeOutput(audioOutput)
            self.microphone = nil
            session.commitConfiguration()
        }
    }
    func handleRuntimeError(_ message: String) {
        queue.async {
            self.desiredRunning = false
            if self.writer != nil {
                self.captureError = message
                self.finishOnQueue()
            } else {
                self.releaseRecordingResources()
                self.error(message)
            }
            if self.session.isRunning { self.stopSession() }
        }
    }
    func stop() {
        queue.async {
            self.desiredRunning = false
            if self.writer != nil { self.finishOnQueue() }
            else if self.session.isRunning { self.stopSession() }
        }
    }
    private func stopSession() {
        session.stopRunning()
        logger.notice("Capture session stopped; camera and microphone are inactive")
    }
    func record(to url: URL) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: beginRecording(url)
        case .notDetermined:
            onPermissionRequest?()
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                if allowed { self.beginRecording(url) }
                else { DispatchQueue.main.async { self.onFinished?(nil, "Enable microphone access in System Settings → Privacy & Security → Microphone.") } }
            }
        default: DispatchQueue.main.async { self.onFinished?(nil, "Enable microphone access in System Settings → Privacy & Security → Microphone.") }
        }
    }
    private func beginRecording(_ url: URL) {
        queue.async {
            guard self.desiredRunning, self.session.isRunning else {
                DispatchQueue.main.async { self.onFinished?(nil, "Click Live to start the camera, then try again.") }; return
            }
            guard self.writer == nil else { return }
            do {
                self.requestedAt = ProcessInfo.processInfo.systemUptime
                try self.prepareMicrophone()
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000, AVVideoExpectedSourceFrameRateKey: 30, AVVideoMaxKeyFrameIntervalKey: 60]
                ])
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 128_000,
                    AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1
                ])
                video.expectsMediaDataInRealTime = true; audio.expectsMediaDataInRealTime = true
                guard writer.canAdd(video), writer.canAdd(audio) else {
                    throw NSError(domain: "Capture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot configure the recording encoder."])
                }
                writer.add(video); writer.add(audio)
                self.writer = writer; self.videoInput = video; self.audioInput = audio
                self.firstTime = nil; self.finishing = false; self.captureError = nil
                self.videoOutput.connection(with: .video)?.isEnabled = true
                self.audioOutput.connection(with: .audio)?.isEnabled = true
            } catch {
                self.releaseRecordingResources()
                DispatchQueue.main.async { self.onFinished?(nil, error.localizedDescription) }
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let writer, !finishing, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstTime == nil {
            guard output === videoOutput else { return }
            guard writer.startWriting() else { complete(writer, message: writer.error?.localizedDescription ?? "Could not start recording."); return }
            writer.startSession(atSourceTime: timestamp)
            firstTime = timestamp
        }
        guard let firstTime, timestamp >= firstTime else { return }
        let input = output === videoOutput ? videoInput : audioInput
        if input?.isReadyForMoreMediaData == true {
            guard input?.append(sampleBuffer) == true else {
                let message = writer.error?.localizedDescription ?? "Recording failed while writing media."
                writer.cancelWriting(); complete(writer, message: message); return
            }
            if requestedAt != 0, output === videoOutput {
                let delay = ProcessInfo.processInfo.systemUptime - requestedAt
                requestedAt = 0
                logger.notice("Recording started after \(delay, privacy: .public) seconds")
                DispatchQueue.main.async { self.onStarted?() }
            }
        } else if writer.status == .failed {
            complete(writer, message: writer.error?.localizedDescription ?? "Recording failed.")
        }
    }
    func finish() { queue.async { self.finishOnQueue() } }
    private func finishOnQueue() {
        guard let writer, !finishing else { return }
        finishing = true
        releaseRecordingResources()
        guard writer.status == .writing else {
            writer.cancelWriting(); complete(writer, message: "Recording stopped before the first frame arrived."); return
        }
        videoInput?.markAsFinished(); audioInput?.markAsFinished()
        writer.finishWriting {
            self.queue.async {
                self.complete(writer, message: writer.status == .completed ? nil : writer.error?.localizedDescription ?? "Could not save recording.")
            }
        }
    }
    private func complete(_ finishedWriter: AVAssetWriter, message: String?) {
        guard writer === finishedWriter else { return }
        let message = captureError ?? message
        captureError = nil
        let url = finishedWriter.outputURL
        releaseRecordingResources()
        writer = nil; videoInput = nil; audioInput = nil; firstTime = nil; finishing = false
        if !desiredRunning { stopSession() }
        // Incomplete outputs are hidden from the library, retained for possible recovery.
        if message != nil, FileManager.default.fileExists(atPath: url.path) {
            let recovery = url.deletingLastPathComponent().appendingPathComponent(".incomplete-" + url.lastPathComponent)
            try? FileManager.default.moveItem(at: url, to: recovery)
        }
        DispatchQueue.main.async { self.onFinished?(message == nil ? url : nil, message) }
    }
}
