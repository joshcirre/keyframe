import SwiftUI

struct AIPresetGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var prompt = ""
    @State private var generatedSetup: AIGeneratedSetup?
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedMIDIInput: String? = "__none__"
    @State private var isApplying = false
    
    private let generator = AIPresetGeneratorService.shared
    private let catalog = PluginCatalogService.shared
    private let midiEngine = MIDIEngine.shared
    
    // Rotating prompt presets
    private static let promptPresets = [
        "Warm synth pad with lush reverb for worship",
        "Punchy bass and bright lead for electronic",
        "Classic FM electric piano with chorus",
        "Orchestral strings with brass section",
        "Ambient textures with delay and reverb",
        "Vintage analog poly synth for 80s sounds",
        "Mellow Rhodes with tape delay",
        "Aggressive lead synth for rock",
        "Soft pad layers for cinematic underscore",
        "Funky clavinet with phaser effect"
    ]
    
    @AppStorage("aiPromptPresetIndex") private var promptPresetIndex = 0
    
    init() {
        // Cycle to next preset on each open
        let nextIndex = (UserDefaults.standard.integer(forKey: "aiPromptPresetIndex") + 1) % Self.promptPresets.count
        UserDefaults.standard.set(nextIndex, forKey: "aiPromptPresetIndex")
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                
                ZStack {
                    // Background
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()
                    
                    // Content
                    if catalog.isScanning {
                        catalogScanningView
                    } else if catalog.instrumentCatalog.isEmpty {
                        catalogEmptyView
                    } else if let setup = generatedSetup {
                        resultsView(setup, isLandscape: isLandscape)
                    } else {
                        promptView(isLandscape: isLandscape)
                    }
                }
            }
            .navigationTitle("AI Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                AISettingsView()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Scanning View
    
    private var catalogScanningView: some View {
        VStack(spacing: 20) {
            ProgressView(value: catalog.scanProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 300)
            
            Text("Scanning plugins...")
                .font(.headline)
            
            Text("\(Int(catalog.scanProgress * 100))%")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Empty Catalog View
    
    private var catalogEmptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            
            Text("Scan Plugins First")
                .font(.title2.bold())
            
            Text("Build the plugin catalog to enable AI suggestions")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task { await catalog.buildCatalog() }
            } label: {
                Label("Scan Plugins", systemImage: "magnifyingglass")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
    }
    
    // MARK: - Prompt View
    
    private func promptView(isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            // Stats bar
            HStack(spacing: 16) {
                Label("\(catalog.instrumentCatalog.count)", systemImage: "pianokeys")
                Label("\(catalog.effectCatalog.count)", systemImage: "waveform")
                Spacer()
                if !generator.hasAPIKey {
                    Label("No API Key", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            
            if isLandscape {
                // Landscape: side by side
                HStack(spacing: 0) {
                    // Left: Examples
                    examplesPanel
                        .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    // Right: Input
                    inputPanel
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Portrait: stacked
                ScrollView {
                    VStack(spacing: 24) {
                        examplesPanel
                        inputPanel
                    }
                    .padding()
                }
            }
        }
    }
    
    private var examplesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DESCRIBE YOUR SOUND")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            // Show current preset suggestion prominently
            Button {
                prompt = Self.promptPresets[promptPresetIndex]
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.orange)
                    Text(Self.promptPresets[promptPresetIndex])
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Text("USE")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            Text("OR TRY")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                exampleButton("Synthy EP with strings and reverb")
                exampleButton("Warm analog pad for ambient music")
            }
            
            Spacer(minLength: 0)
        }
        .padding()
    }
    
    private var inputPanel: some View {
        VStack(spacing: 16) {
            TextField("Describe your ideal sound setup...", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(Color(uiColor: .tertiarySystemBackground))
                .cornerRadius(12)
                .lineLimit(3...8)
                .autocorrectionDisabled(false)
                .textInputAutocapitalization(.sentences)
            
            Button {
                generate()
            } label: {
                HStack(spacing: 8) {
                    if generator.isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(generator.isGenerating ? "Generating..." : "Generate Setup")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(prompt.isEmpty || generator.isGenerating || !generator.hasAPIKey ? Color.gray : Color.orange)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(prompt.isEmpty || generator.isGenerating || !generator.hasAPIKey)
            
            Spacer(minLength: 0)
        }
        .padding()
    }
    
    private func exampleButton(_ text: String) -> some View {
        Button {
            prompt = text
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.orange)
            }
            .padding()
            .background(Color(uiColor: .tertiarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Results View
    
    private func resultsView(_ setup: AIGeneratedSetup, isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            // Summary header
            Text(setup.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
            
            // Channel cards
            ScrollView {
                if isLandscape {
                    // Landscape: horizontal scroll or grid
                    LazyHStack(spacing: 16) {
                        ForEach(Array(setup.channels.enumerated()), id: \.offset) { index, channel in
                            channelCard(channel, index: index + 1)
                                .frame(width: 280)
                        }
                    }
                    .padding()
                } else {
                    // Portrait: vertical list
                    LazyVStack(spacing: 12) {
                        ForEach(Array(setup.channels.enumerated()), id: \.offset) { index, channel in
                            channelCard(channel, index: index + 1)
                        }
                    }
                    .padding()
                }
            }
            
            // MIDI Input Selection
            VStack(spacing: 8) {
                Text("MIDI INPUT FOR NEW CHANNELS")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Picker("MIDI Input", selection: $selectedMIDIInput) {
                    Text("NONE").tag("__none__" as String?)
                    Text("ANY").tag(nil as String?)
                    
                    ForEach(midiEngine.connectedSources) { source in
                        Text(source.name.uppercased()).tag(source.name as String?)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color(uiColor: .tertiarySystemBackground))
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    generatedSetup = nil
                    prompt = ""
                } label: {
                    Text("Start Over")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                Button {
                    applySetup(setup)
                } label: {
                    HStack(spacing: 8) {
                        if isApplying {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(isApplying ? "Applying..." : "Apply Setup")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isApplying ? Color.gray : Color.orange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isApplying)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }
    
    private func channelCard(_ channel: AIGeneratedChannel, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("CH \(index)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(4)
                
                Text(channel.suggestedName)
                    .font(.headline)
                
                Spacer()
            }
            
            Divider()
            
            // Instrument
            HStack(spacing: 8) {
                Image(systemName: "pianokeys")
                    .foregroundColor(.orange)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.instrumentName)
                        .font(.subheadline.bold())
                    if let preset = channel.presetName {
                        Text(preset)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Effects
            if !channel.effects.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(.purple)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(channel.effects.enumerated()), id: \.offset) { _, effect in
                            HStack(spacing: 4) {
                                Text(effect.effectName)
                                    .font(.caption)
                                if let preset = effect.presetName {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(preset)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            
            // Reasoning
            if let reasoning = channel.reasoning, !reasoning.isEmpty {
                Text(reasoning)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func generate() {
        Task {
            do {
                let setup = try await generator.generateSetup(prompt: prompt)
                generatedSetup = setup
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func applySetup(_ setup: AIGeneratedSetup) {
        isApplying = true
        Task {
            await generator.applySetup(setup, midiSourceName: selectedMIDIInput)
            isApplying = false
            dismiss()
        }
    }
}

// MARK: - Settings View

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var apiKey: String = ""
    @State private var selectedProvider: AIPresetGeneratorService.AIProvider = .anthropic
    
    private let generator = AIPresetGeneratorService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(AIPresetGeneratorService.AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                } header: {
                    Text("AI Provider")
                } footer: {
                    Text(providerDescription)
                }
                
                Section {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("API Key")
                } footer: {
                    if generator.hasAPIKey && apiKey.isEmpty {
                        Label("Using bundled key", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text(apiKeyHelp)
                    }
                }
                
                Section {
                    HStack {
                        Text("Instruments")
                        Spacer()
                        Text("\(PluginCatalogService.shared.instrumentCatalog.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Effects")
                        Spacer()
                        Text("\(PluginCatalogService.shared.effectCatalog.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Rescan Plugins") {
                        Task { await PluginCatalogService.shared.buildCatalog() }
                    }
                } header: {
                    Text("Plugin Catalog")
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKey = UserDefaults.standard.string(forKey: "ai_api_key") ?? ""
                selectedProvider = generator.apiProvider
            }
        }
    }
    
    private var providerDescription: String {
        switch selectedProvider {
        case .anthropic:
            return "Claude Sonnet - excellent at structured output"
        case .openai:
            return "GPT-5 Mini - fast and cost-effective"
        }
    }
    
    private var apiKeyHelp: String {
        switch selectedProvider {
        case .anthropic:
            return "Get your key at console.anthropic.com"
        case .openai:
            return "Get your key at platform.openai.com"
        }
    }
    
    private func save() {
        if !apiKey.isEmpty {
            generator.apiKey = apiKey
        }
        generator.apiProvider = selectedProvider
    }
}

#Preview {
    AIPresetGeneratorView()
}
