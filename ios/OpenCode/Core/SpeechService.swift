import AVFoundation
import Combine
import Speech

@MainActor final class SpeechService: ObservableObject {
    @Published var recording = false
    @Published var transcript = ""
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    private let synthesizer = AVSpeechSynthesizer()

    func start() async {
        guard !recording else { return }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard authorized && microphone else { error = "Allow microphone and speech recognition in iOS Settings to dictate."; return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else { error = "Speech recognition is unavailable for this language."; return }
        do {
            stop(); transcript = ""
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else { throw APIError(message: "No microphone input is available") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true; engine.prepare(); try engine.start(); recording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.recording else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
        } catch { stop(); self.error = error.localizedDescription }
    }
    func stop() {
        recording = false; engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func speak(_ text: String) {
        stop(); synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier)
        synthesizer.speak(utterance)
    }
}
