import SwiftUI
import AVFoundation

final class AppModel {
    let log: Diagnostics
    let probe: SpeechProbe
    let floating: FloatingPrompt
    init() throws {
        let log = Diagnostics()
        let matcher = try MatcherBridge(script: SampleScript.text)
        let probe = SpeechProbe(log: log, matcher: matcher)
        let floating = FloatingPrompt(log: log)
        self.log = log; self.probe = probe; self.floating = floating
        probe.onChange = { [weak probe, weak floating] in
            guard let probe, let floating else { return }
            floating.update(characters: probe.matcher.characters, position: probe.position,
                status: probe.status, age: probe.lastAudioAge, buffers: probe.bufferCount, listening: probe.active)
        }
        floating.onPlayingChanged = { [weak probe, weak log] playing in
            if !playing { probe?.stop() }
            else if probe?.active != true && UIApplication.shared.applicationState == .active { probe?.start() }
            else if probe?.active != true { log?.add("pip_resume_requires_foreground") }
        }
        floating.onSkip = { [weak probe] delta in
            guard let probe else { return }
            probe.seek(probe.position + delta)
        }
        log.add("app_created", ["claimedTarget": "iPhone 15 / iOS 26.6", "stage": "diagnostic-prototype"])
        probe.onChange?()
    }
}

@main
struct PromptLabApp: App {
    private let startup: Result<AppModel, Error> = Result { try AppModel() }
    var body: some Scene {
        WindowGroup {
            switch startup {
            case .success(let model): ProbeView(model: model)
            case .failure(let error): Text("初始化失败：\(error.localizedDescription)").padding()
            }
        }
    }
}

private struct ProbeView: View {
    @ObservedObject var probe: SpeechProbe
    @ObservedObject var floating: FloatingPrompt
    let log: Diagnostics
    @Environment(\.scenePhase) private var phase
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var shareError: String?

    init(model: AppModel) {
        probe = model.probe; floating = model.floating; log = model.log
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("中文悬浮提词 · 验证版").font(.title2.bold())
                Text("固定稿件，用来验证开拍拍摄时能否持续跟读。诊断只在本机，导出前不会发送。").font(.subheadline).foregroundStyle(.secondary)
                SampleLayerView(layer: floating.layer)
                    .frame(maxWidth: 320).frame(height: 400).background(.black).clipShape(RoundedRectangle(cornerRadius: 16))
                Text(probe.status).font(.headline)
                HStack {
                    Button("开始跟读") { probe.start() }.buttonStyle(.borderedProminent)
                    Button("停止") { probe.stop() }.buttonStyle(.bordered)
                    Button(floating.active ? "收起悬浮" : "开启悬浮") {
                        if floating.active { floating.stop() } else { floating.start() }
                    }.buttonStyle(.bordered).disabled(!floating.possible && !floating.active)
                }
                if let error = floating.errorMessage { Text(error).foregroundStyle(.orange) }
                HStack {
                    Button("回退十二字") { probe.seek(probe.position - 12) }
                    Button("从头开始") { probe.seek(0) }
                    Button("前进十二字") { probe.seek(probe.position + 12) }
                }.font(.footnote)
                Text("收到音频包：\(probe.bufferCount)　当前位置：\(probe.position)").font(.caption.monospacedDigit())
                Text("识别结果：\(probe.transcript)").font(.footnote)
                DisclosureGroup("查看固定测试稿") { Text(SampleScript.text).textSelection(.enabled) }
                Button("导出本次诊断") {
                    do { shareURL = try log.export(); sharing = true }
                    catch { shareError = error.localizedDescription }
                }
                if let error = shareError { Text(error).foregroundStyle(.orange) }
            }.padding()
        }
        .sheet(isPresented: $sharing) { if let shareURL { ShareSheet(url: shareURL) } }
        .onChange(of: phase) { _, value in
            log.add("scene", ["phase": String(describing: value)])
        }
    }
}

private struct SampleLayerView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    func makeUIView(context: Context) -> LayerHost {
        let host = LayerHost(); host.sampleLayer = layer; host.layer.addSublayer(layer); return host
    }
    func updateUIView(_ view: LayerHost, context: Context) { view.setNeedsLayout() }
    final class LayerHost: UIView {
        var sampleLayer: AVSampleBufferDisplayLayer?
        override func layoutSubviews() { super.layoutSubviews(); sampleLayer?.frame = bounds }
    }
}
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
