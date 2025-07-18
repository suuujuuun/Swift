import SwiftUI

struct DefinitionResponse: Decodable {
    let word: String
    let meanings: [Meaning]
    
    struct Meaning: Decodable {
        let definitions: [Definition]
    }
    
    struct Definition: Decodable {
        let definition: String
    }
    
    var firstDefinition: String? {
        meanings.first?.definitions.first?.definition
    }
}



struct IconBubble: View {
    let systemName: String

    var body: some View {
        BubbleView(item: CircleWord(word: "", score: 1.0, fixedRadius: 25)) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var inputWord: String = ""
    @State private var bubbles: [Bubble] = []
    @State private var appeared: Set<UUID> = []
    @State private var isEditingInput: Bool = true
    @FocusState private var inputIsFocused: Bool
    
    @State private var lastRadius: CGFloat?
    
    @State private var scalingBubbleId: UUID?
    @State private var definition: (response: DefinitionResponse, position: CGPoint)?
    @State private var isLoadingDefinition: Bool = false
    @State private var showingLicense = false
    @State private var showingHistory = false
    @State private var searchHistory: [String] = []
    
    private let centralBubbleId = UUID()
    private let initialMessage = "Enter a word"

    struct Bubble: Identifiable {
        let id: UUID
        let item: CircleWord
        var position: CGPoint
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()

                // Central Bubble
                BubbleView(item: createCentralBubble()) {
                    if isEditingInput {
                        ZStack {
                            if inputWord.isEmpty {
                                Text(initialMessage)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            TextField("", text: $inputWord, onCommit: {
                                if !inputWord.isEmpty {
                                    Task { await findSynonyms(for: inputWord, viewSize: geo.size) }
                                }
                            })
                            .focused($inputIsFocused)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .onChange(of: inputWord) {
                                lastRadius = nil
                            }
                        }
                    } else { Text(inputWord) }
                }
                .position(CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                .scaleEffect(scalingBubbleId == centralBubbleId ? 0.95 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: scalingBubbleId)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: inputWord)
                .onAppear {
                    self.inputWord = ""
                    self.isEditingInput = true
                    self.inputIsFocused = true
                }
                .onTapGesture { if !isEditingInput { resetToInitialState(viewSize: geo.size) } }
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onChanged { _ in
                            if !isEditingInput { scalingBubbleId = centralBubbleId }
                        }
                        .onEnded { _ in
                            if !isEditingInput {
                                isLoadingDefinition = true
                                let centerPosition = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                Task { await fetchDefinition(for: inputWord, at: centerPosition) }
                            }
                        }
                )
                
                // Synonym Bubbles
                if !isEditingInput {
                    ForEach(bubbles) { bubble in
                        BubbleView(item: bubble.item) { Text(bubble.item.word) }
                        .position(bubble.position)
                        .scaleEffect(scalingBubbleId == bubble.id ? 0.95 : 1.0)
                        .opacity(scalingBubbleId == bubble.id ? 0.8 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: scalingBubbleId)
                        .onTapGesture { Task { await findSynonyms(for: bubble.item.word, viewSize: geo.size) } }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onChanged { _ in scalingBubbleId = bubble.id }
                                .onEnded { _ in
                                    isLoadingDefinition = true
                                    Task { await fetchDefinition(for: bubble.item.word, at: bubble.position) }
                                }
                        )
                    }
                }
                
                // Scrim (background overlay to close definition)
                if definition != nil {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                definition = nil
                            }
                        }
                }
                
                // Definition View or Loading Indicator
                ZStack {
                    Group {
                        if isLoadingDefinition {
                            AnyView(ProgressView().scaleEffect(1.5))
                        } else if let defData = definition {
                            let targetY = computeTargetY(for: defData.position, geoHeight: geo.size.height)
                            
                            AnyView(DefinitionView(word: defData.response.word, definition: defData.response.firstDefinition ?? "No definition found.")
                                .position(x: geo.size.width / 2, y: targetY)
                                .transition(.scale.combined(with: .opacity)))
                        } else {
                            EmptyView()
                        }
                    }
                }
                
                // Icons for License and History
                if isEditingInput {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            // 1. 테마 변경 버튼
                            Button(action: { themeManager.cycleTheme() }) {
                                IconBubble(systemName: "paintbrush")
                            }

                            // 2. 검색 기록 버튼
                            Button(action: { showingHistory.toggle() }) {
                                IconBubble(systemName: "clock")
                            }
                            .sheet(isPresented: $showingHistory) {
                                HistoryView(isPresented: $showingHistory, searchHistory: $searchHistory) { word in
                                    Task { await findSynonyms(for: word, viewSize: geo.size) }
                                }
                                .environmentObject(themeManager)
                            }
                            
                            // 3. 라이선스 버튼
                            Button(action: { showingLicense.toggle() }) {
                                IconBubble(systemName: "questionmark.circle")
                            }
                            .sheet(isPresented: $showingLicense) {
                                LicenseView(isPresented: $showingLicense)
                                    .environmentObject(themeManager)
                            }
                        }
                        .padding()
                        
                        // Developed by text
                        if inputWord.isEmpty {
                            Text("Developed by Kyle Lee")
                                .font(.caption)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, 5)
                        }
                    }
                }
            }
        }
    }
    
    func resetToInitialState(viewSize: CGSize) {
        if !isEditingInput {
            withAnimation(.easeOut(duration: 0.3)) {
                for i in bubbles.indices {
                    bubbles[i].position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                }
                appeared.removeAll()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                bubbles = []
                lastRadius = CircleWord(word: inputWord, score: 1.0).radius
                inputWord = ""
                isEditingInput = true
                inputIsFocused = true
            }
        }
    }

    private func createCentralBubble() -> CircleWord {
        if isEditingInput && inputWord.isEmpty && lastRadius != nil {
            return CircleWord(word: initialMessage, score: 1.0, fixedRadius: lastRadius)
        }
        return CircleWord(word: inputWord.isEmpty ? initialMessage : inputWord, score: 1.0)
    }
    
    func findSynonyms(for word: String, viewSize: CGSize) async {
        await MainActor.run {
            self.inputWord = word
            withAnimation { self.definition = nil }
            if !searchHistory.contains(word) { searchHistory.insert(word, at: 0) }
        }
        let wordToSearch = word
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.2)) {
                for i in bubbles.indices {
                    bubbles[i].position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                }
                appeared.removeAll()
            }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        await MainActor.run {
            bubbles = []
            isEditingInput = false
        }
        guard !wordToSearch.isEmpty else {
            await MainActor.run { isEditingInput = true }
            return
        }
        let encodedWord = wordToSearch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let apiUrl = "https://kyle-synonyms-api.onrender.com/synonyms?word=\(encodedWord)"
        guard let url = URL(string: apiUrl) else {
            await MainActor.run { inputWord = "Invalid API URL" }
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run { inputWord = "Word not found. Tap to try again." }
                return
            }
            let decodedWords = try JSONDecoder().decode([CircleWord].self, from: data)
            if decodedWords.isEmpty {
                await MainActor.run { inputWord = "Word not found. Tap to try again." }
                return
            }
            await MainActor.run {
                self.inputWord = wordToSearch
                let finalLayout = BubbleLayoutManager.layoutBubbles(in: viewSize, wordsToLayout: decodedWords, centralWord: wordToSearch)
                let centerPosition = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                self.bubbles = finalLayout.map { Bubble(id: $0.id, item: $0.item, position: centerPosition) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    for (index, finalBubble) in finalLayout.enumerated() {
                        if let bubbleIndex = self.bubbles.firstIndex(where: { $0.id == finalBubble.id }) {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.03)) {
                                self.bubbles[bubbleIndex].position = finalBubble.position
                            }
                        }
                    }
                    withAnimation(.spring().delay(0.2)) { self.appeared = Set(self.bubbles.map { $0.id }) }
                }
            }
        } catch {
            await MainActor.run { inputWord = "Server connection failed." }
            print("Error fetching JSON: \(error)")
        }
    }

    func fetchDefinition(for word: String, at position: CGPoint) async {
        isLoadingDefinition = true
        definition = nil
        
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(word)") else {
            await MainActor.run {
                isLoadingDefinition = false
                scalingBubbleId = nil
            }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedResponse = try JSONDecoder().decode([DefinitionResponse].self, from: data)
            if let firstDef = decodedResponse.first {
                await MainActor.run {
                    withAnimation {
                        self.definition = (response: firstDef, position: position)
                    }
                }
            }
        } catch {
            print("Error fetching definition: \(error)")
            await MainActor.run { withAnimation { self.definition = nil } }
        }
        await MainActor.run {
            isLoadingDefinition = false
            scalingBubbleId = nil
        }
    }
    
    private func index(of bubble: Bubble) -> Int {
        bubbles.firstIndex { $0.id == bubble.id } ?? 0
    }
    
    private func computeTargetY(for pos: CGPoint, geoHeight: CGFloat) -> CGFloat {
        let definitionViewHeight: CGFloat = 200 // Approximate height of the definition view
        let bubbleRadius = CircleWord(word: "", score: 1.0).radius
        
        let targetY: CGFloat
        if pos.y + bubbleRadius + 80 + definitionViewHeight > geoHeight { // If definition view goes off screen below
            targetY = pos.y - bubbleRadius - 80 - definitionViewHeight
        } else { // Otherwise, place it below
            targetY = pos.y + bubbleRadius + 80
        }
        return targetY
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MotionManager())
            .environmentObject(ThemeManager())
    }
}
