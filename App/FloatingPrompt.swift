import AVKit
import UIKit
import Combine

final class FloatingPrompt: NSObject, ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var possible = false
    @Published private(set) var errorMessage: String?
    let layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var observation: NSKeyValueObservation?
    private var timer: Timer?
    private let log: Diagnostics
    private var characters: [String] = []
    private var position = 0
    private var status = "尚未开始"
    private var audioAge: Double = -1
    private var buffers = 0
    private var sequence = 0
    var onPlayingChanged: ((Bool) -> Void)?
    var onSkip: ((Int) -> Void)?
    private var paused = true

    init(log: Diagnostics) {
        self.log = log
        super.init()
        layer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase {
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 1)
            layer.controlTimebase = timebase
        }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            errorMessage = "这台设备不支持画中画"
            log.add("pip_unsupported")
            return
        }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.requiresLinearPlayback = false
        self.controller = controller
        observation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
            DispatchQueue.main.async {
                self?.possible = c.isPictureInPicturePossible
                self?.log.add("pip_possible", ["value": "\(c.isPictureInPicturePossible)"])
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.render() }
    }
    func update(characters: [String], position: Int, status: String, age: Double, buffers: Int, listening: Bool) {
        self.characters = characters; self.position = position; self.status = status
        audioAge = age; self.buffers = buffers; paused = !listening
        controller?.invalidatePlaybackState()
        render()
    }
    func start() {
        errorMessage = nil
        guard possible else { errorMessage = "悬浮尚未就绪，请先开始跟读"; return }
        log.add("pip_start_requested")
        controller?.startPictureInPicture()
    }
    func stop() { controller?.stopPictureInPicture() }
    private func render() {
        guard !characters.isEmpty else { return }
        sequence += 1
        let timestamp = layer.controlTimebase.map { CMTimebaseGetTime($0) } ?? CMClockGetTime(CMClockGetHostTimeClock())
        let healthy = !paused && audioAge >= 0 && audioAge < 2
        let info = "帧 \(sequence) · 音频 \(buffers) · 位置 \(position)"
        guard let frame = PromptFrame.make(characters: characters, position: position,
            status: status, info: info, healthy: healthy, timestamp: timestamp) else {
            if sequence % 20 == 1 { log.add("frame_creation_failed") }
            return
        }
        if layer.status == .failed {
            log.add("display_layer_failed", ["message": layer.error?.localizedDescription ?? "unknown"])
            layer.flush()
        }
        if layer.isReadyForMoreMediaData { layer.enqueue(frame) }
    }
    deinit { timer?.invalidate() }
}

extension FloatingPrompt: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        active = true; log.add("pip_started")
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        active = false; log.add("pip_stopped")
    }
    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        active = false; errorMessage = error.localizedDescription
        log.add("pip_error", ["message": error.localizedDescription])
    }
    func pictureInPictureController(_ c: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
extension FloatingPrompt: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {
        onPlayingChanged?(playing)
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { paused }
    func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        log.add("pip_size", ["width": "\(newRenderSize.width)", "height": "\(newRenderSize.height)"])
    }
    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void) {
        onSkip?(skipInterval.seconds >= 0 ? 12 : -12)
        completionHandler()
    }
}

private enum PromptFrame {
    static func make(characters: [String], position: Int, status: String, info: String,
                     healthy: Bool, timestamp: CMTime) -> CMSampleBuffer? {
        let width = 480, height = 600
        var pixel: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else { return nil }
        CVPixelBufferLockBaseAddress(pixel, [])
        defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        (status as NSString).draw(in: CGRect(x: 20, y: 16, width: 440, height: 64),
            withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: healthy ? UIColor.systemGreen : UIColor.systemOrange])
        let start = max(0, position - 6), end = min(characters.count, start + 90)
        let text = NSMutableAttributedString(string: "")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = 10
        if start < end {
            for i in start..<end {
                let color = i < position ? UIColor.gray : i == position ? UIColor.systemYellow : UIColor.white
                text.append(NSAttributedString(string: characters[i], attributes: [
                    .font: UIFont.systemFont(ofSize: 43, weight: .semibold),
                    .foregroundColor: color, .paragraphStyle: paragraph]))
            }
        }
        text.draw(with: CGRect(x: 20, y: 84, width: 440, height: 460), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        (info as NSString).draw(in: CGRect(x: 20, y: 562, width: 440, height: 28),
            withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .regular), .foregroundColor: UIColor.lightGray])
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
            formatDescriptionOut: &description) == noErr, let description else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 4), presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
            formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}
