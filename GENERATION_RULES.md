# kubectl-aliases 别名生成规则

> 代码在 `main.go`，规则由 `compatible()` 函数强制执行。
> 修改规则时请同步更新此文档和 `main.go` 头部注释。

---

## 命名模式

```
k[作用域][动词][资源][修饰符]
```

### 缩写表

| 位置 | 缩写 | 含义 | kubectl 参数 |
|------|------|------|-------------|
| 作用域 | `(空)` | 默认 namespace | — |
| 作用域 | `sys` | kube-system | `--namespace=kube-system` |
| 动词 | `g` | get | `get` |
| 动词 | `d` | describe | `describe` |
| 动词 | `del` | delete | `delete` |
| 资源 | `po` | pods | `pods` |
| 资源 | `dep` | deployment | `deployment` |
| 资源 | `sts` | statefulset | `statefulset` |
| 资源 | `svc` | service | `service` |
| 资源 | `ing` | ingress | `ingress` |
| 资源 | `cm` | configmap | `configmap` |
| 资源 | `sec` | secret | `secret` |
| 资源 | `no` | nodes | `nodes` |
| 资源 | `ns` | namespaces | `namespaces` |
| 修饰符 | `oyaml` | YAML 输出 | `-o=yaml` |
| 修饰符 | `owide` | 宽格式输出 | `-o=wide` |
| 修饰符 | `ojson` | JSON 输出 | `-o=json` |
| 修饰符 | `sl` | 显示标签 | `--show-labels` |
| 修饰符 | `w` | 监听变化 | `--watch` |
| 修饰符 | `all` | 所有 namespace | `--all-namespaces` |
| 修饰符 | `n` | 指定 namespace | `--namespace`（后接参数） |
| 修饰符 | `l` | 标签选择 | `-l`（后接参数） |
| 修饰符 | `f` | 从文件读取 | `--recursive -f` |

### 示例

| 别名 | 展开 |
|------|------|
| `kgpo` | `kubectl get pods` |
| `kgpooyamlall` | `kubectl get pods -o=yaml --all-namespaces` |
| `ksysgdep` | `kubectl --namespace=kube-system get deployment` |
| `kdelpo` | `kubectl delete pods` |
| `kdelnow` | `kubectl delete --grace-period=0 --force` |
| `kl` | `kubectl logs`（不接受资源类型参数） |

---

## 组合生成规则

### 6 层展开

```
Level 0:  base     [k]                      ─── 必选
Level 1:  scopes   ['' / sys]               ─── 可选 1
Level 2:  verbs    [g / d / del]            ─── 可选 1
Level 3:  resources [po/dep/sts/svc/ing/cm/sec/no/ns]  ─── 可选 1
Level 4:  mods     [oyaml/owide/ojson/sl/w] ─── 可选多个（排列）
Level 5:  ranges   [all / n / l / f]        ─── 可选多个（排列）
```

每层从前到后逐层展开，每步入 `compatible()` 检查合法性。

---

### 动词 × 资源兼容性

表格说明哪些资源支持哪些动词。

| 动词 | po | dep | sts | svc | ing | cm | sec | no | ns |
|------|----|-----|-----|-----|-----|----|-----|----|----|
| **get** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **describe** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **delete** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |

> `no`(nodes) 不支持 delete，因为 kubectl 不允许直接 delete nodes。
> `no`(nodes) 不支持 sys 作用域（nodes 是集群级资源，不属于任何 namespace）。

---

### 格式修饰符（mods）— 仅限 get

格式修饰符只能与 `get` 动词组合。

| 修饰符 | kubectl 参数 | 互斥（Exclude） |
|--------|-------------|----------------|
| `oyaml` | `-o=yaml` | owide, ojson, sl |
| `owide` | `-o=wide` | oyaml, ojson |
| `ojson` | `-o=json` | oyaml, owide, sl |
| `sl` | `--show-labels` | oyaml, ojson |
| `w` | `--watch` | oyaml, ojson, owide |

---

### 范围修饰符（ranges）

| 修饰符 | kubectl 参数 | 适用动词 | 互斥（Exclude） |
|--------|-------------|---------|----------------|
| `all` | `--all-namespaces` | g, d | del, f, no, ns, sys, n |
| `n` | `--namespace`（需参数） | g, d, del | — |
| `l` | `-l`（标签选择） | g, d, del | all |
| `f` | `--recursive -f`（文件） | g, d, del | **全部 9 种资源类型** |

#### 关于 `f`（`--recursive -f`）的重要说明

`-f` 表示从文件或目录读取资源定义。当使用 `-f` 时，**不能再指定资源类型**（如 `pods`、`secret`），因为 kubectl 会报错。

例如以下别名是**非法**的：
```
kgpof     = kubectl get pods --recursive -f        ← 错误
ksysdsecf = kubectl --namespace=kube-system describe secret --recursive -f  ← 错误
```

正确的用法是不带资源类型：
```
kgf       = kubectl get --recursive -f             ← 正确
ksysdf    = kubectl --namespace=kube-system describe --recursive -f  ← 正确
```

> **代码保障**：`f` 组件已通过 `Exclude` 字段排除了全部 9 种资源类型，组合生成器不会生成非法组合。

---

### 集群级资源特殊规则

| 规则 | 说明 |
|------|------|
| `no`/`ns` + `all` | nodes 和 namespaces 是集群级资源，永远不带 `--all-namespaces` |
| `no` + `sys` | nodes 不归属 namespace，不与 `--namespace=kube-system` 组合 |
| `sys` + `n` | sys 已锁定 kube-system，再加 `--namespace` 语义矛盾 |

---

## 特殊别名（不走组合生成）

以下 kubectl 命令**不接受资源类型参数**，或者参数签名特殊，全部手工定义在 `specialAliases` 中：

| 类别 | 别名 | 展开 |
|------|------|------|
| run | `krun` | `kubectl run --rm --restart=Never --image-pull-policy=IfNotPresent -i -t` |
| apply | `ka` | `kubectl apply --recursive -f` |
| kustomize | `kak` | `kubectl apply -k` |
| 强制删除 | `kdelnow` | `kubectl delete --grace-period=0 --force` |
| get -f | `kgf` | `kubectl get --recursive -f` |
| describe -f | `kdf` | `kubectl describe --recursive -f` |
| logs | `kl` | `kubectl logs` |
| exec | `kex` | `kubectl exec -i -t` |
| port-forward | `kpf` | `kubectl port-forward` |
| proxy | `kp` | `kubectl proxy` |
| sys 范围 | `ksysg` | `kubectl get --namespace=kube-system` |
| 动词本体 | `kg` / `kd` / `kdel` | get / describe / delete |
| 格式组合 | `kgoyaml` / `kgowide` / ... | get + -o=yaml / -o=wide / ... |
| 格式+all | `kgoyamlall` / `kgalloyaml` / ... | get + -o=yaml + --all-namespaces |
| sys 格式 | `ksysgoyaml` / `ksysgowide` / ... | get --namespace=kube-system + 格式 |
| --namespace 版本 | `kgn` / `kdn` / `kdeln` / `kexn` / `klfn` / `kpfn` | 动词 + --namespace |
| edit | `ked` / `kedn` | `kubectl edit` |
| rollout | `kroll` / `krr` / ... | `kubectl rollout restart/status` |
| top | `ktop` / `ksystop` | `kubectl top` |
| context/ns | `kctx` / `kns` | config use-context / set-context |
| 节点管理 | `kdrain` / `kcordon` / `kuncordon` | drain / cordon / uncordon |

---

## 生成流程

```
specialAliases 先注册（优先级高）
        │
        ▼
generateCombos()
  ├── 逐层展开 6 个 level
  ├── 每步 compatible() 检查 Require + Exclude
  └── 生成器遇到已注册别名自动跳过（builder.seen 去重）
        │
        ▼
  formatter.Format() 输出（BashZshFormatter / FishFormatter）
```

---

## delete --all 与 delete --all-namespaces 的区别

| 命令 | 含义 |
|------|------|
| `kubectl delete --all` | 删除当前 namespace 下所有同类资源 |
| `kubectl delete --all-namespaces` | 非法（all 与 del 在项目中互斥） |

`kdelall` = `kubectl delete --all`（不是 `--all-namespaces`）。

---

## 已废弃/过时的生成产物

当前 `main.go` 生成 **635 条**合法别名（0 条非法 resource+f 组合）。
仓库里提交的 `.kubectl_aliases`（691 条）包含大量过时的非法组合，需要重新生成。
