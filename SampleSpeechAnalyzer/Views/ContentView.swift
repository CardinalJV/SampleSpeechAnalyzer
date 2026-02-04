//
//  ContentView.swift
//  SampleSpeechAnalyzer
//
//  Created by Viranaiken Jessy on 02/02/26.
//

import SwiftUI

struct ContentView: View {
    
    let speechManager: SpeechManager
    let recorder: Recorder
    
    init() {
        self.speechManager = SpeechManager()
        self.recorder = Recorder(transcriber: self.speechManager)
    }
    
    var body: some View {
        VStack {
            Button("Record") {
                recorder.playRecording()
            }
            
            liveRecordingView
        }
        .padding()
    }
    
    @ViewBuilder
    var liveRecordingView: some View {
        Text(speechManager.finalizedTranscript + speechManager.volatileTranscript)
            .font(.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
    }
}

#Preview {
    ContentView()
}
