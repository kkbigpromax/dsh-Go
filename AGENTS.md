# AGENTS.md

dsh-Go 是 DeepSeek Harness 的手机应用：Flutter 原生界面 + 纯 Dart 客户端 + 打过补丁的 DSH 引擎运行时。Android 版在 PRoot 里运行 `dsh web`；鸿蒙版共用同一套 Dart，宿主是 ArkTS（`app/ohos/`），引擎跑在 App 进程内的 Node 里（`runtime/ohos/`，见 [docs/architecture.md §3B](docs/architecture.md)）。改动前先读 [CONTRIBUTING.md](CONTRIBUTING.md)（贡献与验证契约）与 [docs/architecture.md](docs/architecture.md)。

## 仓库布局

```
app/                         Flutter App：原生界面、Riverpod 状态、l10n、手机操控
app/lib/l10n/parts/          界面文案的中英文 ARB 输入
app/ohos/                    鸿蒙 ArkTS 宿主工程（Android 不读）
packages/dsh_client/         纯 Dart 客户端：HTTP/SSE、mux、会话与删除 API
packages/dsh_remote/         远程传输：WebRTC / LAN / TURN / 中继
runtime/                     打补丁的 DSH 引擎运行时
runtime/bridge/dsh-go-bridge/  App ↔ 引擎的 HTTP 桥（/dsh-go/v1/*，含会话删除路由）
runtime/patches/             引擎补丁及其 pins.json（补丁与版本钉死，targetSets 分 android / ohos）
runtime/ohos/                鸿蒙本机引擎：Node 宿主、虚拟进程、生命周期、运行时组成
sdk/plugin-kit/              插件 SDK
tooling/                     APK 构建与构建号脚本；tooling/ohos/ 是鸿蒙构建、ArkTS 检查与门禁
docs/                        架构、发布、路线图、用户指南（鸿蒙版在 docs/guide/harmony/，设计在 docs/design/harmonyos/）
```

## 命令

按改动面选择验证，在 PR/报告里写实际执行的命令和结果。完整说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

```bash
(cd app && flutter pub get && flutter analyze && flutter test)   # Flutter 应用
(cd packages/dsh_client && dart pub get && dart analyze && dart test)
(cd packages/dsh_remote && dart pub get && dart analyze && dart test)
(cd sdk/plugin-kit && npm install && npm test)
node --test runtime/tests/*.test.mjs                               # 引擎桥/补丁测试
python3 app/tool/l10n_merge.py --check                             # 文案生成检查
python3 app/tool/guide_sync.py --check                             # 用户指南同步检查
tooling/build-apk.sh --build-name <x.y.z>                          # 构建 APK
tooling/ohos/check-arkts.sh --sdk <OpenHarmony SDK> --hms-stubs    # 鸿蒙严格 ArkTS 编译
bash tooling/ohos/run-gates.sh --config <inputs.json> --out <dir>  # 鸿蒙全量门禁（tooling/ohos/GATES.zh.md）
```

CI（`.github/workflows/ci.yml`）在 PR 上跑通用检查和改动涉及的部分，在 `main` 上跑全量，结果看 `CI OK`。它不碰真机和真实账号，绿了不等于手机上没问题。

## 硬规则

### 不接受外部 PR（最高优先级）

- 本仓库**暂不接受任何外部 Pull Request**（代码、文档、配置、模板都不收）。
- **禁止合并任何外部 PR**：不得用 `gh pr merge`、GitHub API、网页合并、rebase 或 cherry-pick 把外部提交带进 `main`。
- **禁止替用户创建 PR**，除非用户在当次对话里明确要求。
- 收到外部 PR：关闭它并回复"暂不接受外部 PR，请改用 issue 提供建议"。入口检查（`.github/workflows/pr-gate.yml`）会自动关闭外部 PR；人工按同一政策处理，不要"先合并再说"。
- 不要因为某个 issue 有了实现，就自动把实现包装成 PR 合入。

### 源码、生成物与运行时补丁

- 不手改生成物：`app/build/`、`.dart_tool/`、生成的 l10n 产物等；改输入后运行对应生成器。
- 界面文案改 `app/lib/l10n/parts/*.arb`，中英文同步，再跑 `python3 app/tool/l10n_merge.py`；不要手改生成结果。
- 用户指南改 `docs/guide/`，再跑 `python3 app/tool/guide_sync.py`。鸿蒙版指南在 `docs/guide/harmony/`，功能在鸿蒙上有差异时两套都要改。
- 引擎补丁在 `runtime/patches/`：补丁文件与 `pins.json` 保持同步，不手改正被补丁覆盖的产物。新补丁要登记进 `pins.json` 的 `targetSets`（`android`、`ohos` 或两者），没登记的补丁 rtbuild 拒绝构建。
- 插件教学技能改 `sdk/plugin-kit/skill/` 或 SDK 对应输入，再跑 `node sdk/plugin-kit/scripts/sync-skill.mjs`。

### 行为与契约

- 客户端、桥接、插件协议的改动，同时检查另一端的调用方与向后兼容。
- 危险操作（删除会话、权限、凭据）以主机/引擎的实际回答为准，不用本地推断代替；失败要有稳定错误码，不静默吞掉。
- 界面文案中英两版同步（`app/lib/l10n/parts/*.arb` 与对应 `.en.arb`）。
- 双语文档同步：README、CONTRIBUTING、SECURITY、docs/guide 中英两版同步。

### 鸿蒙

- 鸿蒙和 Android 功能一致是目标，前端优先。能实现的功能走同一套 UI；做不到的才用 `androidSystemFeaturesProvider` / `operatingSystemProvider`（`app/lib/state/android_features.dart`）按功能隐藏，不全局放开或关闭，并在鸿蒙指南里写明替代。
- `androidSystemFeaturesProvider` 在鸿蒙和 iOS 上都是 false。只属于鸿蒙的分支判断 `operatingSystemProvider == 'ohos'`，不要用它的 false 代指鸿蒙。
- 鸿蒙改动不能改变 Android 的运行时字节和行为；门禁的 Android 对照（`android-targets`、`android-version-tree`）以 main 为基线。
- ArkTS 按严格模式写：for-of 变量显式类型、子类传给 `Error` 参数要 `as Error`、静态方法不用 `this`。改了 `app/ohos/` 就跑 `check-arkts.sh`。
- 签名材料（`.p12`、证书、profile）只放仓库外（`DSH_OHOS_SIGN`），不入库、不回显。

### 凭据与隐私

- 不记录、不回显、不持久化完整 API key、token、cookie、登录态。
- 诊断包和日志外发前人工检查；自动打码不能当成保证。

### Git 安全

- **每次开工前先拉平基线**：`git fetch origin main` 后把当前分支同步到最新 `origin/main`（能快进就 `git merge --ff-only`），检查、改动和开 PR 都在最新基线上做。不在落后 `main` 的分支上直接叠加任务——否则容易重复实现 `main` 已经修好的东西，白改一遍。
- 拉平前先处理未提交改动：自己的改动先备份（patch 或临时副本）再让分支快进；用户或其他任务的未提交改动不得丢弃、reset、stash 或覆盖，拉不平就停下来问。默认从最新 `origin/main` 建立隔离工作分支。
- 工作提交并合并后，必须清理本次创建的临时工作树与分支；清理前确认提交已合入目标、没有未保存或未推送的成果。不强制删除含改动的工作树，不删除其他任务的分支。
- 合并及清理后，再获取最新 `main`，在干净的主工作树内仅用 fast-forward 同步，并报告最终提交与未清理事项；主工作树有无关改动时保留并说明，不能为了制造“干净”而丢失工作。
- 只暂存明确路径，不用 `git add .` / `git add -A`。
- 未经要求不 commit、不 push、不打 tag、不发布。
- 不 force push `main` 或重写共享历史，除非用户在当前对话里明确要求；重写后必须重建受影响的分支与 PR。

### 本 fork 的精简范围

- 用户保留现在的原生聊天主界面；移除宠物、原版 DSH 网页界面、酒馆、伙伴小屋、左滑快捷面板，以及“帮助与关于”整组。
- 只用本机引擎：远程主机（SSH、DSH Remote 中继、扫码配对、远程备份、远程保活）连同 `flutter_webrtc`、`mobile_scanner`、`dartssh2`、`dsh_remote` 依赖已移除；DeepSeek 账号入口和 DS Bot 入口断开，DeepSeek 模型按自定义渠道接入。ChatGPT／Claude 订阅登录与 OpenAI 官方渠道保留。合并上游时不得重新接入这些功能或依赖。
- 设置 › AI › 代理（仅 Android）用内置的精简 Xray（`runtime/xray`，固定提交见 `source.json`）让引擎的模型请求走用户手填的 VLESS + REALITY 服务器；这是本 fork 的保留功能，合并上游时不得移除，内核范围不扩大到其他协议。
- Agent 预设也须执行精简规则：`dsh-go-companion`、`dsh-go-companion-full`、`dsh-go-diagnostics` 不得出现在设置、新对话或预设编辑器的选择列表中；保留原始主机目录以识别旧默认值，新建对话不得因此回到已移除的预设。
- 功能移除须同步清理设置项、设置搜索、全部功能、深链、启动监听、原生服务/桌面组件与独占资源；旧偏好不得重新启用这些功能。后续合并上游时保持此范围。
- 聊天共用的语音、通知状态归约、手机操控、引擎与错误捕获继续保留；不要因为目录名含 companion/pet 就连带删除共享模块。用户已有对话和配置不清空。

### 本 fork 的 APK 构建

- App 名称为 Agentello，`applicationId` 为 `io.github.kkbigpromax.agentello`；Kotlin namespace 保持原值。合并上游时不得恢复旧名称、旧包名或旧图标，细节见 [fork 改动与合并规则](docs/fork-maintenance.md)。
- 版本名称与当前上游版本保持一致（取 `app/pubspec.yaml` 中的版本，不加 fork 后缀）；内部构建号按现有规则递增以支持覆盖安装。
- 固定发布签名（2026-11-28 生成，证书 SHA-256 `86eade3eecb4bc32e38dc62c135c500b641c1de8b9d751751ec0e0b1d2e47bf2`）由用户私下备份，并存为仓库 Actions secret `AGENTELLO_SIGNING`（JSON：`keystore` 为 base64 PKCS12，`password`，`alias`）。用 GitHub Actions「Build Agentello APK」（`.github/workflows/build-apk.yml`，手动触发）构建；`app/android/app/build.gradle.kts` 校验证书指纹，不符即停止。不得重新生成签名、不得把密钥提交 Git 或写进日志。
- 新签名启用后，后续更新都应复用这一把签名。密钥缺失或证书不符应停止发布构建，恢复当前签名而非回退到 debug 签名。同包名但签名不同会导致旧版无法直接覆盖安装。需要保留旧版数据时，应在卸载前自行导出或备份所需数据。
- 密钥、密码、配置和备份不得提交 Git 或放入公开输出。

### 本 fork 合并上游的规则

- 每次合并前先读 [fork 改动与合并规则](docs/fork-maintenance.md)，从上次已合入的上游提交比较到目标版本；同时审查提交、源码差异、依赖、权限、资源与启动行为，不能只看发布说明或 Git 是否报告冲突。
- 必须完成两项检查：一是新代码与本 fork 改动的文本及行为冲突，发现后处理并验证，保持隐私、精简范围、固定签名与配置兼容；二是上游是否新增功能或重新引入已移除功能。
- 上游新增功能必须先向用户说明用途、是否会引入额外依赖/资源/权限/后台活动，以及建议，逐项询问是否加入；未经用户明确选择，不得默认加入或启用，也不能仅隐藏入口却把新增的独占负担带进交付 APK。可先继续处理独立的修复和冲突，不提前交付含待决定功能的安装包。
- 用户需求集中，优先保留现有核心用途和最小必要改动，避免功能堆积。已移除功能默认继续移除；正常漏洞修复、稳定性修复和既有功能兼容适配可继续完成，若夹带新的功能或负担则拆出询问。
- 合并完成后更新上述记录中的上游基线、保留的 fork 改动、新功能的用户决定、冲突处理与实际验证结果；不能把测试通过写成真机验证通过。

### 真机验证

- Flutter widget 测试需要对应架构的 Flutter 引擎；只有桌面端（x86_64）而设备是 arm64 时，明确写"未运行"及原因。
- 手机操控、PRoot、直接启动、更新安装相关改动必须在真机上验证；桌面结果不能替代。
- 鸿蒙的系统能力（HMS、后台、通知、语音、卡片）只有真机能证明；`--hms-stubs` 只是让调用方编得过的非官方声明，编过不等于能用。

## 代码审查原则

审查 PR 或改动时，以**不引入新 Bug、最小必要改动、保持代码简洁**为核心：

1. **防止回归**：优先检查新增 Bug、竞态、资源泄漏、性能退化、兼容性问题，特别关注共享层（`packages/dsh_client`、bridge、runtime 补丁）对既有主机连接方式的影响。
2. **避免过度设计**：识别重复实现、无必要的抽象、冗余封装和过度防御性编程；只在存在更简单等效方案时报告，不误判必要的安全校验和错误处理。
3. **严格控制范围**：改动应围绕目标与关联 issue，不夹带无关重构、格式化、依赖升级或其他功能修改；必要的测试和文档同步除外。
4. **保证实质价值**：关注无效代码、重复逻辑、无意义拆分和缺乏有效断言的测试；不以代码行数或提交次数判断贡献，不推测贡献者动机。
5. **审查必须有据**：只报告本次改动引入的实质问题，说明具体位置、触发条件和实际影响，优先给最小修复建议。

### 过度防御也是缺陷（写代码时就按这个判）

防御不是越多越好。判断只有一条：**这个分支挡住的事情，真的会发生吗。**

- 只对能说出触发条件的失败加防御；说不出触发条件的分支删掉。
- 能用类型、单点入口或既有调用顺序保证的，不加运行时校验、不加兜底重试、不加多层状态机。
- 错误处理只有两种出口：可恢复的给出可执行结果，不可恢复的明确失败。不许静默吞、不许无限重试、不许为了「更安全」把功能锁死。
- 安全边界（权限、资源收尾、外部输入校验）该严就严，但必须留恢复路径：拒绝之后用户要走得回来，不能永久卡住。
- 新增的状态标记、门禁、握手，必须写清「谁置位、谁清除、清不掉会怎样」；写不清就别加。

### 先做最短能跑通的

- 需求没写的防护不加：多层重试、兜底回退、冗余校验、层层判空、功能开关。
- 不为自己造流程：冻结清单、签名台账、状态快照、验收报告，除非用户要求。
- 不建 v1 / v2 / final 这类并行目录；直接改原文件，历史交给 git。
- 出问题先读真实输出定位根因，不靠加重试掩盖；改一处就重跑确认，通过后再跑几次看稳定。
- 本节与上面硬规则冲突时以硬规则为准（Git 安全、外部 PR 政策、真机验证、双语同步）。

## 技能与流程

- 内部 PR：走 `.agents/skills/pr`（流程、模板、验证记录）。
- 代码审查：走 `.agents/skills/review`（证据优先，只报本次改动引入的实质问题）。
- 缺陷报告：`.agents/skills/bug`；安全审计：`.agents/skills/vuln-check`；大范围审计：`.agents/skills/audit`。

## 编辑本文件

`CLAUDE.md` 是指向 `AGENTS.md` 的符号链接；编辑真身。每条规则保持自包含，细节链接到权威文档。
