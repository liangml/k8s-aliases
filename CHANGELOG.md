# Changelog

## v1.0.0 (2026-06-11)

### Added
- Go 编写的 kubectl 别名生成器 (`main.go`)
- 覆盖 **9 种资源类型**（po/dep/sts/svc/ing/cm/sec/no/ns）× 3 个动词（get/describe/delete）× 格式/范围修饰符
- 自动处理兼容性约束，生成 **691 个** 可直接使用的 shell 别名
- 30+ 实用特殊别名：`krun`、`ka`/`kak`/`kk`、`kdelnow`/`kdelall`、`kdrain`、`kcordon`、`kuncordon`、`kctx`、`kns`、`klabel`、`kannotate`、`kcp`、`ked`、`kroll*`、`ktop` 等
- 支持 3 种 Shell 输出：bash、zsh、fish
- `--version` / `--help` 命令行标志
- 输出文件分组排列（按功能分类）
- `make dist` 一键构建全部产物（别名文件 + 5 平台二进制）
- GitHub Releases 自动发布：打 `v*` tag 即自动构建并上传产物

### Infrastructure
- Makefile：build/release/test/generate/dist/clean/help，交叉编译 5 平台，版本号通过 ldflags 注入
- Dockerfile：多阶段构建（golang:alpine → alpine:latest），非 root 用户
- GitHub Actions CI/Release 自动构建与发布
- ShellCheck、Trivy、govulncheck 安全扫描集成

### Fixed
- Source guard POSIX 兼容（bash/zsh/ash/dash）
- 特殊别名优先级高于生成器组合
- Docker 构建版本适配
