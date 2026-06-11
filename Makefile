APP     := kubectl-aliases
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

# 目标平台: OS × Arch
BUILDS := \
	darwin/amd64 \
	darwin/arm64 \
	linux/amd64 \
	linux/arm64 \
	windows/amd64

default: build

.PHONY: build
build: ## 编译当前平台可执行文件
	go build -ldflags="-X main.version=$(VERSION)" -o $(APP) main.go

.PHONY: release
release: clean ## 编译所有平台（cross-compile）
	@mkdir -p dist
	@for plat in $(BUILDS); do \
		os=$$(echo $$plat | cut -d/ -f1); \
		arch=$$(echo $$plat | cut -d/ -f2); \
		ext=""; \
		[ "$$os" = "windows" ] && ext=".exe"; \
		name="$(APP)-$${os}-$${arch}$${ext}"; \
		echo "  >> $$name"; \
		GOOS=$$os GOARCH=$$arch go build -ldflags="-s -w -X main.version=$(VERSION)" -o "dist/$$name" main.go; \
	done
	@echo "=== dist/ ===" && ls -lh dist/

.PHONY: generate
generate: build ## 生成 .kubectl_aliases + .kubectl_aliases.fish
	./$(APP) -o .kubectl_aliases
	./$(APP) -shell fish -o .kubectl_aliases.fish

.PHONY: dist
dist: generate release ## 构建全部产物（别名文件 + 交叉编译）
	@echo "=== dist 完成 ==="
	ls -lh .kubectl_aliases .kubectl_aliases.fish dist/

.PHONY: clean
clean: ## 清理构建产物
	rm -rf $(APP) dist/

.PHONY: test
test: build ## 生成并验证
	./$(APP) -o /tmp/_kubectl_aliases_test
	@echo "=== alias smoke test ==="
	bash -c 'unset _K8S_ALIAS_LOADED; source /tmp/_kubectl_aliases_test && alias kgpo && alias kdelpo && echo "PASS"'
	@echo "=== --version ==="
	./$(APP) --version | grep -q . && echo "PASS"
	@echo "=== go vet ==="
	go vet ./... && echo "PASS"

.PHONY: help
help: ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
