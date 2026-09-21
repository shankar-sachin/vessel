import Foundation

#if canImport(Speech) && os(iOS)
import Speech
import AVFoundation
#endif

/// Live speech-to-text, feeding the parser as you talk.
///
/// Speaking is the fastest way to log a meal and the one people will actually
/// keep doing, so this has to feel immediate: partial results stream out while
/// you're still talking rather than arriving in one lump at the end.
///
/// Transcription is forced **on-device**. A food diary is medical-adjacent
/// data, and sending it to Apple's servers for transcription would quietly
/// undo the promise that the log never leaves the phone.
@MainActor
public final class VoiceTranscriber: ObservableObject {

    /// What the transcriber is doing, so the UI never has to guess.
    public enum State: Equatable {
        case idle
        case preparing
        case listening
        case finished(String)
        case failed(Failure)
    }

    public enum Failure: Equatable {
        case microphonePermissionDenied
        case speechPermissionDenied
        case recognizerUnavailable
        case onDeviceUnavailable
        case audioSessionFailed
        case noSpeechDetected

        /// Plain language, and where it can be fixed.
        public var message: String {
            switch self {
            case .microphonePermissionDenied:
                return "Vessel needs microphone access to hear you. You can turn it on in Settings."
            case .speechPermissionDenied:
                return "Vessel needs permission to turn speech into text. You can turn it on in Settings."
            case .recognizerUnavailable:
                return "Speech recognition isn't available in your language on this device."
            case .onDeviceUnavailable:
                return "This device can't transcribe without sending audio to Apple, so Vessel won't use it. You can still type."
            case .audioSessionFailed:
                return "Vessel couldn't start recording. Another app may be using the microphone."
            case .noSpeechDetected:
                return "Didn't catch anything — try again a little closer."
            }
        }

        /// Whether Settings is where this gets resolved.
        public var isPermissionIssue: Bool {
            self == .microphonePermissionDenied || self == .speechPermissionDenied
        }
    }

    @Published public private(set) var state: State = .idle
    /// Text so far, updating as you speak.
    @Published public private(set) var transcript: String = ""
    /// Rough input level, 0...1, for a waveform.
    @Published public private(set) var audioLevel: Double = 0

    public var isListening: Bool { state == .listening || state == .preparing }

    public init() {}

    #if canImport(Speech) && os(iOS)

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private lazy var recognizer = SFSpeechRecognizer(locale: Locale.current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))

    // MARK: - Permissions

    /// Asks for both permissions, in the order the system prefers.
    ///
    /// Requested at the moment the user taps the microphone rather than on
    /// launch, so the prompt arrives with obvious context.
    public func requestPermissions() async -> Failure? {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return .speechPermissionDenied }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micGranted else { return .microphonePermissionDenied }

        return nil
    }

    // MARK: - Listening

    public func start() async {
        guard !isListening else { return }
        state = .preparing
        transcript = ""

        if let failure = await requestPermissions() {
            state = .failed(failure)
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            state = .failed(.recognizerUnavailable)
            return
        }
        // Refusing rather than falling back to server transcription: sending a
        // food diary to a server is not a trade-off to make silently.
        guard recognizer.supportsOnDeviceRecognition else {
            state = .failed(.onDeviceUnavailable)
            return
        }

        do {
            try configureAudioSession()
        } catch {
            state = .failed(.audioSessionFailed)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // Biases the recogniser toward words a food log actually contains.
        request.contextualStrings = Self.contextualStrings
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.meanLevel(of: buffer)
            Task { @MainActor in self?.audioLevel = level }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .failed(.audioSessionFailed)
            return
        }

        state = .listening

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.finish() }
                }
                if error != nil, self.isListening {
                    // An error after speech has been heard is usually the end of
                    // the utterance, not a failure worth showing.
                    self.transcript.isEmpty ? (self.state = .failed(.noSpeechDetected)) : self.finish()
                    self.teardown()
                }
            }
        }
    }

    public func stop() {
        guard isListening else { return }
        request?.endAudio()
        finish()
        teardown()
    }

    public func cancel() {
        teardown()
        transcript = ""
        state = .idle
    }

    // MARK: - Internals

    private func finish() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        state = text.isEmpty ? .failed(.noSpeechDetected) : .finished(text)
    }

    private func teardown() {
        task?.cancel()
        task = nil
        request = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // `.measurement` disables processing that would otherwise colour the
        // signal; `.duckOthers` lets music keep playing quietly underneath.
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// RMS level, compressed into something a waveform can use directly.
    private static func meanLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = sqrt(sum / Float(count))

        // Speech sits in a narrow band of raw RMS; this maps it onto 0...1 in a
        // way that actually moves visibly rather than hugging the floor.
        let decibels = 20 * log10(max(rms, 1e-7))
        return Double(max(0, min(1, (decibels + 50) / 50)))
    }

    #else

    // Non-iOS builds (the package compiles on macOS so tests run without a
    // simulator) get a transcriber that reports honestly rather than crashing.
    public func requestPermissions() async -> Failure? { .recognizerUnavailable }
    public func start() async { state = .failed(.recognizerUnavailable) }
    public func stop() {}
    public func cancel() { state = .idle }

    #endif

    /// Words the recogniser should expect.
    ///
    /// Food logging has a narrow vocabulary with several terms general speech
    /// models mis-hear — "grams" as "grahams", "sauteed" as "so tade".
    static let contextualStrings = [
        "grams", "millilitres", "milliliters", "tablespoon", "teaspoon",
        "sauteed", "poached", "quinoa", "acai", "gnocchi", "bruschetta",
        "espresso", "cappuccino", "kombucha", "edamame", "halloumi",
        "bloated", "bloating", "heartburn", "reflux", "nausea"
    ]
}
