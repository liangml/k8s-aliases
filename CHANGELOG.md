# Changelog

## v1.0.0 (2026-06-11)

### Added
- Go 重写的别名生成器 (`main.go`)，替代旧版 Python 实现
- 覆盖 **9 种资源类型**（po/dep/sts/svc/ing/cm/sec/no/ns）× 3 个动词（get/describe/delete）× 格式/范围修饰符
- 自动处理兼容性约束，生成 **691 个** 可直接使用的 shell 别名
- 30+ 实用特殊别名：`krun`、`ka`/`kak`/`kk`、`kdelnow`/`kdelall`、`kdrain`、`kcordon`、`kuncordon`、`kctx`、`kns`、`klabel`、`kannotate`、`kcp`、`ked`、`kroll*`、`ktop` 等
- 支持 3 种 Shell 输出：bash、zsh、fish
- `--version` / `--help` 命令行标志
- 多行注释 header，自动标明生成器和目标 Shell
- 输出文件分组排列（按功能分类）
- `make dist` 一键构建全部产物（别名文件 + 5 平台二进制）
- GitHub Releases 自动发布：打 `v*` tag 即自动构建并上传产物

### Changed
- 架构从 Python 单文件生成器迁移为 Go 模块化方案（Builder + Strategy + Composite 模式）
- 命名规则调整：格式修饰符在范围修饰符之前（如 `kgpooyamlall` 而非 `kgpoalloyaml`）
- 移除无效别名：nodes/namespaces + `--all-namespaces`、sys scope + `--all-namespaces`、`ksysrunn` 重复项

### Infrastructure
- Makefile：build/release/test/generate/dist/clean/help，交叉编译 5 平台，版本号通过 ldflags 注入
- Dockerfile：多阶段构建（golang:1.23 → alpine:3.21），非 root 用户
- GitHub Actions CI：4 阶段管道（lint → 安全扫描 → 构建测试 → Docker）
- GitHub Actions Release：打 tag 自动构建并发布到 Releases
- `.gitignore`：排除编译产物、IDE 配置、临时文件
- `go.mod`：Go module 初始化
- ShellCheck、Trivy、govulncheck 安全扫描集成

### Removed
- `generate_aliases.py`：旧版 Python 生成器（由 Go 版本替代）
- `.kubectl_aliases.nu`：Nushell 支持（Go 版本暂不支持）
- `ksysrunn`：死别名（与 `ksysrun` 命令完全相同）
