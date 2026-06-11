# kubectl-aliases

用 Go 编写的 kubectl 别名生成器，覆盖 **9 种资源类型 × 3 个动词 × 格式/范围修饰符**，
自动处理兼容性约束，生成 700+ 条可直接使用的 shell 别名。

## 快速开始

```bash
# 方式一：下载预编译二进制
# 从 https://github.com/liangml/k8s-aliases/releases 下载对应平台版本
# macOS Intel:    kubectl-aliases-darwin-amd64.gz
# macOS M1/M2:   kubectl-aliases-darwin-arm64.gz
# Linux x86_64:  kubectl-aliases-linux-amd64.gz
# Linux ARM64:   kubectl-aliases-linux-arm64.gz
# Windows:       kubectl-aliases-windows-amd64.zip

# 生成别名文件
./kubectl-aliases -o ~/.kubectl_aliases

# 在 .bashrc / .zshrc 中添加
[ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases
```

```bash
# Fish shell
./kubectl-aliases -shell fish -o ~/.config/fish/conf.d/kubectl_aliases.fish
# 在 ~/.config/fish/config.fish 中添加
echo 'source ~/.config/fish/conf.d/kubectl_aliases.fish' >> ~/.config/fish/config.fish
```

```bash
# 方式二：自行编译（需 Go 1.26+）
make generate   # 编译并生成 .kubectl_aliases
```

## 命名规则

```
k[作用域][动词][资源][修饰符]
```

| 部分 | 可选值 | 含义 |
|------|--------|------|
| 作用域 | 空 / sys | 默认 / kube-system |
| 动词 | g / d / del | get / describe / delete |
| 特殊 | l / ex / pf / p | logs / exec / port-forward / proxy（无资源类型） |
| 资源 | po / dep / sts / svc / ing / cm / sec / no / ns | pods / deployment / statefulset / service / ingress / configmap / secret / nodes / namespaces |
| 格式 | oyaml / owide / ojson / sl / w | -o=yaml / -o=wide / -o=json / --show-labels / --watch |
| 范围 | all / n / l / f | --all-namespaces / --namespace / -l / --recursive -f |

---

## 完整使用指南

### 1. 基础 get

```sh
kgpo              = kubectl get pods
kgdep             = kubectl get deployment
kgsts             = kubectl get statefulset
kgsvc             = kubectl get service
kging             = kubectl get ingress
kgcm              = kubectl get configmap
kgsec             = kubectl get secret
kgno              = kubectl get nodes
kgns              = kubectl get namespaces
```

### 2. 基础 describe

```sh
kdpo  test-pod    = kubectl describe pods test-pod
kddep test-dep    = kubectl describe deployment test-dep
kdsvc test-svc    = kubectl describe service test-svc
kdcm  test-cm     = kubectl describe configmap test-cm
kdsec test-sec    = kubectl describe secret test-sec
kdno  orbstack    = kubectl describe nodes orbstack
kdns  kube-system = kubectl describe namespaces kube-system
```

### 3. 基础 delete

```sh
kdelpo  test-pod  = kubectl delete pods test-pod
kdeldep test-dep  = kubectl delete deployment test-dep
kdelsvc test-svc  = kubectl delete service test-svc
kdelcm  test-cm   = kubectl delete configmap test-cm
kdelsec test-sec  = kubectl delete secret test-sec
kdeling test-ing  = kubectl delete ingress test-ing
kdelns  test-ns   = kubectl delete namespaces test-ns
```

### 4. 输出格式（仅 get）

```sh
kgpooyaml         = kubectl get pods -o=yaml       # YAML 输出
kgpoowide         = kubectl get pods -o=wide        # 显示 IP/NODE 列
kgpoojson         = kubectl get pods -o=json        # JSON 输出
kgposl            = kubectl get pods --show-labels  # 显示标签列
kgpow             = kubectl get pods --watch        # 实时监听
```

### 5. 范围修饰符

```sh
kgpoall           = kubectl get pods --all-namespaces
kgpon             = kubectl get pods --namespace       # 需传参：kgpon kube-system
kgpol             = kubectl get pods -l                # 需传参：kgpol 'app=nginx'
kgpof             = kubectl get pods --recursive -f    # 从文件读取
```

> ⚠️ `n`（--namespace）和 `l`（-l）是快捷前缀，必须跟参数，否则报错。

### 6. 组合

```sh
kgpooyamlall      = kubectl get pods -o=yaml --all-namespaces
kgpoojsonall      = kubectl get pods -o=json --all-namespaces
kgpoallowidesl    = kubectl get pods --all-namespaces -o=wide --show-labels
kgposlowideall    = kubectl get pods --show-labels -o=wide --all-namespaces
```

### 7. 动词独立 + 格式（无资源）

```sh
kgoyaml           = kubectl get -o=yaml
kgowide           = kubectl get -o=wide
kgojson           = kubectl get -o=json
kgsl              = kubectl get --show-labels
kgw               = kubectl get --watch
kgall             = kubectl get --all-namespaces
kdall             = kubectl describe --all-namespaces
```

### 8. kube-system 作用域

```sh
ksysgpo           = kubectl --namespace=kube-system get pods
ksysgdep          = kubectl --namespace=kube-system get deployment
ksysgpooyaml      = kubectl --namespace=kube-system get pods -o=yaml
ksysdpo           = kubectl --namespace=kube-system describe pods
ksysdelpo         = kubectl --namespace=kube-system delete pods
```

### 9. logs / exec / port-forward

这些命令不接受资源类型参数，直接跟 pod 名：

```sh
kl  test-pod              = kubectl logs test-pod
klf test-pod              = kubectl logs -f test-pod
kltt test-pod             = kubectl logs --tail=50 -f test-pod
kex test-pod -- ls /      = kubectl exec -i -t test-pod -- ls /
kpf test-pod 8080         = kubectl port-forward test-pod 8080
kp                        = kubectl proxy
```

### 10. --namespace 参数版本

```sh
kgn  kube-system pods               = kubectl get --namespace kube-system pods
kdn  kube-system pods               = kubectl describe --namespace kube-system pods
kdeln kube-system pods              = kubectl delete --namespace kube-system pods
kexn kube-system test-pod -- ls /   = kubectl exec -i -t --namespace kube-system test-pod -- ls /
klfn kube-system test-pod           = kubectl logs -f --namespace kube-system test-pod
kpfn kube-system test-pod 8080      = kubectl port-forward --namespace kube-system test-pod 8080
```

### 11. --recursive -f 系列

```sh
kgf                   = kubectl get --recursive -f
kdf                   = kubectl describe --recursive -f
kdelf                 = kubectl delete --recursive -f
kgoyamlf              = kubectl get -o=yaml --recursive -f
kgowidef              = kubectl get -o=wide --recursive -f
kgojsonf              = kubectl get -o=json --recursive -f
```

### 12. 强制删除

```sh
kdelnow  pod test-pod           = kubectl delete --grace-period=0 --force pod test-pod
ksysdelnow pod test-pod         = kubectl delete --grace-period=0 --force --namespace=kube-system pod test-pod
kdelf                           = kubectl delete --recursive -f
```

### 13. kubectl run

```sh
krun test --image=nginx --rm -i -t -- sh      = 创建临时调试 pod（退出自动删除）
krunn default test --image=nginx --rm -i -t -- sh   = 指定命名空间
```

### 14. kubectl apply / kustomize

```sh
ka  ./manifests/         = kubectl apply --recursive -f ./manifests/
kak ./overlays/prod      = kubectl apply -k ./overlays/prod
kk  ./overlays/prod      = kubectl kustomize ./overlays/prod
ksysa ./manifests/       = kubectl apply --recursive -f --namespace=kube-system ./manifests/
```

### 15. kubectl edit

```sh
ked deploy test-dep                    = kubectl edit deployment test-dep
kedn kube-system cm coredns            = kubectl edit --namespace kube-system configmap coredns
```

### 16. kubectl rollout

```sh
kroll status deploy test-dep          = kubectl rollout status deployment test-dep
krollrestart deploy test-dep          = kubectl rollout restart deployment test-dep
krr deploy test-dep                   = kubectl rollout restart deployment test-dep（快捷版）
krollhistory deploy test-dep          = kubectl rollout history deployment test-dep
krollundo deploy test-dep             = kubectl rollout undo deployment test-dep
```

### 17. kubectl top

```sh
ktop nodes                = kubectl top nodes
ktop pods                 = kubectl top pods
ksystop pods              = kubectl top --namespace=kube-system pods
```

### 18. context / namespace 切换

```sh
kctx minikube             = kubectl config use-context minikube
kns kube-system           = kubectl config set-context --current --namespace kube-system
```

### 19. 节点管理

```sh
kdrain orbstack           = kubectl drain orbstack
kcordon orbstack          = kubectl cordon orbstack       # 设为不可调度
kuncordon orbstack        = kubectl uncordon orbstack     # 恢复调度
```

### 20. 标签 / 注解 / 文件复制

```sh
klabel po test-pod env=prod                    = kubectl label pods test-pod env=prod
kannotate po test-pod my-key='my value'        = kubectl annotate pods test-pod my-key='my value'
kcp test-pod:/etc/nginx ./                     = kubectl cp test-pod:/etc/nginx ./
```

---

## 构建

```bash
make build     # 编译当前平台
make release   # 交叉编译（dist/ 目录，5 个平台）
make generate  # 编译并生成 .kubectl_aliases + .kubectl_aliases.fish
make dist      # 构建全部产物（别名文件 + 交叉编译二进制）
make test      # 构建、生成、验证（smoke + version + go vet）
make clean     # 清理
```

## 下载产物

每个版本都包含以下可直接下载的产物（[Releases 页面](https://github.com/liangml/k8s-aliases/releases)）：

| 文件 | 说明 |
|------|------|
| `.kubectl_aliases` | bash / zsh 别名（691 条，可直接 source） |
| `.kubectl_aliases.fish` | fish 别名（691 条） |
| `kubectl-aliases-darwin-amd64.gz` | macOS Intel 二进制 |
| `kubectl-aliases-darwin-arm64.gz` | macOS Apple Silicon 二进制 |
| `kubectl-aliases-linux-amd64.gz` | Linux x86_64 二进制 |
| `kubectl-aliases-linux-arm64.gz` | Linux ARM64 二进制 |
| `kubectl-aliases-windows-amd64.zip` | Windows x86_64 二进制 |

> 💡 无需安装 Go 环境，下载对应平台的二进制即可直接使用。

## License

Apache 2.0
