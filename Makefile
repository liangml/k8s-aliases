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
test: build ## 全面验证：烟雾测试 → 总量 → 去重 → 互斥 → 特殊别名 → fish
	@./$(APP) -o /tmp/_kubectl_aliases_test; \
	fail=0; \
	ok() { printf "  ok  %s\n" "$$1"; }; \
	fail() { printf "  FAIL %s\n" "$$1"; fail=$$((fail+1)); }; \
	check_alias() { bash -c 'unset _K8S_ALIAS_LOADED; source /tmp/_kubectl_aliases_test && alias "$$1" >/dev/null 2>&1' _ "$$1" && ok "$$1" || fail "$$1 missing"; }; \
	check_cmd() { local g=; g=$$(bash -c 'unset _K8S_ALIAS_LOADED; source /tmp/_kubectl_aliases_test && alias "$$1" 2>/dev/null' _ "$$1"); [ "$$g" = "alias $$1='$$2'" ] && ok "$$1" || fail "$$1 (expected: $$2)"; }; \
	\
	echo "=== 1/6 烟雾测试 ==="; \
	check_alias kgpo; check_alias kdelpo; \
	./$(APP) --version 2>&1 | grep -q . && ok "--version" || fail "--version"; \
	\
	echo "=== 2/6 总量 691 ==="; \
	c=$$(bash -c 'unset _K8S_ALIAS_LOADED; source /tmp/_kubectl_aliases_test && alias | grep -c kubectl'); \
	[ "$$c" = "691" ] && ok "total=691" || fail "total=$$c (expected 691)"; \
	\
	echo "=== 3/6 去重 ==="; \
	d=$$(grep '^alias' /tmp/_kubectl_aliases_test | sed 's/^alias \([^=]*\)=.*/\1/' | sort | uniq -d); \
	[ -z "$$d" ] && ok "no dupes" || fail "dupes: $$d"; \
	\
	echo "=== 4/6 互斥组合 ==="; \
	grep -q 'no.*--all-namespaces\|ns.*--all-namespaces' /tmp/_kubectl_aliases_test && fail "no/ns+all" || ok "no/ns+all excluded"; \
	grep -q 'ksys.*--all-namespaces' /tmp/_kubectl_aliases_test && fail "sys+all" || ok "sys+all excluded"; \
	grep '^alias' /tmp/_kubectl_aliases_test | grep -qE '(oyaml.*owide|owide.*oyaml|oyaml.*ojson|ojson.*owide)' && fail "conflicting mods" || ok "no conflicting mods"; \
	\
	echo "=== 5/6 关键别名精确匹配 ==="; \
	check_cmd kgpo   'kubectl get pods'; \
	check_cmd kdelpo 'kubectl delete pods'; \
	check_cmd ksysg  'kubectl get --namespace=kube-system'; \
	check_cmd krun   'kubectl run --rm --restart=Never --image-pull-policy=IfNotPresent -i -t'; \
	check_cmd kdelnow 'kubectl delete --grace-period=0 --force'; \
	check_cmd kctx   'kubectl config use-context'; \
	check_cmd kl     'kubectl logs'; \
	check_cmd kex    'kubectl exec -i -t'; \
	\
	echo "=== 6/6 fish 输出 ==="; \
	fc=$$(./$(APP) -shell fish 2>/dev/null | grep -c '^abbr'); \
	[ "$$fc" = "691" ] && ok "fish=691" || fail "fish=$$fc (expected 691)"; \
	echo; \
	if [ "$$fail" -eq 0 ]; then echo "=== 全部通过 ==="; else echo "=== $$fail 个失败 ==="; fi; \
	exit $$fail

.PHONY: help
help: ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
