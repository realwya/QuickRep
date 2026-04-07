# QuickRep P0-2 核心数据模型定义方案

## 摘要
本轮只定义数据模型规格，不实现解析器、编辑器或持久化接线。模型保持“双层模型”，但训练中的完成进度改为独立草稿状态：

- 持久化层保存真正需要跨重启保留的真值：训练原文、训练中草稿进度、更新时间、动作库
- 解析层定义可从 `rawText` 重建的派生结构：`ExerciseBlock`、`PlanLine`
- 训练中的计划行只采用 `重量 x 次数 x 组数` 语法，例如 `20 x 8 x 5`
- 结束训练后，同一行会收敛成实际完成记录，例如 `20 x 8 x 4`
- `rawText` 承载正文与最终结果；训练中的进度由独立 `WorkoutDraftProgressState` 持久化

建议把这一轮的代码落在 3 个区域：

- `QuickRep/Domain/Workout`
- `QuickRep/Domain/ExerciseLibrary`
- `QuickRep/Persistence` 或同级模型目录

## 关键定义

### 1. 持久化实体

#### `WorkoutNote`
- 字段：`id`、`rawText`、`draftProgressData`、`updatedAt`
- 角色：当前训练笔记正文与训练中草稿进度的持久化宿主

约束：
- `rawText` 保存完整原始文本
- `rawText` 不承载训练中的实时进度
- `draftProgressData` 保存未结束训练前的计划行草稿进度
- 不直接持久化 `ExerciseBlock` / `PlanLine`
- `draftProgressData` 在结束训练后清空

#### `ExerciseLibraryEntry`
- 字段：`id`、`name`、`isBuiltin`
- 用途：`@动作` 自动补全的数据源

### 2. 解析输出类型

#### `ExerciseBlock`
- 字段：`id`、`exerciseName`、`startLineIndex`、`endLineIndex`
- 角色：从 `rawText` 推导出的动作段落
- 不作为长期真值保存

#### `PlanLine`
- 字段：`id`、`lineIndex`、`exerciseBlockId`、`weight`、`reps`、`targetSets`、`rawText`
- 角色：从 `rawText` 推导出的结构化计划行
- 不作为长期真值保存

#### `WorkoutDraftProgressState`
- 角色：表达训练未结束时每条计划行的独立完成进度
- 字段：`entries`
- 每个 entry 至少包含：`lineIndex`、`completedSets`
- 说明：该状态与 `rawText` 一起持久化，但只服务于未结束训练

### 3. 文本语义

计划行在不同阶段的文本规则如下：

- 计划态：`20 x 8 x 5`
- 结束训练后：`20 x 8 x 4`

收敛规则：

- `20 x 8 x 5` + 草稿进度 `4` -> `20 x 8 x 4`
- `20 x 8 x 5` + 草稿进度 `5` -> `20 x 8 x 5`
- `20 x 8 x 5` + 草稿进度 `0` -> 删除该行

训练中的点击规则：

- 点击右侧勾选时，系统只更新该行的草稿进度状态
- `20 x 8 x 5` + 草稿进度 `0` -> 草稿进度 `1`
- `20 x 8 x 5` + 草稿进度 `3` -> 草稿进度 `4`

编辑规则：

- 用户手动编辑计划核心内容时，已有进度立即清空
- 改动重量、次数或目标组数后，该行回到新的纯计划态，并清空该行草稿进度
- 仍保留“离开当前行后再统一校验”的编辑稳定性原则

## 实现变更

- 为持久化层定义最小模型骨架，优先兼容后续 SwiftData：
  - `WorkoutNote`
  - `ExerciseLibraryEntry`
- 为解析层定义纯领域类型：
  - `ExerciseBlock`
  - `PlanLine`
  - `WorkoutDraftProgressState`
- 明确关系与职责：
  - `WorkoutNote.rawText` 保存正文与最终结果
  - `WorkoutNote.draftProgressData` 保存训练中的独立草稿进度
  - `ExerciseBlock` / `PlanLine` 全部由解析器重建

不在本轮加入：

- `lineStates`
- 模板模型
- 历史页聚合模型
- 统计模型
- 网络/同步相关字段

## 测试与验收

### 类型层验收
- 能清楚区分“持久化实体”和“解析输出类型”
- `WorkoutNote` 不直接包含 `ExerciseBlock` / `PlanLine` 集合
- `WorkoutNote` 明确持有训练中草稿进度而不是正文后缀

### 解析层验收
- `PlanLine` 能识别：
  - `20 x 8 x 5`
  - `20 x 8 x 4`
- 带 `n/m` 后缀的文本不再视为合法计划行
- `WorkoutDraftProgressState` 可以独立表达训练中的完成进度

### 动作库验收
- `ExerciseLibraryEntry` 只承担名称和内置/自定义来源区分

### 文档/命名验收
- 类型命名与 backlog 一致
- 代码注释或文档明确声明训练中进度不写入正文
- 文档明确说明训练中进度来自独立草稿状态，结束训练时收敛为最终记录

## 默认假设

- 训练中的进度只显示在圆圈上，不写入正文
- 当前不支持负向修正、撤销勾选、超目标组数或实际 reps/weight 偏差
- 删除 0 组计划行只发生在“结束训练”这一显式动作上
- 最终历史记录以“实际完成结果”为准，不保留原目标组数痕迹
- `ExerciseBlock.id` 和 `PlanLine.id` 在当前阶段是运行时解析身份，不承诺跨解析稳定
