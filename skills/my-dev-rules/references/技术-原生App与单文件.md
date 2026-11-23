# 技术红线：原生 App（Swift/macOS） + 单文件离线交付物

> 通用底线见 `技术-通用红线.md`，本篇只写这两类的专属坑。

## Swift / macOS 原生 App

- **SwiftPM 可测性**：executable target 不能被 test target 用 `@testable import` 依赖；把可测逻辑拆成独立 library target，executable 只做入口。
- **跨 module 访问级别**：library target 里的 struct/class、成员、`init`、`@Published` 属性默认是 `internal`，跨 module 不可见；对外暴露的必须逐个显式 `public`，否则 UI 层 `import` 了照样报 "cannot find type in scope"。改完 clean 全量构建验证，别信增量缓存。
- **Swift 6 的 `Array.indices`**：返回 `RangeSet` 不是 `Range<Int>`，`ForEach` 直接用会类型不匹配；用 `0..<array.count` 配 `id: \.self`。
- **SwiftUI 三元分支类型**：没有 `Color.quaternary`（那是 ShapeStyle）；三元两侧 `Color` 与 `some ShapeStyle` 类型不一致会编译失败，用 `AnyShapeStyle` 包一层统一类型。
- **Mach API 三坑**：`Host.current().machHost` 不存在，用 `mach_host_self()`；`processor_cpu_load_info_data_t.cpu_ticks` 是四元组不是数组，不能下标循环，用 switch 逐项取；`MEMORY_INT32_SIZE` 未定义，用 `MemoryLayout<integer_t>.size`。
- **构建沙箱**：本机 SwiftPM 构建报 `sandbox-exec: Operation not permitted` 是工具链限制，不是代码缺陷；用 `swift build --disable-sandbox` / `swift test --disable-sandbox`，不为此改业务代码。
- **密钥卫生**：密钥只进系统钥匙串（`Security` 框架 `kSecClassGenericPassword`），源码/配置/docs 零明文；用 `security add-generic-password -U` 写入，验证时不回显 key，交付前 grep 全仓扫一遍。
- **App 启动验证**：用工具管理的后台任务启动，不用 shell `&`（命令结束进程被清掉，看起来像崩溃）；验证进程存活 + 无崩溃日志后必须停掉，不留残留。

## 单文件 / 离线交付物

- 单文件 HTML 必须内联 CSS/JS/SVG，**不引外部 CDN 与外部字体**，双击或本地静态服务即可运行。
- 中文字体导出 PDF 不依赖字体嵌入，可调系统打印另存 PDF。
- 交付时说明启动方式与访问地址，附已验证的功能清单。
- 原型/报告单页要真能点、真能滚，不留"示意一下"的死链。
