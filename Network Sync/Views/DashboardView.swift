//
//  DashboardView.swift
//  Newtowk Sync
//
//  Created by Anthony Terry on 6/8/26.
//


struct DashboardView: View {
    @Binding var isRunning: Bool
    @Binding var status: String
    @Binding var progress: Double
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("ISO Sync & Transcode Pipeline")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                Circle()
                    .fill(isRunning ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(isRunning ? "Pipeline Running" : "Ready")
            }
            .padding()
            
            Divider()
            
            // Progress Indicator
            VStack(alignment: .leading) {
                Text("Current Phase: \(status)")
                    .font(.headline)
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
            }
            .padding()
            
            Spacer()
            
            // Main Action Trigger
            Button(action: {
                startPipeline()
            }) {
                Text(isRunning ? "Stop Pipeline" : "Start Interleaved Pipeline")
                    .font(.title3)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .red : .blue)
            .padding()
        }
        .padding()
    }
    
    func startPipeline() {
        isRunning.toggle()
        if isRunning {
            status = "Mounting Cloud Store..."
            progress = 0.1
            // Call underlying Swift translation of your pipeline here
        } else {
            status = "Idle"
            progress = 0.0
        }
    }
}
