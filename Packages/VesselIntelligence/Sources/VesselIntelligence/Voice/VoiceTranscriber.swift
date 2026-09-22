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
        case noMicrophone
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
            case .noMicrophone:
                return "No microphone is available on this device, so Vessel can't listen. You can still type."
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

    /// Whether `inputNode` has ever been touched on this instance.
    ///
    /// Teardown must not be the thing that first wakes the input unit — that is
    /// the same fatal call, arriving on the cleanup path instead of the setup one.
    private var didTouchEngine = false
    private lazy var recognizer = SFSpeechRecognizer(locale: Locale.current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))

    // MARK: - Permissions

    /// Asks for both permissions, in the order the system prefers.
    ///
    /// Requested at the moment the user taps the microphone rather than on
    /// launch, so the prompt arrives with obvious context.
    ///
    /// Both handlers are `@Sendable`, and that is not decoration. Apple
    /// documents each as being called "on an arbitrary queue"; written as plain
    /// closures inside this `@MainActor` method they *inherit* main-actor
    /// isolation, because a non-`@Sendable` closure adopts the isolation of
    /// wherever it was written. The compiler is satisfied, and then the system
    /// calls the block on its own queue and Swift's isolation check kills the
    /// process:
    ///
    ///     BUG IN CLIENT OF LIBDISPATCH: Assertion failed:
    ///     Block was not expected to execute on queue [com.apple.main-thread]
    ///
    /// This fired the instant the microphone was tapped — before any audio,
    /// which is why looking at the audio path first was looking in the wrong
    /// place. Marking the closures `@Sendable` makes them non-isolated, which
    /// is what they always were, and makes the compiler check that nothing
    /// main-actor-bound is touched inside. `CheckedContinuation` is `Sendable`,
    /// so resuming across the boundary is exactly what it is for.
    public func requestPermissions() async -> Failure? {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return .speechPermissionDenied }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
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

        // Ask the *session* whether there is an input before asking the engine.
        //
        // Touching `audioEngine.inputNode` is not a passive read: it makes
        // AVAudioEngine enable input on the remote IO audio unit there and then.
        // Where there is no usable input that call fails inside CoreAudio —
        //
        //     AURemoteIO.cpp:1135 failed: -10851 (enable 1, outf< 2 ch, 0 Hz …>)
        //
        // — and takes the app with it. The session knows the same thing and
        // answering the question costs nothing, so the engine is never asked
        // until there is something for it to listen to.
        let session = AVAudioSession.sharedInstance()
        guard session.isInputAvailable, session.inputNumberOfChannels > 0, session.sampleRate > 0 else {
            releaseSession()
            state = .failed(.noMicrophone)
            return
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Belt and braces, because `installTap` *traps* on an invalid format
        // rather than throwing: a microphone held by another app can still
        // report a zero-rate format after the session said it was there.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            releaseSession()
            state = .failed(.noMicrophone)
            return
        }
        didTouchEngine = true

        input.removeTap(onBus: 0)

        // The tap block runs on the audio render thread. Written as a plain
        // closure it *inherits* this class's `@MainActor` isolation — which
        // compiles, and then traps the first time a real microphone delivers a
        // buffer. That is why this only ever died on hardware: the simulator has
        // no microphone, so no buffer ever arrived to violate the assumption.
        //
        // `@Sendable` makes the compiler check what the closure touches instead
        // of assuming it runs where it does not, and the one deliberate
        // exception is named below rather than left implicit.
        nonisolated(unsafe) let sink = request   // Speech documents this as safe to feed from the audio thread
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
            sink.append(buffer)
            let level = meanLevel(of: buffer)
            Task { @MainActor in self?.audioLevel = level }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            // Leave nothing running: a half-started engine keeps the audio
            // session active and blocks the next attempt.
            teardown()
            state = .failed(.audioSessionFailed)
            return
        }

        state = .listening

        // Same hazard as the tap: this handler is called on whichever queue
        // Speech feels like using. Everything the main actor needs is pulled out
        // into plain Sendable values here, and only those cross the hop.
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let didError = error != nil

            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if isFinal {
                    self.finish()
                    self.teardown()
                    return
                }
                if didError, self.isListening {
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
        // Detach the audio *before* closing the request. The other order leaves
        // a window in which a buffer already in flight on the audio thread is
        // appended to a request that has been ended — which throws, from a
        // thread with nothing to catch it.
        detachAudio()
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

    /// Safe to call at any point, including before anything started.
    private func teardown() {
        detachAudio()
        task?.cancel()
        task = nil
        request = nil
        audioLevel = 0
        releaseSession()
    }

    /// Stops the engine and unhooks the tap, so no further buffers can arrive.
    private func detachAudio() {
        guard didTouchEngine else { return }
        if audioEngine.isRunning { audioEngine.stop() }
        // Removing a tap that was never installed is harmless; removing one
        // that was is essential, or the next start installs a second.
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    /// Hands the audio session back without going near the engine.
    private func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // `.measurement` disables processing that would otherwise colour the
        // signal; `.duckOthers` lets music keep playing quietly underneath.
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
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

#if canImport(Speech) && os(iOS)

/// RMS level, compressed into something a waveform can use directly.
///
/// A free function rather than a static member of `VoiceTranscriber`, because a
/// static on a `@MainActor` class is itself main-actor isolated — and this is
/// called from the audio render thread on every buffer.
private func meanLevel(of buffer: AVAudioPCMBuffer) -> Double {
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

#endif
