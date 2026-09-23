import SwiftUI
import SwiftData
import PhotosUI
import CoreImage
import VesselCore
import VesselDesign
import VesselNutrition
import VesselVision

/// Logs food from a photo or a barcode.
///
/// Ordered by how much the result can be trusted, which is also the order the
/// UI presents: a **barcode** gives exact label nutrition, **text on packaging**
/// usually names the product outright, and **image classification** is the
/// coarse last resort. Presenting a guess with the same confidence as a scanned
/// label would be the dishonest option, so each route says what it is.
struct CaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickedItem: PhotosPickerItem?
    @State private var image: CIImage?
    @State private var preview: Image?
    @State private var reading: PlateReading?
    @State private var product: PackagedProduct?
    @State private var barcodeInput = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var selected: Set<String> = []

    /// A photo dropped onto the Diet log on iPad, read as soon as the sheet opens.
    var droppedImage: Data? = nil

    private let recognizer = FoodRecognizer()
    private let search = FoodSearch()

    var body: some View {
        NavigationStack {
            Form {
                sourceSection

                if isWorking {
                    Section {
                        HStack(spacing: Layout.md) {
                            ProgressView()
                            Text("Reading the photo…")
                                .font(Typography.callout)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }

                if let product { productSection(product) }
                if let reading, !reading.isEmpty { readingSection(reading) }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.caution)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .navigationTitle("From a photo")
            .navigationBarTitleDisplayMode(.inline)
            .vesselSheetBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .tint(Palette.diet)
        }
        .onChange(of: pickedItem) { _, item in
            Task { await load(item) }
        }
        .task {
            if let droppedImage { await read(droppedImage) }
        }
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section {
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .foregroundStyle(Palette.diet)
            }
            .accessibilityIdentifier("capturePickPhoto")

            if let preview {
                preview
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.radiusMedium, style: .continuous))
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Layout.xs)
            }

            HStack(spacing: Layout.sm) {
                TextField("Or type a barcode", text: $barcodeInput)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("captureBarcodeField")
                Button("Look up") {
                    Task { await lookUpBarcode() }
                }
                .buttonStyle(.borderless)
                .disabled(barcodeInput.count < 8)
            }
        } header: {
            Text("Source")
        } footer: {
            // Saying plainly which route is trustworthy, so a coarse guess is
            // never mistaken for a scanned label.
            Text("A barcode gives exact figures from the product's label. A photo is read on device and gives a starting point you should check.")
        }
    }

    private func productSection(_ product: PackagedProduct) -> some View {
        Section("Scanned product") {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                Text("\(Int(product.nutrientsPer100g.kilocalories)) kcal / 100 g")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                if !product.tags.isEmpty {
                    Text(product.tags.joined(separator: " · "))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.diet.opacity(0.85))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func readingSection(_ reading: PlateReading) -> some View {
        Group {
            if !reading.candidates.isEmpty {
                Section {
                    ForEach(reading.candidates) { candidate in
                        CandidateRow(
                            candidate: candidate,
                            isSelected: selected.contains(candidate.label)
                        ) {
                            if selected.contains(candidate.label) {
                                selected.remove(candidate.label)
                            } else {
                                selected.insert(candidate.label)
                            }
                        }
                    }
                } header: {
                    Text("What Vessel saw")
                } footer: {
                    if reading.regionCount > 1 {
                        // Offered as a hint, not acted on: saliency separates
                        // things sitting apart on a plate but cannot tell the
                        // components of a stew from each other.
                        Text("Looks like about \(reading.regionCount) things on the plate. Tap the ones that are right.")
                    } else {
                        Text("Tap what's right. These are guesses from the image, not measurements.")
                    }
                }
            }

            if !reading.recognizedText.isEmpty {
                Section("Text on the packaging") {
                    ForEach(reading.recognizedText.prefix(5), id: \.self) { line in
                        Button {
                            barcodeInput = ""
                            Task { await searchText(line) }
                        } label: {
                            Text(line)
                                .font(Typography.callout)
                                .foregroundStyle(Palette.diet)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Behaviour

    private var canSave: Bool { product != nil || !selected.isEmpty }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        reading = nil
        selected = []
        isWorking = true
        defer { isWorking = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "Vessel couldn't read that image."
            return
        }
        await read(data)
    }

    /// Recognises food in an image, however it arrived — picked or dropped.
    private func read(_ data: Data) async {
        errorMessage = nil
        reading = nil
        selected = []
        isWorking = true
        defer { isWorking = false }

        guard let ciImage = CIImage(data: data) else {
            errorMessage = "Vessel couldn't read that image."
            return
        }

        image = ciImage
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) { preview = Image(uiImage: uiImage) }
        #endif

        let result = await recognizer.read(image: ciImage)
        reading = result

        // Pre-select the strongest guess so the common case is one tap, while
        // leaving it visible and revocable.
        if let best = result.candidates.first, best.confidence > 0.5 {
            selected.insert(best.label)
        }

        if result.isEmpty {
            errorMessage = "Nothing recognisable in that photo. You can still search or type it."
        }
    }

    private func lookUpBarcode() async {
        let code = barcodeInput.trimmingCharacters(in: .whitespaces)
        guard code.count >= 8 else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            product = try await OpenFoodFactsClient.shared.product(forBarcode: code)
        } catch {
            product = nil
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't look that barcode up."
        }
    }

    private func searchText(_ line: String) async {
        guard let match = search.search(line, limit: 1).first else {
            errorMessage = "No match for “\(line)”."
            return
        }
        selected.insert(match.food.name)
        reading = PlateReading(
            candidates: [FoodCandidate(
                label: match.food.displayName,
                confidence: match.score,
                matched: match.food,
                areaFraction: nil
            )] + (reading?.candidates ?? []),
            regionCount: reading?.regionCount ?? 0,
            recognizedText: reading?.recognizedText ?? []
        )
    }

    private func save() {
        let entry = FoodEntry(
            loggedAt: Date(),
            slot: MealSlot.inferred(from: Date()),
            source: product != nil ? .barcode : .photo,
            parseConfidence: product != nil ? 1.0 : 0.5
        )
        context.insert(entry)

        var items: [FoodItem] = []

        if let product {
            let grams = product.servingGrams ?? 100
            let item = FoodItem(
                foodID: "off:\(product.barcode)",
                displayName: product.name,
                brand: product.brand,
                quantity: 1,
                unit: .serving,
                grams: grams,
                nutrients: product.nutrientsPer100g.scaled(by: grams / 100),
                tags: product.tags
            )
            context.insert(item)
            items.append(item)
        }

        for label in selected {
            guard let candidate = reading?.candidates.first(where: { $0.label == label }) else { continue }
            guard let food = candidate.matched ?? search.search(label, limit: 1).first?.food else { continue }
            let grams = food.defaultPortion?.grams ?? 100
            let item = FoodItem(
                foodID: food.id,
                displayName: food.displayName,
                quantity: 1,
                unit: .serving,
                grams: grams,
                nutrients: food.nutrients(forGrams: grams),
                tags: food.tags
            )
            context.insert(item)
            items.append(item)
        }

        guard !items.isEmpty else {
            context.delete(entry)
            return
        }

        entry.items = items
        try? context.save()
        Task { await StreakCoordinator.refresh(context: context) }
        dismiss()
    }
}

/// One thing the classifier thinks it saw.
private struct CandidateRow: View {
    let candidate: FoodCandidate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Layout.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Palette.diet : Palette.inkTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.matched.map { FoodName($0.displayName).title } ?? candidate.label.capitalized)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: Layout.xs) {
                        Text("saw “\(candidate.label)”")
                        if let food = candidate.matched {
                            Text("·")
                            Text("\(Int(food.nutrientsPer100g.kilocalories)) kcal / 100 g")
                        }
                    }
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                }

                Spacer(minLength: Layout.xs)

                // The raw confidence, shown rather than hidden behind a word:
                // "62%" tells you more about whether to trust it than "likely".
                Text("\(Int(candidate.confidence * 100))%")
                    .font(Typography.numeric)
                    .foregroundStyle(candidate.confidence > 0.5 ? Palette.positive : Palette.caution)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
