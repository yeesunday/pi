# Pi 架构提案

Pi 是一个开源、Local-first 的个人应用运行时。

> **Build your own Pi.**  
> Everything is a plugin.  
> Your data is yours.

这份提案刻意区别于传统的“超级 App”设计。Pi Runtime 只提供生命周期、组合、存储、事件、提醒、导航、权限和 Provider 接口。Todo、Birthday、Notes、Health 以及未来的其他领域，都作为插件贡献的能力存在。

## 1. 设计目标与约束

Pi 必须允许开发者使用同一套 Runtime 和插件生态，组装出不同的应用。Todo + Birthday + Notes 的构建产物应该拥有不同于 Todo + Notes 的首页和导航，而且不需要向 Core 添加条件分支。

第一版遵循以下约束：

- 使用 Flutter 和 Dart，iOS 优先，兼容 Android，同时保留未来扩展到桌面端的包边界。
- Local-first、Offline-first。核心能力不依赖账号或后端。
- 通过普通的 Dart/Flutter package 在构建期组合。手机端不会下载并执行任意 Dart 代码。
- 足够小，便于理解和替换。插件与实现之间通过接口隔离。
- 支持导入和导出。用户可以带走自己的数据和附件。

V1 明确不包含云端账号、同步、插件市场、远程代码执行、社交功能和通用事件溯源系统。

## 2. 架构方案比较

### 方案 A：基于 Flutter package 组合的薄 Runtime（选定）

每个插件都是一个普通 Dart package，并实现 `PiPlugin`。App 在 `pubspec.yaml` 中声明选定的 package，在启动时创建 `PiRuntime` 并注册插件。Runtime 管理 Registry 和受其管理的资源；插件贡献 Service、Route、Slot 条目、Migration、Command 和 AI Tool。

**优点**

- 符合 Flutter 和 iOS 的发布规则。
- 保留静态分析、代码签名、Tree Shaking 和标准 package 工具链。
- 第三方代码在 App 构建中明确可见，便于审查和权限检查。
- 可以用内存实现和虚拟时钟进行测试。

**代价**

- V1 中安装新插件需要重新构建 App。
- 插件本质上是原生应用代码，无法彼此完全沙箱隔离。

### 方案 B：运行时解释 Manifest 和通用 Widget/Data DSL

App 下载插件元数据，并在运行时解释数据模型、Command 和 UI 描述，由一个受信任的 Host 负责渲染。

**优点**

- 未来可能无需完整重新构建即可动态安装插件。
- 如果解释语言受到严格限制，可以获得更强的隔离能力。

**代价**

- 需要重新构建一套完整的 UI、Migration 和 Capability DSL。
- Flutter 原生集成和复杂插件 UI 会变得困难。
- 安全、版本兼容、调试和性能复杂度都很高。

这可以作为未来插件 Registry 的元数据格式，但不是 V1 的执行模型。

### 方案 C：全局 Service Locator 加 Feature package

插件通过全局 Locator（例如全局 `GetIt` 容器）注册实现，Feature package 主要暴露页面并调用共享 Singleton。

**优点**

- 初始代码量小。
- 对许多 Flutter 团队来说比较熟悉。

**代价**

- 全局状态会让卸载、测试、Profile 和多个 Runtime 实例变得不可靠。
- 依赖变成隐式关系，具体实现容易泄漏到业务代码。
- 容易退化为“插件就是页面”和 Core 条件分支。

Pi 不采用它作为架构基础。Runtime 自己持有的作用域 Registry 可以提供类似的便利，同时保留资源所有权和释放能力。

## 3. 选定的系统形态

```text
App 入口 / 生成的 Profile
                |
         PiRuntime（作用域）
   ┌────────────┼───────────────────────┐
   │            │                       │
插件 Registry  Core Service            扩展 Registry
              Data / Event / Reminder  Route / Slot / Command / Tool
   |
插件能力：Todo、Birthday、Notes……
   |
Flutter Shell 渲染已注册的 Route 和 UI Slot 贡献
```

`PiRuntime` 是一个明确的对象，不是静态 Singleton。生产环境可以创建一个 Runtime，测试或预览则可以创建完全隔离的 Runtime。

Core 只负责协议和编排，不认识 Todo 或 Birthday 这类领域名称。即使某个领域插件由官方随主 App 一起发布，它的领域规则仍然属于插件，而不是 Core。

## 4. 包与仓库结构

```text
apps/
  pi/                         # Flutter App Shell 和选定的 Profile
packages/
  pi_core/                    # ID、Result、Clock、Permission、Diagnostics
  pi_runtime/                 # 生命周期、依赖解析、Registry
  pi_data/                    # Entity/Repository 协议和 Migration
  pi_storage_sqlite/          # Drift/SQLite 实现
  pi_reminder/                # Reminder 协议和本地通知适配器
  pi_ui/                      # Shell、Slot、Route、Contribution 渲染
  pi_ai/                      # Provider、Conversation、Tool 协议
plugins/
  todo/
  birthday/
docs/
tooling/
```

`pi_core` 必须保持轻量，尽量少依赖。平台适配器（SQLite、通知、安全密钥存储）放在接口之后的独立 package 中。插件依赖协议，不能依赖 `pi_storage_sqlite` 或原生数据库 API。

## 5. Plugin 模型

插件是一个能力集合。它的 UI 只是贡献项之一，其他贡献还包括 Entity Model、Repository、Command、Event、Route、Setting、Migration、Permission 和 AI Tool。

概念性的 Dart API：

```dart
abstract interface class PiPlugin {
  PluginManifest get manifest;
  Future<void> register(PluginContext context);
  Future<void> start(PluginContext context);
  Future<void> stop(PluginContext context);
}

class PluginManifest {
  final String id;                 // 反向域名，例如 dev.pi.todo
  final String version;
  final Set<String> dependencies;  // 插件 ID 或 Capability ID
  final Set<Permission> permissions;
}
```

`register` 负责声明资源并校验依赖，`start` 负责开始主动工作。Runtime 为每个插件保存一个 `PluginHandle`，其中包含该插件通过 `PluginContext` 注册的全部资源；释放 Handle 时，会一并移除 Route、Slot、Listener、Service、Timer 和通知注册。

生命周期状态包括 `registered`、`loading`、`active`、`failed`、`unloading` 和 `disposed`。启动时解析依赖图，拒绝循环依赖，并按照拓扑顺序启动。关闭或卸载时按逆序停止。某个插件失败后，Runtime 通过 Diagnostics 报告错误；只要不是必需依赖，其他插件仍可继续运行。

插件不能直接修改另一个插件的 Registry。它们应通过 `PluginContext.services` 请求协议，并拿到一个作用域内的 `ServiceRef<T>`；插件卸载后，该引用失效。

## 6. Service 与依赖边界

Service 是注册在 Runtime 作用域中的接口。初始 Core 协议包括：

- `PiDataStore` 和 `EntityRepository<T>`
- `PiEventBus`
- `ReminderService`
- `NotificationService`
- `NavigationRegistry`
- `UiContributionRegistry`
- `SettingsStore`
- `FileStorage`
- `ImportExportService`
- `SearchRegistry`
- `AiProviderRegistry`
- `PermissionService`
- `PiLogger` 和 Diagnostics

注册通过类型化 Token，或 Dart `Type` 加可选 Qualifier 来定位。插件依赖接口或 Capability，而不是具体类。例如 Birthday 请求 `PersonCapability` 和 `ReminderService`，不应导入 Family 的内部 Repository。

Core Service 的作用域属于 `PiRuntime`。平台实现由 App 组合入口提供：

```dart
final runtime = PiRuntime(
  services: [
    SqliteDataStore(...),
    LocalNotificationService(...),
    SecureSettingsStore(...),
  ],
  plugins: [TodoPlugin(), BirthdayPlugin(), NotesPlugin()],
);
```

组合入口是唯一选择实现的地方。因此替换实现或为测试注入 Fake，只需要修改 App 组装代码。

## 7. Event

`PiEventBus` 支持带取消句柄的类型化事件：

```dart
final subscription = events.on<TodoCompleted>((event) { ... });
// PluginHandle 会在卸载时负责取消 subscription。
```

Transient Event 是内存中的实时通知，用于 UI 和插件协调。Domain Event 是持久化事实；当插件要求持久化时，应与 Entity 修改在同一个事务中写入。持久化事件用于集成、导入导出和诊断，V1 不通过重放全部事件来重建状态。

Event 名称和 Payload 都是带版本的协议。Listener 必须能够忽略自己不理解的事件；单个 Listener 的错误应按 Listener 记录日志，不能中断整个 Event Bus。

## 8. 数据模型与存储

默认实现使用 Drift（或同等成熟的 SQLite package）封装 SQLite，由 `PiDataStore` 隔离底层细节。SQLite 能够提供事务、索引、Migration、备份和可靠的离线行为，不需要服务端。

Core 为插件定义的 Entity 保存统一 Envelope：

```text
entities(
  id TEXT PRIMARY KEY,
  plugin_id TEXT NOT NULL,
  type TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  payload JSON/BLOB NOT NULL,
  metadata JSON/BLOB,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL
)
```

默认索引覆盖 `(plugin_id, type, updated_at)`，插件可以为确有查询需要的字段声明额外索引。插件提供类型化 Repository，负责校验和映射 Payload；业务代码永远不能直接调用 SQLite。查询需求足够明确时，插件可以通过 Migration 增加类型化 Projection 或索引。

每个插件声明按顺序执行的 Migration。Migration 在插件激活前、事务内运行。Entity Reference 使用稳定 ID 和声明的目标类型；删除策略由拥有该关系的 Repository 明确选择（限制、解除关系或级联），并负责执行。可恢复的用户数据可以使用 Soft Delete，但不要求所有 Entity 都采用它。

Store 提供事务边界和基于 `updatedAt`/Revision 的乐观并发检查。审计历史是可选的插件数据，不是 Core 级别的事件溯源要求。

## 9. 导入、导出与数据主权

标准交换格式是带版本的 ZIP 包：

```text
manifest.json
entities/<plugin-id>.jsonl
attachments/<sha256>
```

`manifest.json` 记录格式版本、App 版本、插件 ID、Entity 类型和导出时间。每个 Entity 至少包含 `id`、`pluginId`、`type`、`schemaVersion`、`createdAt`、`updatedAt`、`metadata`、Payload 和 References。JSON 是主要的可读格式；有意义的插件可以额外提供 Markdown 或 CSV 导出。

导入按包分事务处理，先校验插件和 Schema 兼容性，保留未知插件的记录以便再次导出，并报告冲突而不是静默覆盖。导出支持全部数据、指定插件或指定 Entity 类型。附件采用内容寻址，并与数据一起放入同一个包。

## 10. Reminder Runtime

Reminder 是 Core 提供的基础能力，插件只负责使用。插件声明 Reminder 时，需要提供所属 Entity ID、Schedule、时区、Locale、通知 Channel 和完成策略。Runtime 负责去重、调度、Snooze、Skip、取消、重新调度以及平台通知适配器。

Schedule 模型覆盖单次时间点、事件前偏移，以及日/周/月/年和每 N 个单位的日历重复。Reminder 拥有稳定 ID 和幂等 Key，因此插件重启不会创建重复通知。Runtime 持久化 Reminder 定义和下次触发时间；平台适配器在 App 启动和时区变化后重新对齐系统通知。

插件负责领域含义：Birthday 提供每年发生的事件和显示文本，Reminder Runtime 负责投递和完成状态。

## 11. UI 组合

`pi_ui` 提供 Shell 和命名扩展点，而不是固定的功能首页。初始 Slot 包括 `home.primary`、`home.secondary`、`quick-actions`、`search.providers`、`settings.sections` 和 `profile.sections`。

```dart
ui.slots.register(
  slot: 'home.primary',
  id: 'dev.pi.todo.today',
  order: 20,
  builder: (context) => const TodoTodayWidget(),
);
```

Registry 根据 Profile 配置和插件优先级对 Contribution 排序。Shell 渲染所有已注册的 Contribution，也能处理没有任何 Contribution 的空状态。导航同样通过 Route ID 和 Builder 注册。不会出现包含 `if (todoEnabled)` 分支的固定 `HomePage`。

UI Contribution 是可选的。纯 Headless 插件可以只提供数据、Command 或 AI Tool；同一个插件也可以提供同一能力的多种呈现方式。

## 12. App Profile 与构建期组合

App Profile 描述一个发行版选用的插件和展示默认值：

```yaml
id: pi.personal
plugins:
  - dev.pi.todo
  - dev.pi.birthday
theme: system
startupRoute: /home
```

V1 中，这个文件由工具或代码生成器读取，但实际 Dart package 仍然是显式依赖。生成的 `PiComposition` 负责把 Manifest 和构造函数接入 App。这样 `Pi Personal` 和 `Pi Family` 可以共享 Runtime package，却编译出不同的插件集合和默认布局。用户设置可以运行时启用或停用已经打包的插件；新增可执行代码仍然需要重新构建。

## 13. AI 能力

AI 是可替换的 Provider Capability。`pi_ai` 定义 `generate`、`stream`、可选的 Embedding 和 Tool Call。内置适配器包括 OpenAI-compatible HTTP Provider；其他 package 可以实现 OpenAI、Anthropic、DeepSeek、Gemini、Ollama 或本地 Provider。

API Key、Base URL、Model 名称和对话历史都保存在本地。Secret 通过平台安全存储适配器保存。Pi 不提供代理服务，也不会上传用户的 Key。

插件以命名空间方式注册 Tool，例如 `todo.list` 和 `birthday.next`，同时提供 JSON Schema 和所需 Permission。Agent 只能看到当前 Profile 和用户授予的 Tool。读权限和写权限必须区分；敏感领域可以要求每次操作显式确认。Tool 执行仍然经过插件自己的 Service 接口，因此 AI 不能绕过授权和校验直接修改数据。

## 14. 权限与安全

权限在插件 Manifest 中声明，并在 Capability 边界检查。初始类别包括存储、通知、联系人、日历、健康、定位、AI 和敏感数据。App 为 Profile 展示可审查的权限摘要，并在本地保存授权结果。

Flutter 插件本质上是签名的原生应用代码，因此 V1 提供透明度和 Capability 边界，而不宣称实现沙箱隔离。Runtime 拒绝未声明的 Capability 访问，记录敏感操作的诊断审计信息，并禁止从网络加载可执行代码。未来的 Registry 可以发布元数据、Hash、兼容性、许可证和截图，但不改变执行模型。

## 15. MVP 范围

第一条纵向切片应该证明“可以组合”，而不是追求业务数量：

1. `pi_core` 和 `pi_runtime`：Manifest、依赖图、作用域 Service、Handle、生命周期和 Diagnostics。
2. `pi_data` + SQLite Adapter：Envelope Entity、Repository、Migration、事务以及导入导出。
3. `pi_reminder`：持久化 Schedule 和本地通知适配器，测试中使用 Fake Adapter。
4. `pi_ui`：Shell、Route Registry、Home Slot、Settings Slot 和 Quick Action。
5. 插件：Todo、Birthday、Notes。Birthday 使用由共享 People package 或插件提供的 Person Capability，并使用 Core Reminder。
6. `pi_ai`：一个 OpenAI-compatible Provider、本地多 Key 配置，以及只读的 Todo/Birthday Tool。AI Provider 是共享 Capability，不作为插件安装。
7. 两个生成的 Profile：Todo + Birthday + Notes，以及 Todo + Notes。两者的 Route 和 Dashboard Contribution 自动不同。

Health、Family、Finance、日历集成、更复杂的重复规则和可写 AI，都应在这条切片稳定后再加入。

## 16. 测试策略

测试重点放在协议和清理能力：

- 生命周期状态转换、依赖顺序、循环依赖/失败处理，以及逆序卸载。
- Registry 清理：卸载后 Route、Slot、Service、Stream、Timer 和通知 ID 都应消失。
- Event 投递、取消、持久化事件的事务行为，以及 Listener 隔离。
- 从历史 Fixture 版本执行 Migration、事务回滚、Reference、索引和导入导出往返，包括未知插件数据。
- Reminder 在时区/Locale 变化下的重复计算、Snooze/Skip/Complete、幂等性和重启后的重新对齐。
- AI Provider 的流式响应/错误归一化，以及 Tool Call 的权限检查。
- 两个 Profile 的 UI Slot 组合；使用 Fake Runtime，只有稳定的布局才编写 Golden Test。

每个插件都应该能通过内存 Data Store、Fake Clock、Fake Notification Service 和隔离的 `PiRuntime` 测试；测试不能依赖进程级全局状态。

## 17. 演进路线

需要保持稳定的边界包括 Plugin Manifest、Capability 接口、Entity Envelope、Event Schema 和 Profile 配置。未来可以增加发布元数据和 package 引用的 Registry，可以让桌面端支持更丰富的动态扩展，可以把同步实现为另一种 Data Store Adapter，也可以增加本地 AI Provider，而无需修改 Core。

这些扩展必须保留 V1 规则：新增领域或 Provider 应该成为插件，Runtime 继续负责组合和生命周期，而不是承载业务规则。

## 18. 评审清单

向 Core 增加代码前，先判断它是否确实服务于生命周期、组合、持久化或跨插件基础能力。如果代码中出现具体领域名称，它就应该属于插件。评审插件时，确认它声明了依赖和权限，使用协议 Service，拥有自己的 Migration，并且卸载后不会残留任何注册项。

## 19. 双层插件架构：普通用户模式与开发者模式

可以同时提供“普通用户无需构建即可组合”和“开发者可以编写新插件并自行构建”两种玩法，但必须区分两件事：

1. **插件代码是否已经存在于当前 App 中。**
2. **插件当前是否加入某个用户 Profile 并处于激活状态。**

Flutter/iOS 的普通发布包不能安全地下载并执行任意新的 Dart/Flutter 代码。因此，普通用户模式的“安装”不是下载可执行代码，而是从当前 App 已经包含的内置插件目录中把插件加入 Profile。开发者模式则在构建期把新插件代码加入 App。

### 19.1 四个层次

```text
Plugin package（Dart/Flutter 代码）
        ↓ 构建时编译进 App
Plugin artifact（代码、资源、Manifest、Factory）
        ↓ 启动时登记
Built-in Plugin Catalog（当前 App 可用的插件目录）
        ↓ 用户或 Profile 选择
Profile Activation State（启用、停用、配置、权限）
        ↓ Runtime 生命周期
Active Plugin（Service、Route、Slot、Event、Reminder、Tool）
```

这四层分别解决不同问题：

- **Package** 是开发者写的源码包。
- **Artifact** 是已经编译进 App 的可执行插件。
- **Catalog** 是当前 App 能够提供哪些插件的清单。
- **Activation State** 是用户决定哪些插件在当前 Profile 中运行的状态。

不要把 Catalog 和 Activation State 混成一个概念。插件可以存在于 App 的 Catalog 中，但没有被用户启用；插件也可以因为依赖或权限问题暂时处于 `blocked` 状态。

### 19.2 普通用户模式：内置插件的安装与卸载

App 内置一个 `PluginCatalog`，每个条目包含插件 Descriptor 和一个由构建期生成的 Factory：

```dart
class PluginDescriptor {
  final String id;
  final String version;
  final String name;
  final String description;
  final PluginSource source;       // builtIn 或 customBuild
  final Set<String> dependencies;
  final Set<Permission> permissions;
  final PluginFactory create;
}
```

普通用户在 Plugin Manager 中看到的是 Catalog 中的元数据，可以执行：

- **添加到当前 Profile**：写入启用状态，解析依赖，运行 Migration，然后启动插件。
- **停用**：停止插件并释放它拥有的所有资源，但保留插件数据和配置。
- **从 Profile 移除**：停用后不再显示其 UI 和导航入口；默认保留数据，方便以后重新启用。
- **卸载并清理数据**：在明确确认并提供导出选项后，删除该插件的 Entity、附件、设置和 Reminder。
- **恢复默认配置**：仅清理插件设置，不删除领域数据。

因此，用户感知上可以像安装/卸载普通插件一样操作；实际执行的是对已签名代码的启用、停用和数据策略管理。停用时，`PluginHandle.dispose()` 必须移除 Route、Slot、Listener、Timer、Service、Reminder 和 AI Tool，避免重新启用后重复注册。

推荐将“停用”和“删除数据”分开。用户误操作移除插件时，数据默认仍然可恢复；只有选择“卸载并清理数据”时才执行破坏性删除。

### 19.3 Profile 级状态，而不是全局开关

同一 App 可以存在多个 Profile，每个 Profile 单独保存插件状态：

```yaml
profiles:
  personal:
    enabledPlugins: [dev.pi.todo, dev.pi.birthday]
  minimal:
    enabledPlugins: [dev.pi.todo]
```

`PluginActivationStore` 只保存用户选择、插件配置、授权结果和数据保留策略；它不保存可执行代码。切换 Profile 时，Runtime 计算差异：先卸载当前多余插件，再按依赖顺序启动新增插件。这样同一个安装包可以表现成多个不同的个人 App。

依赖处理遵循以下规则：

- 启用插件时自动启用当前 Catalog 中可用的必需依赖，并向用户说明新增的能力和权限。
- 仍有活跃依赖者时，不能单独停用被依赖插件；UI 应指出依赖链。
- 缺少依赖、版本不兼容或权限未授予时，插件进入 `blocked`，而不是让整个 Runtime 启动失败。
- 卸载数据前检查其他插件的 Entity Reference，并明确提示将要解除或删除的关系。

### 19.4 开发者模式：构建自己的插件和 App

开发者使用完全相同的 `PiPlugin`、Service、Event、Data、UI Slot 和 AI Tool API 编写新插件：

```text
my_pi_app/
  apps/my_app/
  packages/pi_plugin_collection/
  pi.yaml
```

`pi.yaml` 描述 Profile；`pubspec.yaml` 通过 pub、path 或 git dependency 引入插件。工具生成 `PiComposition` 和 `PluginCatalog` 注册代码：

```dart
final catalog = PluginCatalog([
  ...builtInPiPlugins,
  PluginDescriptor.from(CollectionPlugin()),
]);

final runtime = PiRuntime.fromProfile(
  composition: catalog,
  profile: appProfile,
);
```

开发者可以：

- fork Pi App Shell，编写只属于自己的插件和主题；
- 只选择 Runtime，不使用官方 App Shell，构建自己的发行版；
- 把新插件编译进自己的 App，并仍然让最终用户通过 Plugin Manager 启用或停用；
- 把插件作为独立 package 发布，供其他开发者在构建期引用；
- 在 App 更新中加入新版本插件，用户更新后再决定是否启用。

开发者新增的是 **Package/Artifact**，普通用户改变的是 **Activation State**。两者使用同一套运行时协议，因此不需要维护两套插件 API。

### 19.5 “安装”一词在两种模式中的准确含义

为了避免产品文案误导，内部最好使用更精确的状态名称：

| 用户看到的操作 | Runtime 实际动作 | 是否需要重新构建 |
| --- | --- | --- |
| 添加插件 | 将已在 Catalog 中的插件加入 Profile 并启动 | 否 |
| 停用插件 | 停止并释放该插件的 Runtime 资源 | 否 |
| 从当前 App 移除 | 从 Profile 删除，默认保留数据 | 否 |
| 删除插件数据 | 删除该插件数据和附件 | 否 |
| 安装开发者新插件 | 将新的 Dart/Flutter package 编译进 App | 是 |
| 更新插件代码 | 发布包含新 Artifact 的 App 版本 | 是 |

对普通用户可以继续使用“安装/卸载”这样的产品语言；设置页和开发者文档应说明“内置插件的代码随 App 提供，卸载主要意味着停用和移除数据”。

### 19.6 成本和边界

这种方案的代价是：内置插件即使未启用，代码和部分资源仍然会增加 App 包体积；“卸载”也不能从已经签名的二进制中删除代码。可以通过延迟加载图片、按平台拆分资源、拆分可选的原生模块和构建多个发行版来控制体积，但不能把它描述成真正的动态代码安装。

如果未来必须支持 App 发布后下载新能力，需要另外定义受限的插件层，例如声明式 Widget/Data DSL、WASM 沙箱或桌面端的进程/IPC 扩展。那会是一个独立的 `SandboxedPlugin` 协议，不能直接把普通 Flutter package 当作远程插件执行，也不能绕过移动平台的签名和审核约束。

### 19.7 推荐的实现对象

双层架构至少需要以下几个对象：

- `PluginCatalog`：当前构建包含哪些 Plugin Descriptor 和 Factory。
- `PluginActivationStore`：每个 Profile 的启用、停用、配置和授权状态。
- `PluginManager`：执行添加、停用、移除、数据清理、依赖解析和版本升级。
- `PluginRuntime`：执行 `register/start/stop/dispose`，持有每个插件的 `PluginHandle`。
- `PluginDataNamespace`：按照 `pluginId` 隔离 Entity、附件、设置和 Reminder。
- `PluginMigrationRunner`：只为已启用或即将启用的插件执行 Schema Migration。
- `PluginDiagnostics`：记录失败原因、依赖链、权限请求和资源清理结果。

推荐的状态机是：

```text
available → enabling → active → disabling → disabled
     │             │                  │
     └─────────────┴→ blocked          └→ data deleted
```

`available` 表示代码和 Manifest 已在当前 Catalog 中；`active` 才表示插件正在贡献能力。数据是否存在由独立的数据保留策略决定，不能从 `disabled` 状态直接推断数据已经删除。
