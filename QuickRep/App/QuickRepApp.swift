import SwiftUI
import SwiftData

@main
struct QuickRepApp: App {
    var body: some Scene {
        WindowGroup {
            TrainingHomeScreen()
        }
        .modelContainer(for: [
            WorkoutNote.self,
            WorkoutHistoryRecord.self,
            ExerciseLibraryEntry.self,
        ])
    }
}

struct TrainingHomeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutHistoryRecord.finishedAt, order: .reverse)
    private var historyRecords: [WorkoutHistoryRecord]
    @Query(sort: \WorkoutNote.updatedAt, order: .reverse)
    private var workoutNotes: [WorkoutNote]

    @State private var isPresentingEditor = false
    @State private var selectedHistoryRecord: WorkoutHistoryRecord?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if historyRecords.isEmpty {
                        Text("还没有训练记录，点击“开始训练”创建第一条。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(historyRecords) { record in
                            Button {
                                selectedHistoryRecord = record
                            } label: {
                                WorkoutHistoryRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("训练")
            .navigationDestination(isPresented: isPresentingHistoryDetail) {
                if let selectedHistoryRecord {
                    TrainingHistoryDetailScreen(record: selectedHistoryRecord)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Label(primaryWorkoutButtonTitle, systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background {
                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemBackground).opacity(0),
                            Color(uiColor: .systemBackground).opacity(0.72),
                            Color(uiColor: .systemBackground).opacity(0.94),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            TrainingEditorScreen(
                initialRawText: "",
                onFinishWorkout: finalizeWorkout(with:)
            )
        }
    }

    private var primaryWorkoutButtonTitle: String {
        Self.primaryWorkoutButtonTitle(for: workoutNotes.first)
    }

    static func primaryWorkoutButtonTitle(for draftWorkoutNote: WorkoutNote?) -> String {
        guard
            let draftWorkoutNote,
            draftWorkoutNote.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return "开始训练"
        }

        return "继续训练"
    }

    private func finalizeWorkout(with finalizedRawText: String) {
        do {
            try TrainingHistoryStore.recordFinishedWorkout(
                finalizedRawText: finalizedRawText,
                draftWorkoutNote: workoutNotes.first,
                modelContext: modelContext
            )
            isPresentingEditor = false
        } catch {
            QuickRepDiagnostics.log(
                "Failed to finalize workout from home screen: \(error.localizedDescription)"
            )
        }
    }

    private var isPresentingHistoryDetail: Binding<Bool> {
        Binding(
            get: { selectedHistoryRecord != nil },
            set: { isPresented in
                if !isPresented {
                    selectedHistoryRecord = nil
                }
            }
        )
    }
}

private struct TrainingHistoryDetailScreen: View {
    let record: WorkoutHistoryRecord

    var body: some View {
        TrainingTextEditor(
            text: .constant(record.rawText),
            isEditable: false,
            rightGutterWidth: 0
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .navigationTitle("训练记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(
                    record.finishedAt,
                    format: .dateTime.year().month().day().hour().minute()
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkoutHistoryRow: View {
    let record: WorkoutHistoryRecord

    var body: some View {
        let entries = record.historyCardEntries

        VStack(alignment: .leading, spacing: 16) {
            Text(record.historyCardDateText)
                .font(.body.monospaced())

            HStack(alignment: .top, spacing: 24) {
                historyColumn(title: "动作", values: entries.map(\.exerciseName))
                historyColumn(title: "最佳组", values: entries.map(\.bestSetText))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func historyColumn(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)

            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(.body.monospaced())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkoutHistoryCardEntry: Equatable {
    let exerciseName: String
    let bestSetText: String
}

extension WorkoutHistoryRecord {
    var historyCardDateText: String {
        Self.historyDateFormatter.string(from: finishedAt)
    }

    var historyCardEntries: [WorkoutHistoryCardEntry] {
        let parseResult = WorkoutTextParser.parse(rawText: rawText)
        let planLinesByExerciseBlock = Dictionary(
            grouping: parseResult.planLines,
            by: \.exerciseBlockId
        )

        return parseResult.exerciseBlocks.compactMap { block in
            guard
                let planLines = planLinesByExerciseBlock[block.id],
                let bestLine = planLines.bestHistoryLine
            else {
                return nil
            }

            return WorkoutHistoryCardEntry(
                exerciseName: block.exerciseName,
                bestSetText: bestLine.historySetText
            )
        }
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension Array where Element == PlanLine {
    var bestHistoryLine: PlanLine? {
        reduce(nil) { currentBest, candidate in
            guard let currentBest else {
                return candidate
            }

            return candidate.isBetterHistoryBestSet(than: currentBest)
                ? candidate
                : currentBest
        }
    }
}

private extension PlanLine {
    var historySetText: String {
        "\(historyFormattedWeight) x \(reps) x \(targetSets)"
    }

    func isBetterHistoryBestSet(than rhs: PlanLine) -> Bool {
        if weight != rhs.weight {
            return weight > rhs.weight
        }

        if reps != rhs.reps {
            return reps > rhs.reps
        }

        if targetSets != rhs.targetSets {
            return targetSets > rhs.targetSets
        }

        return false
    }

    private var historyFormattedWeight: String {
        guard weight.rounded() == weight else {
            return String(weight)
        }

        return String(Int(weight))
    }
}
