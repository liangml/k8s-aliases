#!/bin/bash
# =============================================================================
# kubectl-aliases 集成测试
# 需要: kind 集群已启动, kubectl 已配置
# =============================================================================

set -eu

APP="./kubectl-aliases"
NS="test-aliases"
ALIAS_FILE="/tmp/_kubectl_aliases_inttest"
PASS=0
FAIL=0
FAILED=""

ok()   { echo "  [OK] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); FAILED+=" $1 "; }

# ── 准备测试资源 ──────────────────────────────────────────────────────────
echo "=== 创建测试资源 ==="
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
kubectl -n "$NS" create deployment nginx --image=nginx:alpine 2>/dev/null || true
kubectl -n "$NS" expose deployment nginx --port=80 --target-port=80 --name nginx-svc 2>/dev/null || true

echo "=== 等待 deployment 就绪 ==="
kubectl -n "$NS" rollout status deployment/nginx --timeout=120s 2>/dev/null || true

POD=$(kubectl -n "$NS" get pod -l app=nginx -o name 2>/dev/null | head -1 | cut -d/ -f2 || echo "")
echo "  pod: ${POD:-none}"

# ── 生成别名 ─────────────────────────────────────────────────────────────
echo "=== 生成别名 ==="
"$APP" -o "$ALIAS_FILE"
source "$ALIAS_FILE"

# ── 测试别名 ─────────────────────────────────────────────────────────────
echo "=== 测试别名 ==="
test_alias() {
  local name="$1" cmd
  cmd=$(alias "$name" 2>/dev/null | sed "s/^alias $name='\(.*\)'/\1/") || return 0

  case "$name" in
    k|kex|kpf|krun|ksysrun|krunn|kak|kk|kctx|kns|kdrain|kcordon|kuncordon|kannotate|ked|kedn) return 0;;
  esac

  # 补参数
  [[ "$cmd" == *"--watch"* ]] && cmd="timeout 3 $cmd"
  [[ "$cmd" == "kubectl proxy" ]] && cmd="timeout 3 $cmd"
  [[ "$cmd" == *"--recursive -f" ]] && cmd="$cmd /tmp/"
  [[ "$cmd" != *"--namespace=kube-system"* && "$cmd" == *" --namespace" ]] && cmd="$cmd $NS"
  [[ "$cmd" == *" -l" ]] && cmd="$cmd app=nginx"
  [[ "$cmd" == "kubectl logs" && -n "$POD" ]] && cmd="$cmd $POD -n $NS"
  [[ "$cmd" == "kubectl logs -f"* && -n "$POD" ]] && cmd="timeout 3 $cmd $POD -n $NS"
  [[ "$cmd" == "kubectl logs --tail=50 -f"* && -n "$POD" ]] && cmd="timeout 3 $cmd $POD -n $NS"

  if [[ "$cmd" == "kubectl delete pods" ]]; then
    kubectl -n "$NS" run temp-del --image=nginx:alpine --restart=Never 2>/dev/null || true
    cmd="$cmd temp-del -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete --grace-period=0 --force" ]]; then
    kubectl -n "$NS" run temp-force --image=nginx:alpine --restart=Never 2>/dev/null || true
    cmd="$cmd pods temp-force -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete --all" ]]; then
    cmd="$cmd pods -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete --all --namespace=kube-system" ]] || \
     [[ "$cmd" == "kubectl delete --grace-period=0 --force --namespace=kube-system" ]]; then
    return 0
  fi

  if [[ "$cmd" == "kubectl rollout" ]]; then cmd="kubectl rollout status deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout restart" ]]; then cmd="kubectl rollout restart deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout status" ]]; then cmd="kubectl rollout status deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout history" ]]; then cmd="kubectl rollout history deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout undo" ]]; then return 0; fi
  if [[ "$cmd" == "kubectl apply --recursive -f"* ]]; then cmd="$cmd $NS"; fi

  if eval "$cmd" &>/dev/null; then ok "$name"; else fail "$name"; fi
}

while IFS='=' read -r name _; do
  [[ "$name" == "k" ]] && continue
  test_alias "$name"
done < <(alias | grep "^k" | grep -v "^k=")

# ── 结果 ─────────────────────────────────────────────────────────────────
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ -n "$FAILED" ] && echo "Failed: $FAILED"
exit $FAIL
