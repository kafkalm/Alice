# PRD: Quick SVO Parse（全局快捷键英文主谓宾解析）

## 1. 背景与问题
用户在 macOS 任意应用中阅读英文长段落时，难以快速提取句子核心关系，导致阅读中断和理解成本升高。  
本功能目标是在不复制粘贴、不切应用的前提下，让用户一键看到逐句主谓宾结构。

## 2. 目标与范围
### 2.1 目标
- 一次触发，自动分句并逐句输出主谓宾结构
- 优先保证解析正确性，再优化时延
- 在主流 macOS 阅读场景保持可用

### 2.2 非目标
- 不提供全文翻译
- 不提供语法课程式讲解
- 不做写作纠错

## 3. 用户故事
- 作为英文基础较弱用户，我希望悬停并按快捷键后立刻得到句子主干。
- 作为阅读长段落用户，我希望自动分句，不需要多次触发。
- 作为隐私敏感用户，我希望默认本地处理，仅在我允许时进行云端回退。

## 4. 关键流程（主路径）
1. 首次启动，引导用户授权辅助功能与屏幕录制权限。
2. 用户在任意应用将鼠标悬停在英文文本区域，按下 Alice 快捷键。
3. 系统尝试通过 AX API 抓取文本，失败时回退 OCR。
4. 对段落执行分句。
5. 对每句执行主谓宾解析，生成置信度。
6. 在光标附近展示悬浮结果卡，按句列出 Subject / Verb / Object。
7. 如低置信度或失败，展示“云端重试”入口（仅当用户开启该能力）。

## 5. 功能需求（FR）
- FR-1：支持全局快捷键注册，并进行冲突检测与提示。
- FR-2：文本抓取路径固定为 AX 优先、OCR 回退。
- FR-3：段落输入自动分句并保持原始顺序。
- FR-4：每句输出字段固定为 `subject`、`verb`、`object`、`confidence`。
- FR-5：本地解析失败或低置信度时，可触发云端回退（用户开启后生效）。
- FR-6：结果卡展示来源应用、解析耗时、失败原因（若有）。
- FR-7：记录匿名事件：触发、成功、失败、云端回退。

## 6. 非功能需求（NFR）
- 准确率：常见陈述句/被动句/从句主干识别准确率 >= 85%（内部基准集）。
- 时延：本地解析 p95 <= 800ms，云端回退 p95 <= 2500ms。
- 稳定性：连续 100 次触发无崩溃。
- 隐私：默认本地，云端请求需要用户显式开启。

## 7. 接口与数据契约
### 7.1 类型定义
```ts
type CaptureTextRequest = {
  sourceApp: string;
  cursorPoint: { x: number; y: number };
  timestamp: number;
};

type CaptureTextResponse = {
  method: "ax" | "ocr";
  rawText: string;
  languageHint: "en" | "unknown";
  bounds?: { x: number; y: number; width: number; height: number };
};

type ParseSentenceRequest = {
  sentence: string;
  mode: "local" | "cloud_fallback";
  contextId: string;
};

type ParseSentenceResponse = {
  subject: string;
  verb: string;
  object: string;
  confidence: number;
  notes?: string;
};

type ParseParagraphResponse = {
  sentences: Array<{
    index: number;
    text: string;
    svo: ParseSentenceResponse;
  }>;
  totalLatencyMs: number;
  fallbackUsed: boolean;
};
```

### 7.2 事件接口
- `alice.quick_svo.triggered`
- `alice.quick_svo.succeeded`
- `alice.quick_svo.failed`
- `alice.quick_svo.cloud_fallback_used`

## 8. 错误处理与降级
- 文本抓取失败：提示“未检测到可解析英文文本”，提供权限修复入口。
- 分句失败：降级为整段单句解析重试一次。
- 本地低置信度：保留本地结果并提示“结果可能不准”，允许云端重试。
- 云端失败：保留本地结果并提示网络或服务异常。

## 9. 测试场景
- 场景 1：浏览器英文新闻 3-5 句，验证逐句顺序和 SVO 完整度。
- 场景 2：邮件客户端复杂长句（含从句），验证主干抽取稳定性。
- 场景 3：PDF 阅读器（AX 不可用），验证 OCR 回退成功。
- 场景 4：权限缺失（仅开辅助功能未开录屏），验证引导链路。
- 场景 5：低置信度触发云端回退，验证结果替换与状态标识。
- 场景 6：离线状态，验证本地路径可用及文案提示。
- 场景 7：高频触发 100 次，验证稳定性与内存表现。

## 10. 发布与灰度
- 阶段 1：内部灰度（20 用户），建立错误样本池。
- 阶段 2：公开 Beta（500 用户），验证跨应用覆盖率。
- 阶段 3：正式发布，持续跟踪准确率与时延看板。

## 11. 假设与默认值
- 菜单栏为首发形态。
- 默认本地优先，允许云端回退。
- 默认仅展示主谓宾结构，不附翻译。
- 默认自动分句并逐句展示。
- 默认权限为辅助功能 + 屏幕录制。
- 解析准确率优先级高于时延与覆盖率。

