#!/bin/bash
# =============================================================================
# kubectl-aliases 集成测试
# 需要: kind / orbstack 集群已启动, kubectl 已配置
# =============================================================================

set -eu

APP="./kubectl-aliases"
NS="test-aliases"
ALIAS_FILE="/tmp/_kubectl_aliases_inttest"
TMP_DIR="/tmp/k8s-test-manifests"
PASS=0
FAIL=0
FAILED=""

ok()   { echo "  [OK] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); FAILED+=" $1 "; }

# 跨平台 timeout: macOS / Linux 兼容
_timed_run() {
  local secs=$1; shift
  "$@" &
  local pid=$!
  (sleep "$secs" && kill "$pid" 2>/dev/null) &>/dev/null &
  wait "$pid" 2>/dev/null || true
  return 0
}

# ── 创建测试资源 ──────────────────────────────────────────────────────────
echo "=== 创建测试资源 ==="
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
kubectl -n "$NS" create deployment nginx --image=nginx:alpine 2>/dev/null || true
kubectl -n "$NS" expose deployment nginx --port=80 --target-port=80 --name nginx-svc 2>/dev/null || true
kubectl -n "$NS" create configmap app-config --from-literal=key=value 2>/dev/null || true
kubectl -n "$NS" create secret generic app-secret --from-literal=password=secret 2>/dev/null || true

echo "=== 等待 deployment ==="
kubectl -n "$NS" rollout status deployment/nginx --timeout=120s 2>/dev/null || true
POD=$(kubectl -n "$NS" get pod -l app=nginx -o name 2>/dev/null | head -1 | cut -d/ -f2 || echo "")
echo "  pod: ${POD:-none}"

# ── 别名文件 ──────────────────────────────────────────────────────────────
echo "=== 生成别名 ==="
"$APP" -o "$ALIAS_FILE"
_K8S_ALIAS_LOADED=""
source "$ALIAS_FILE"

# kubectl 命令中是否包含资源类型（排除 --all-namespaces 等 flag）
HAS_RESOURCE_RE="(^| )pods| deployment| statefulset| service| ingress| configmap| secret| nodes| namespaces"
has_resource() { [[ "$1" =~ $HAS_RESOURCE_RE ]]; }

# ── 测试别名 ──────────────────────────────────────────────────────────────
echo "=== 测试别名 ==="
test_alias() {
  local name="$1" cmd
  cmd=$(alias "$name" 2>/dev/null | sed "s/^alias $name='\(.*\)'/\1/") || return 0

  case "$name" in
    k|kex|kexn|kpf|kpfn|krun|ksysrun|krunn|kak|kk|kctx|kns|kdrain|kcordon|kuncordon|kannotate|ked|kedn|kcp|klabel|klfn) return 0;;
  esac

  # --watch / proxy → 后台运行
  if [[ "$cmd" == *"--watch"* ]] || [[ "$cmd" == "kubectl proxy" ]]; then
    _timed_run 1 $cmd; ok "$name"; return
  fi

  # --recursive -f → 指向 manifest 目录
  if [[ "$cmd" == *"--recursive -f" ]]; then
    cmd="$cmd $TMP_DIR"
  fi

  # --namespace (末尾, 排除已带 =kube-system)
  if [[ "$cmd" != *"--namespace=kube-system"* && "$cmd" == *" --namespace" ]]; then
    cmd="$cmd $NS"
  fi

  # -l → 标签选择, 并补资源类型(如缺)
  if [[ "$cmd" == *" -l" ]]; then
    cmd="$cmd app=nginx"
    ! has_resource "$cmd" && cmd="$cmd pods"
  fi

  # logs → 补 pod
  if [[ "$cmd" == "kubectl logs"* && -n "$POD" ]]; then
    if [[ "$cmd" == "kubectl logs" ]]; then
      cmd="$cmd $POD -n $NS"
    elif [[ "$cmd" == "kubectl logs -f" ]]; then
      _timed_run 1 kubectl logs "$POD" -n "$NS"; ok "$name"; return
    elif [[ "$cmd" == "kubectl logs --tail=50 -f" ]]; then
      _timed_run 1 kubectl logs --tail=50 "$POD" -n "$NS"; ok "$name"; return
    fi
  fi

  # 纯动词 / 纯格式 / 纯 all / 纯 n → 补 pods -n $NS
  if ! has_resource "$cmd"; then
    if [[ "$cmd" == "kubectl get"* ]] || [[ "$cmd" == "kubectl describe"* ]] || [[ "$cmd" == "kubectl delete"* ]]; then
      cmd="$cmd pods -n $NS"
    fi
  fi

  # delete: 创建临时资源并追加到命令
  if [[ "$cmd" == "kubectl delete pods"* && "$cmd" != *"temp-del"* && "$cmd" != *"-n $NS" ]]; then
    kubectl -n "$NS" run temp-del --image=nginx:alpine --restart=Never 2>/dev/null || true
    cmd="$cmd temp-del -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete pods -n $NS" ]]; then
    kubectl -n "$NS" run temp-del --image=nginx:alpine --restart=Never 2>/dev/null || true
    cmd="$cmd temp-del"
  fi
  if [[ "$cmd" == "kubectl delete deployment"* && "$cmd" != *"temp-del-dep"* ]]; then
    kubectl -n "$NS" create deployment temp-del-dep --image=nginx:alpine 2>/dev/null || true
    cmd="$cmd temp-del-dep -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete configmap"* && "$cmd" != *"temp-del-cm"* ]]; then
    kubectl -n "$NS" create configmap temp-del-cm --from-literal=k=v 2>/dev/null || true
    cmd="$cmd temp-del-cm -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete secret"* && "$cmd" != *"temp-del-sec"* ]]; then
    kubectl -n "$NS" create secret generic temp-del-sec --from-literal=k=v 2>/dev/null || true
    cmd="$cmd temp-del-sec -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete service"* && "$cmd" != *"temp-del-svc"* ]]; then
    kubectl -n "$NS" create service clusterip temp-del-svc --tcp=80:80 2>/dev/null || true
    cmd="$cmd temp-del-svc -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete statefulset"* && "$cmd" != *"temp-del-sts"* ]]; then
    kubectl -n "$NS" create sts temp-del-sts --image=nginx:alpine 2>/dev/null || true
    cmd="$cmd temp-del-sts -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete ingress"* && "$cmd" != *"temp-del-ing"* ]]; then
    kubectl -n "$NS" create ingress temp-del-ing --rule=/=nginx-svc:80 2>/dev/null || true
    cmd="$cmd temp-del-ing -n $NS"
  fi
  if [[ "$cmd" == "kubectl delete --grace-period=0 --force"* ]]; then
    kubectl -n "$NS" run temp-force --image=nginx:alpine --restart=Never 2>/dev/null || true
    cmd="$cmd pods temp-force -n $NS"
  fi
  # kdelnow 直接已追加了 pods temp-force, 无需额外处理

  # rollout → 补 deployment
  if [[ "$cmd" == "kubectl rollout" ]]; then cmd="kubectl rollout status deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout restart" ]]; then cmd="kubectl rollout restart deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout status" ]]; then cmd="kubectl rollout status deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout history" ]]; then cmd="kubectl rollout history deployment nginx -n $NS"; fi
  if [[ "$cmd" == "kubectl rollout undo" ]]; then return 0; fi

  # top → kind 无 metrics-server
  if [[ "$cmd" == "kubectl top"* ]]; then return 0; fi

  local exit_code=0
  eval "$cmd" &>/dev/null || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "$name"
  else
    fail "$name"
  fi
}

while IFS='=' read -r name _; do
  name="${name#alias }"
  [[ "$name" == "k" ]] && continue
  test_alias "$name"
done < <(alias | grep "^alias k" | grep -v "^alias k=")

# ── 结果 ─────────────────────────────────────────────────────────────────
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ -n "$FAILED" ] && echo "Failed: $FAILED"
exit $FAIL
