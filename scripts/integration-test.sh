#!/bin/bash
# =============================================================================
# kubectl-aliases 集成测试
# 需要: kind 集群已启动, kubectl 已配置
# 测试步骤:
#   1. 创建测试资源 (deploy, svc, sts, cm, sec, ing)
#   2. 生成别名文件并 source
#   3. 逐条别名展开后执行, 验证退出码
#   4. 清理测试资源
# =============================================================================

set -euo pipefail

APP="./kubectl-aliases"
NS="test-aliases"
ALIAS_FILE="/tmp/_kubectl_aliases_inttest"
TMP_MANIFEST_DIR="/tmp/test-manifests"
PASS=0
FAIL=0
FAILED_ALIASES=""

# ── 颜色 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}❌${NC} $1"; ((FAIL++)); FAILED_ALIASES+=" $1"; }

# ── 资源创建 ──────────────────────────────────────────────────────────────

create_resources() {
  echo "=== 创建测试资源 ==="

  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

  # namespaced 资源 (7 种)
  kubectl -n "$NS" create deployment nginx --image=nginx:alpine --port=80 2>/dev/null
  kubectl -n "$NS" expose deployment nginx --port=80 --name nginx-svc 2>/dev/null || true
  kubectl -n "$NS" create statefulset web --image=nginx:alpine 2>/dev/null || true
  kubectl -n "$NS" create configmap app-config --from-literal=key=value 2>/dev/null || true
  kubectl -n "$NS" create secret generic app-secret --from-literal=password=secret 2>/dev/null || true
  kubectl -n "$NS" create ingress test-ing --rule=/=nginx-svc:80 2>/dev/null || true
  kubectl -n "$NS" create service clusterip dummy --tcp=80:80 2>/dev/null || true

  # 等 nginx deployment 就绪
  echo "  等待 nginx deployment 就绪..."
  kubectl -n "$NS" wait --for=condition=available deployment/nginx --timeout=120s 2>/dev/null

  # 获取 nginx pod 名
  NGINX_POD=$(kubectl -n "$NS" get pod -l app=nginx -o name 2>/dev/null | head -1 | cut -d/ -f2)
  echo "  nginx pod: $NGINX_POD"

  # 创建临时 manifest 目录 (给 -f 命令用)
  mkdir -p "$TMP_MANIFEST_DIR"
  cat > "$TMP_MANIFEST_DIR/nginx.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-from-manifest
  labels:
    app: nginx
spec:
  containers:
    - name: nginx
      image: nginx:alpine
EOF
  # 不要 apply, 只是作为文件存在; -f 测试只读文件不需要 apply
}

cleanup() {
  echo "=== 清理 ==="
  kubectl delete namespace "$NS" --ignore-not-found --timeout=60s 2>/dev/null || true
  rm -rf "$TMP_MANIFEST_DIR" "$ALIAS_FILE"
}

# ── 别名测试入口 ──────────────────────────────────────────────────────────

test_alias() {
  local name="$1"
  local expanded

  # 跳过特殊别名
  case "$name" in
    k|kex|kpf|krun|ksysrun|krunn)  return 0 ;;  # 交互式 / 前台进程
    kak|kk)                         return 0 ;;  # 需要真实 kustomize 目录
    kctx|kns)                       return 0 ;;  # 会修改当前上下文
    kdrain|kcordon|kuncordon)       return 0 ;;  # 节点操作, 跳过
    kannotate)                      return 0 ;;  # 需要完整参数
  esac

  # 从 alias 展开命令
  expanded=$(alias "$name" 2>/dev/null | sed "s/^alias $name='\(.*\)'/\1/")
  [ -z "$expanded" ] && { fail "$name (alias not found)"; return 1; }

  # ── 参数补充 ──

  # 1) --watch → timeout 3
  if [[ "$expanded" == *"--watch"* ]]; then
    expanded="timeout 3 $expanded"
  fi

  # 2) proxy → timeout 3
  if [[ "$expanded" == "kubectl proxy" ]]; then
    expanded="timeout 3 $expanded"
  fi

  # 3) --recursive -f (末尾无资源, 需补路径)
  if [[ "$expanded" == *"--recursive -f" ]]; then
    expanded="$expanded $TMP_MANIFEST_DIR"
  fi

  # 4) --namespace (末尾, 需补 ns 名; 排除已带 =kube-system 的情况)
  if [[ "$expanded" != *"--namespace=kube-system"* ]]; then
    if [[ "$expanded" == *" --namespace" ]]; then
      expanded="$expanded $NS"
    fi
  fi

  # 5) -l 末尾 → 补标签
  if [[ "$expanded" == *" -l" ]]; then
    expanded="$expanded app=nginx"
  fi

  # 6) kubectl logs → 补 pod 名
  if [[ "$expanded" == "kubectl logs" ]]; then
    expanded="$expanded $NGINX_POD -n $NS"
  fi
  if [[ "$expanded" == "kubectl logs -f" ]]; then
    expanded="timeout 3 $expanded $NGINX_POD -n $NS"
  fi
  if [[ "$expanded" == "kubectl logs --tail=50 -f" ]]; then
    expanded="timeout 3 $expanded $NGINX_POD -n $NS"
  fi

  # 7) kubectl logs -f --namespace → 补 pod + ns
  if [[ "$expanded" == "kubectl logs -f --namespace" ]]; then
    expanded="timeout 3 $expanded $NS $NGINX_POD"
  fi

  # 8) kubectl describe <resource> (有资源无具体名) → describe all 即可
  #    无需额外参数, kubectl describe pods 会 describe 所有 pod

  # 9) kubectl delete pods → 创建临时 pod 再删
  if [[ "$expanded" == "kubectl delete pods" ]]; then
    kubectl -n "$NS" run temp-del --image=nginx:alpine --restart=Never 2>/dev/null || true
    kubectl -n "$NS" wait --for=condition=Ready pod/temp-del --timeout=30s 2>/dev/null || true
    expanded="$expanded temp-del -n $NS"
  fi
  # delete deployment → 创建临时 deploy 再删
  if [[ "$expanded" == "kubectl delete deployment" ]]; then
    kubectl -n "$NS" create deployment temp-del-dep --image=nginx:alpine 2>/dev/null || true
    expanded="$expanded temp-del-dep -n $NS"
  fi
  # delete statefulset → 创建临时 sts 再删
  if [[ "$expanded" == "kubectl delete statefulset" ]]; then
    kubectl -n "$NS" create sts temp-del-sts --image=nginx:alpine 2>/dev/null || true
    expanded="$expanded temp-del-sts -n $NS"
  fi
  # delete service → 创建临时 svc 再删
  if [[ "$expanded" == "kubectl delete service" ]]; then
    kubectl -n "$NS" create service clusterip temp-del-svc --tcp=80:80 2>/dev/null || true
    expanded="$expanded temp-del-svc -n $NS"
  fi
  # delete configmap → 创建临时 cm 再删
  if [[ "$expanded" == "kubectl delete configmap" ]]; then
    kubectl -n "$NS" create configmap temp-del-cm --from-literal=k=v 2>/dev/null || true
    expanded="$expanded temp-del-cm -n $NS"
  fi
  # delete secret → 创建临时 sec 再删
  if [[ "$expanded" == "kubectl delete secret" ]]; then
    kubectl -n "$NS" create secret generic temp-del-sec --from-literal=k=v 2>/dev/null || true
    expanded="$expanded temp-del-sec -n $NS"
  fi
  # delete ingress → 创建临时 ing 再删
  if [[ "$expanded" == "kubectl delete ingress" ]]; then
    kubectl -n "$NS" create ingress temp-del-ing --rule=/=nginx-svc:80 2>/dev/null || true
    expanded="$expanded temp-del-ing -n $NS"
  fi
  # delete namespaces → 跳过(太危险)
  if [[ "$expanded" == "kubectl delete namespaces" ]]; then
    return 0
  fi

  # 10) kdelnow / ksysdelnow → 创建临时 pod 再删
  if [[ "$expanded" == "kubectl delete --grace-period=0 --force" ]]; then
    kubectl -n "$NS" run temp-force-del --image=nginx:alpine --restart=Never 2>/dev/null || true
    expanded="$expanded pods temp-force-del -n $NS"
  fi
  if [[ "$expanded" == "kubectl delete --grace-period=0 --force --namespace=kube-system" ]]; then
    return 0  # 跳过 sys 的强制删除
  fi

  # 11) kdelall / ksysdelall → 创建临时资源再删 --all
  if [[ "$expanded" == "kubectl delete --all" ]]; then
    kubectl -n "$NS" run temp-all-del --image=nginx:alpine --restart=Never 2>/dev/null || true
    expanded="$expanded pods -n $NS"
  fi
  if [[ "$expanded" == "kubectl delete --all --namespace=kube-system" ]]; then
    return 0
  fi

  # 12) kubectl apply --recursive -f → 补路径
  if [[ "$expanded" == "kubectl apply --recursive -f" ]] || \
     [[ "$expanded" == "kubectl apply --recursive -f --namespace=kube-system" ]]; then
    expanded="$expanded $TMP_MANIFEST_DIR"
  fi

  # 13) kubectl edit → 跳过 (需要编辑器交互)
  if [[ "$expanded" == "kubectl edit" ]] || [[ "$expanded" == "kubectl edit --namespace" ]]; then
    return 0
  fi

  # 14) kubectl rollout (无资源) → 补 deployment
  if [[ "$expanded" == "kubectl rollout" ]]; then
    expanded="$expanded status deployment nginx -n $NS"
  fi
  if [[ "$expanded" == "kubectl rollout restart" ]]; then
    expanded="$expanded deployment nginx -n $NS"
  fi
  if [[ "$expanded" == "kubectl rollout status" ]]; then
    expanded="$expanded deployment nginx -n $NS"
  fi
  if [[ "$expanded" == "kubectl rollout history" ]]; then
    expanded="$expanded deployment nginx -n $NS"
  fi

  # 15) kubectl top → kind 无 metrics-server, 跳过
  if [[ "$expanded" == "kubectl top" ]] || [[ "$expanded" == "kubectl top --namespace=kube-system" ]]; then
    return 0
  fi

  # ── 执行 ──
  local exit_code=0
  eval "$expanded" &>/dev/null || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "$name"
  else
    fail "$name (exit=$exit_code)"
    echo "       cmd: $expanded" >&2
  fi
}

# ── 主流程 ──────────────────────────────────────────────────────────────

trap cleanup EXIT

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  kubectl-aliases 集成测试                       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

create_resources

echo ""
echo "=== 生成别名 ==="
"$APP" -o "$ALIAS_FILE"
source "$ALIAS_FILE"

# 收集总条数
TOTAL=$(alias | grep -c "^k")
echo "   共 $TOTAL 个别名"

echo ""
echo "=== 逐条测试 ==="

# 通过 alias 命令获取所有 k 开头的别名
while IFS='=' read -r name _; do
  [[ "$name" == "k" ]] && continue
  test_alias "$name"
done < <(alias | grep "^k" | grep -v "^k=")

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  结果: $PASS 通过, $FAIL 失败"
echo "╚══════════════════════════════════════════════════╝"

if [ -n "$FAILED_ALIASES" ]; then
  echo "  失败列表:$FAILED_ALIASES"
fi

exit $FAIL
