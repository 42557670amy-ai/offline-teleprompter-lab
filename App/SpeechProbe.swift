import AVFoundation
import Speech
import Combine
import UIKit

// A diagnostic app: interruption freezes the script and is visible, never hidden
// behind a timer that repeatedly takes audio focus from the camera.
final class SpeechProbe: ObservableObject {
    @Published private(set) var status = "尚未开始"
    @Published private(set) var position = 0
    @Published private(set) var transcript = ""
    @Published private(set) var active = false
    @Published private(set) var bufferCount = 0
    @Published private(set) var rms: Float = 0
    @Published private(set) var lastAudioAge: Double = -1
    var onChange: (() -> Void)?
    let log: Diagnostics
    let matcher: MatcherBridge
    private var engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var wanted = false
    private var interrupted = false
    private var generation = 0
    private var errorRetries = 0
    private var starting = false
    private let feed = AudioFeed()

    private final class AudioFeed: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        private var count = 0
        private var level: Float = 0
        private var time: Double = 0
        func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
            lock.lock(); defer { lock.unlock() }
            self.request = request
            time = 0
            level = 0
        }
        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            guard let request else { return }
            request.append(buffer)
            count += 1
            time = ProcessInfo.processInfo.systemUptime
            if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += channel[i] * channel[i] }
                level = sqrt(sum / Float(buffer.frameLength))
            }
        }
        func snapshot() -> (Int, Float, Double) {
            lock.lock(); defer { lock.unlock() }
            return (count, level, time)
        }
    }

    init(log: Diagnostics, matcher: MatcherBridge) {
        self.log = log
        self.matcher = matcher
        observe()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.heartbeat()
        }
    }

    func start() {
        guard !starting else { return }
        starting = true
        status = "检查权限与中文离线识别"
        generation += 1
        let token = generation
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard let self, token == self.generation else { return }
                    self.starting = false
                    guard auth == .authorized, granted else {
                        self.status = "需要麦克风和语音识别权限"
                        self.log.add("permission_denied", ["speech": "\(auth.rawValue)", "mic": "\(granted)"])
                        self.onChange?()
                        return
                    }
                    self.wanted = true
                    self.interrupted = false
                    self.errorRetries = 0
                    self.begin()
                }
            }
        }
    }

    private func begin() {
        guard wanted, !interrupted else { return }
        cleanup()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.supportsOnDeviceRecognition else {
            fail("本机中文离线识别不可用；不会转用联网识别")
            return
        }
        guard recognizer.isAvailable else {
            fail("中文识别服务当前不可用")
            return
        }
        self.recognizer = recognizer
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(mic)
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request
            matcher.newUtterance()
            feed.set(request)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("麦克风输入格式不可用")
                return
            }
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in feed.append(buffer) }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            active = true
            status = "等待声音"
            let token = generation
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let problem = error.map { $0 as NSError }
                DispatchQueue.main.async {
                    guard let self, token == self.generation, self.wanted, !self.interrupted else { return }
                    if let text {
                        self.transcript = text
                        if let match = self.matcher.update(text) {
                            self.position = match.position
                            self.status = "正在跟读"
                            self.log.add("recognition", ["text": text, "position": "\(match.position)",
                                "reason": match.reason, "confidence": "\(match.confidence)", "final": "\(final)"])
                        } else {
                            self.fail("稿件匹配失败，请导出诊断")
                            return
                        }
                    }
                    if final {
                        self.restart(after: 0.2)
                    } else if let problem {
                        self.log.add("recognition_error", ["domain": problem.domain, "code": "\(problem.code)",
                            "message": problem.localizedDescription])
                        // One bounded retry only in foreground. Background errors require
                        // an interruption-ended event or an explicit user start.
                        if self.errorRetries < 1, UIApplication.shared.applicationState == .active {
                            self.errorRetries += 1
                            self.restart(after: 0.8)
                        } else { self.fail("识别停止，请返回后重新开始") }
                    }
                    self.onChange?()
                }
            }
            log.add("audio_started", ["locale": "zh-CN", "onDeviceRequired": "true",
                "sampleRate": "\(format.sampleRate)", "route": routeDescription()])
            onChange?()
        } catch {
            log.add("audio_start_error", ["message": error.localizedDescription])
            fail("无法开始收音：\(error.localizedDescription)")
        }
    }

    private func restart(after delay: TimeInterval) {
        cleanup()
        status = "正在恢复识别"
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, token == self.generation, self.wanted, !self.interrupted else { return }
            self.begin()
        }
    }

    func stop() {
        wanted = false
        starting = false
        cleanup()
        status = "已停止"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        log.add("user_stop")
        onChange?()
    }
    func seek(_ index: Int) {
        position = max(0, min(index, matcher.characters.count))
        matcher.seek(position)
        log.add("manual_seek", ["position": "\(position)"])
        // Discard the old cumulative transcript after an explicit reposition.
        if wanted && !interrupted { restart(after: 0.2) }
        onChange?()
    }
    private func cleanup() {
        generation += 1
        feed.set(nil)
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        active = false
    }
    private func fail(_ message: String) {
        wanted = false
        cleanup()
        status = message
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        log.add("stopped_with_error", ["message": message])
        onChange?()
    }
    private func routeDescription() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
    }
    private func heartbeat() {
        let sample = feed.snapshot()
        bufferCount = sample.0
        rms = sample.1
        lastAudioAge = sample.2 > 0 ? ProcessInfo.processInfo.systemUptime - sample.2 : -1
        if active && lastAudioAge > 2 { status = "收音已停，跟读暂停" }
        else if active && (status == "收音已停，跟读暂停" || status == "等待声音") && lastAudioAge >= 0 {
            status = "已收到音频，等待识别"
        }
        if wanted || interrupted {
            log.add("heartbeat", ["buffers": "\(bufferCount)", "rms": "\(rms)",
                "audioAge": "\(lastAudioAge)", "engineRunning": "\(engine.isRunning)",
                "position": "\(position)", "interrupted": "\(interrupted)", "route": routeDescription()])
        }
        onChange?()
    }
    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.interrupted = true
                self.cleanup()
                self.status = "收音被其他应用中断，跟读暂停"
                self.log.add("interruption_began")
            } else {
                self.interrupted = false
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let resume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                self.log.add("interruption_ended", ["shouldResume": "\(resume)"])
                if self.wanted && resume { self.begin() }
                else { self.status = "中断已结束，请返回后重新开始" }
            }
            self.onChange?()
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            self.log.add("route_changed", ["route": self.routeDescription(),
                "reason": "\(note.userInfo?[AVAudioSessionRouteChangeReasonKey] ?? "unknown")"])
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.cleanup()
            self.engine = AVAudioEngine()
            self.wanted = false
            self.status = "系统音频服务重置，请重新开始"
            self.log.add("media_services_reset")
            self.onChange?()
        })
    }
    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
