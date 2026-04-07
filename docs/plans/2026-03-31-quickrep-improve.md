
## 代码审查总结

项目整体架构清晰，领域层/持久化层/表现层分离得当，测试覆盖了核心解析和进度逻辑。以下是按优先级分类的优化点：

---

### 一、潜在 Bug / 正确性问题

1. **`PlanLine.state` 和 `state(isFinalizedRecord:)` 是死代码** — `PlanLine` 上有两个从未被调用的方法，`state` 永远返回 `.planned`。建议移除或整合到实际使用场景中。

2. **`WorkoutTextProgressUpdater.reconcileDraftProgress` 用 `lineIndex` 做 key 匹配旧 planLine** — 当用户在同一位置先删一行再改内容时，`lineIndex` 可能匹配到错误的 planLine。应该用 `id`（通过 snapshot reconciliation 已经保证稳定）来做匹配，当前逻辑实际已经用了 id，但中间查找链路先用 `lineIndex` 找旧 planLine 再用 id 找新 planLine，这个两步查找可以简化为直接用 id。

3. **`WorkoutNote.draftProgressState` setter 里 `newValue.isEmpty` 判断在 `draftProgressData = nil` 之后多余** — 先 encode 再判断 isEmpty 再置 nil，逻辑上等价于直接判断 encode 结果是否和空状态一样。

4. **`TrainingEditorScreen.onChange(of: workoutNotes.first?.id)` 使用了 key path 到 optional property** — 这在 SwiftUI 中可能不会如预期般响应变化，因为可选值的 key path 变化跟踪不稳定。建议用 `workoutNotes` 的 `id` 集合来跟踪。

---

### 二、架构 / 设计优化

5. **`TrainingEditorScreen` 承担了过多职责** — 它同时处理：视图渲染、SwiftData 持久化读写、解析/进度状态管理、UI 状态管理。建议拆分为：
   - `TrainingEditorViewModel`（或用 `@Observable` class）管理状态和持久化
   - `TrainingEditorScreen` 只负责视图渲染
   
6. **`WorkoutTextParser` 每次完整重解析** — 每次文本变化都从头遍历所有行重建所有 `ExerciseBlock`。当前规模下没问题，但可以考虑增量解析（只重新解析变化行所在的动作段落）。

7. **`TrainingEditorTextLayout.lines(in:)` 被频繁调用且无缓存** — `line()`、`selectionRangePreservingLinePosition()` 等每次都重建整个行数组。在 `Coordinator.publishEditorState` 中被频繁触发。

---

### 三、性能优化

8. **`WorkoutTextSnapshot.reconciled` 的行匹配是 O(n²)** — 对每一行新文本，都从 `searchStart` 开始线性搜索旧文本。在长笔记场景下可能有性能影响。可用字典优化匹配阶段。

9. **`TrainingTextEditor.Coordinator.trackedLineRects` 每次构建完整行字典** — 每次 `publishEditorState` 都调用 `TrainingEditorTextLayout.lines(in:)` 重建全量行数据再查找。可以缓存或只计算可见区域的 tracked lines。

10. **`TrainingEditorScreen.reconcileEditedText` 在 `onChange(of: noteText)` 中触发** — 每次击键都会执行：进度协调 + 重新解析 + 持久化写入。对 SwiftData 的频繁 `save()` 可能在极端情况下造成主线程压力。建议加入 debounce 或至少将 save 延迟到编辑暂停时。

---

### 四、代码质量 / 可维护性

11. **正则 `try!` 强制解包** — `WorkoutTextParser.plannedPattern` 用 `try!` 创建正则。虽然正则是编译期常量不太可能出错，但更安全的做法是 `try` 并在 `static let` 初始化失败时提供明确错误信息。

12. **测试文件过大（475 行）** — 所有测试在一个文件里。建议按模块拆分：`WorkoutTextParserTests`、`WorkoutTextProgressUpdaterTests`、`TrainingEditorTextLayoutTests`、`WorkoutNoteTests`。

13. **`String.nilIfEmpty` 扩展定义在 `TrainingEditorScreen` 里** — 这个通用扩展不应该藏在特定 Screen 文件里。如果需要，放到公共扩展文件。

14. **`WorkoutNote.parsedText()` 和 `textSnapshot()` 方法让 Model 承担了解析职责** — 持久化实体不应该知道解析逻辑。这些方法应该由调用方构造 snapshot 和 parse result。

15. **缺少错误处理** — 全局使用 `try?` 吞掉 SwiftData 错误，在 debug 阶段应至少加入 log。

---

### 五、具体小改进

16. **`WorkoutNote` 缺少 `draftProgressData` 的 `@Attribute(.externalStorage)` 注解** — JSON data 默认存在主表里，数据量大时影响查询性能。

17. **`ExerciseLibraryEntry.name` 没有 unique 约束** — 允许同名动作被重复创建。应加 `@Attribute(.unique)` 或在创建前检查。

18. **`TrainingTextEditor.updateUIView` 中设置 `textContainerInset` 的比较逻辑** — `UIEdgeInsets` 不直接支持 `!=`，这里的比较可能总是 true（取决于是否实现了 Equatable），导致每次 update 都重新设置 inset。

---

### 建议的优先执行顺序

如果要逐步优化，建议按以下顺序：
1. 修复潜在 Bug（#1 死代码、#4 onChange 跟踪）
2. 拆分 `TrainingEditorScreen` 的职责（#5）— 这是最大的架构改进
3. 加入编辑 debounce 或延迟持久化（#10）
4. 优化 `lines(in:)` 缓存和行匹配性能（#8 #9）
5. 测试文件拆分和错误处理改善（#12 #15）
