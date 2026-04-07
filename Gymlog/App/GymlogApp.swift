import SwiftUI
import SwiftData

@main
struct GymlogApp: App {
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Label("开始训练", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section("训练历史记录") {
                    if historyRecords.isEmpty {
                        Text("还没有训练记录，点击“开始训练”创建第一条。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(historyRecords) { record in
                            NavigationLink {
                                TrainingHistoryDetailScreen(record: record)
                            } label: {
                                WorkoutHistoryRow(record: record)
                            }
                        }
                    }
                }
            }
            .navigationTitle("训练")
        }
        .sheet(isPresented: $isPresentingEditor) {
            TrainingEditorScreen(
                initialRawText: "",
                onFinishWorkout: finalizeWorkout(with:)
            )
        }
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
            GymlogDiagnostics.log(
                "Failed to finalize workout from home screen: \(error.localizedDescription)"
            )
        }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(record.finishedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.subheadline.weight(.semibold))
            Text(record.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private extension WorkoutHistoryRecord {
    var previewText: String {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return lines.first(where: { $0.isEmpty == false }) ?? "空白训练记录"
    }
}
