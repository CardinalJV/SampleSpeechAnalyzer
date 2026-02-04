//
//  SpeechAnalyzer.swift
//  SampleSpeechAnalyzer
//
//  Created by Viranaiken Jessy on 02/02/26.
//

import Speech
import SwiftUI
import Foundation

enum TranscriptionError: Error {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case noInternetForModelDownload
    case audioFilePathNotFound
    
    var descriptionString: String {
        switch self {
            
        case .couldNotDownloadModel:
            return "Could not download the model."
        case .failedToSetupRecognitionStream:
            return "Could not set up the speech recognition stream."
        case .invalidAudioDataType:
            return "Unsupported audio format."
        case .localeNotSupported:
            return "This locale is not yet supported by SpeechAnalyzer."
        case .noInternetForModelDownload:
            return "The model could not be downloaded because the user is not connected to internet."
        case .audioFilePathNotFound:
            return "Couldn't write audio to file."
        }
    }
}

@Observable
final class SpeechManager {
    // Will handle the sequence of input
    private var inputSequence: AsyncStream<AnalyzerInput>?
    // Will push new flux in the sequence ⬆️
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    // Will convert input to the textual output
    private var transcriber: SpeechTranscriber?
    // Will handle the flux
    private var analyzer: SpeechAnalyzer?
    // Will handle the live transcription
    private var recognizerTask: Task<(), Error>?
    // Audio format expected by the transcriber / analyzer
    var analyzerFormat: AVAudioFormat?
    // Converter audio format
    var bufferConverter = BufferConverter()
    // Progress
    var downloadProgress: Progress?
    // Text processing
    var volatileTranscript: AttributedString = ""
    // Text processed
    var finalizedTranscript: AttributedString = ""
    // Set the default language
    static let locale = Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))
    // Init
    init() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("SpeechRecognizer authorized.")
                case .denied:
                    print("SpeechRecognizer denied.")
                case .notDetermined:
                    print("SpeechRecognizer notDetermined.")
                case .restricted:
                     print("SpeechRecognizer restricted")
                @unknown default:
                    print("Error unknown")
                }
            }
        }
    }
    // Set the transcriber
    func setUpTranscriber() async throws {
        /// Create the transcriber
        transcriber = SpeechTranscriber(
            /// Set the language
            locale: Locale.current,
            /// Define the options
            transcriptionOptions: [],
            /// Will handle temporary results
            reportingOptions: [.volatileResults],
            /// Will stock the time stamp
            attributeOptions: [.audioTimeRange]
        )
        /// Verify transcriber's availability
        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        /// Create a analyzer that will use the transcriber as a module
        analyzer = SpeechAnalyzer(modules: [transcriber])
        /// Verify the model's availability otherwise download it
        do {
            try await ensureModel(transcriber: transcriber, locale: Locale.current)
        } catch let error as TranscriptionError {
            print(error)
            return
        }
        /// Get the best audio format
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        guard let inputSequence else {
            return
        }
        /// Launch the recognization
        recognizerTask = Task {
            do {
                for try await case let result in transcriber.results {
                    let text = result.text
                    if result.isFinal {
                        finalizedTranscript += text
                        volatileTranscript = ""
                    } else {
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.4)
                    }
                }
            } catch {
                print("speech recognition failed")
            }
        }
        /// Launch the process
        try await analyzer?.start(inputSequence: inputSequence)
    }
    // Launch the stream
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }
        let converted = try self.bufferConverter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }
    // End the process
    public func finishTranscribing() async throws {
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
}

extension SpeechManager {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw TranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        } else {
            try await downloadIfNeeded(for: transcriber)
        }
    }
    
    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
        }
    }
    
    func releaseLocales() async {
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }
    }
}
