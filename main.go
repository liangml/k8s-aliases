// kubectl-aliases — 智能 kubectl 别名生成器
//
// 用法:
//   go run main.go > .kubectl_aliases        # 生成 bash/zsh 别名
//   go run main.go -shell fish > .kubectl_aliases.fish
//
// 设计模式:
//   - Builder: 分步构建别名组合
//   - Strategy: 不同 shell 输出策略
//   - Composite: 别名各部分（作用域+动词+资源+修饰符）组合

package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

// version 在编译时通过 -ldflags 注入，用于 --version 输出
var version = "dev"

// ─── 数据定义 ───────────────────────────────────────────────────────────────

// Component 表示别名的一个组成部分
type Component struct {
	Alias   string   // 缩写
	Command string   // 对应的 kubectl 参数
	Require []string // 需要的其他组件（空=不限制）
	Exclude []string // 互斥的组件
}

// ─── 核心数据 ───────────────────────────────────────────────────────────────

var base = Component{Alias: "k", Command: "kubectl"}

var scopes = []Component{
	{Alias: "", Command: ""},
	{Alias: "sys", Command: "--namespace=kube-system"},
}

var verbs = []Component{
	{Alias: "g", Command: "get"},
	{Alias: "d", Command: "describe"},
	{Alias: "del", Command: "delete"},
}

var resources = []Component{
	{Alias: "po", Command: "pods", Require: []string{"g", "d", "del"}},
	{Alias: "dep", Command: "deployment", Require: []string{"g", "d", "del"}},
	{Alias: "sts", Command: "statefulset", Require: []string{"g", "d", "del"}},
	{Alias: "svc", Command: "service", Require: []string{"g", "d", "del"}},
	{Alias: "ing", Command: "ingress", Require: []string{"g", "d", "del"}},
	{Alias: "cm", Command: "configmap", Require: []string{"g", "d", "del"}},
	{Alias: "sec", Command: "secret", Require: []string{"g", "d", "del"}},
	{Alias: "no", Command: "nodes", Require: []string{"g", "d"}, Exclude: []string{"sys"}},
	{Alias: "ns", Command: "namespaces", Require: []string{"g", "d", "del"}, Exclude: []string{"sys"}},
}

var mods = []Component{
	{Alias: "oyaml", Command: "-o=yaml", Require: []string{"g"}, Exclude: []string{"owide", "ojson", "sl"}},
	{Alias: "owide", Command: "-o=wide", Require: []string{"g"}, Exclude: []string{"oyaml", "ojson"}},
	{Alias: "ojson", Command: "-o=json", Require: []string{"g"}, Exclude: []string{"owide", "oyaml", "sl"}},
	{Alias: "sl", Command: "--show-labels", Require: []string{"g"}, Exclude: []string{"oyaml", "ojson"}},
	{Alias: "w", Command: "--watch", Require: []string{"g"}, Exclude: []string{"oyaml", "ojson", "owide"}},
}

var ranges = []Component{
	{Alias: "all", Command: "--all-namespaces", Require: []string{"g", "d"}, Exclude: []string{"del", "f", "no", "ns", "sys"}},
	{Alias: "n", Command: "--namespace", Require: []string{"g", "d", "del"}},
	{Alias: "l", Command: "-l", Require: []string{"g", "d", "del"}, Exclude: []string{"all"}},
	{Alias: "f", Command: "--recursive -f", Require: []string{"g", "d", "del"}},
}

// ─── 特殊别名（不适用组合生成） ─────────────────────────────────────────────

type SpecialAlias struct {
	Alias   string
	Command string
}

var specialAliases = []SpecialAlias{
	// kubectl run
	{Alias: "krun", Command: "kubectl run --rm --restart=Never --image-pull-policy=IfNotPresent -i -t"},
	{Alias: "ksysrun", Command: "kubectl run --rm --restart=Never --image-pull-policy=IfNotPresent -i -t --namespace=kube-system"},
	{Alias: "krunn", Command: "kubectl run --rm --restart=Never --image-pull-policy=IfNotPresent -i -t --namespace"},

	// kubectl apply
	{Alias: "ka", Command: "kubectl apply --recursive -f"},
	{Alias: "ksysa", Command: "kubectl apply --recursive -f --namespace=kube-system"},
	{Alias: "kak", Command: "kubectl apply -k"},
	{Alias: "kk", Command: "kubectl kustomize"},

	// kubectl delete
	{Alias: "kdelnow", Command: "kubectl delete --grace-period=0 --force"},
	{Alias: "ksysdelnow", Command: "kubectl delete --grace-period=0 --force --namespace=kube-system"},
	{Alias: "kdelf", Command: "kubectl delete --recursive -f"},
	{Alias: "kdelall", Command: "kubectl delete --all"},
	{Alias: "ksysdelall", Command: "kubectl delete --all --namespace=kube-system"},

	// kubectl get/describe --recursive -f
	{Alias: "kgf", Command: "kubectl get --recursive -f"},
	{Alias: "kdf", Command: "kubectl describe --recursive -f"},
	{Alias: "kgoyamlf", Command: "kubectl get -o=yaml --recursive -f"},
	{Alias: "kgowidef", Command: "kubectl get -o=wide --recursive -f"},
	{Alias: "kgojsonf", Command: "kubectl get -o=json --recursive -f"},
	{Alias: "kgslf", Command: "kubectl get --show-labels --recursive -f"},
	{Alias: "kgwf", Command: "kubectl get --watch --recursive -f"},
	{Alias: "kgowideslf", Command: "kubectl get -o=wide --show-labels --recursive -f"},
	{Alias: "kgslowidef", Command: "kubectl get --show-labels -o=wide --recursive -f"},
	{Alias: "kgslwf", Command: "kubectl get --show-labels --watch --recursive -f"},
	{Alias: "kgwslf", Command: "kubectl get --watch --show-labels --recursive -f"},

	// 动词独立别名（logs/exec/pf 不接受资源类型参数）
	{Alias: "kl", Command: "kubectl logs"},
	{Alias: "klf", Command: "kubectl logs -f"},
	{Alias: "kltt", Command: "kubectl logs --tail=50 -f"},
	{Alias: "kpf", Command: "kubectl port-forward"},
	{Alias: "kex", Command: "kubectl exec -i -t"},
	{Alias: "kp", Command: "kubectl proxy"},

	// sys 范围动词
	{Alias: "ksysg", Command: "kubectl get --namespace=kube-system"},
	{Alias: "ksysd", Command: "kubectl describe --namespace=kube-system"},
	{Alias: "ksysdel", Command: "kubectl delete --namespace=kube-system"},

	// 动词 + 格式 + all 组合
	{Alias: "kg", Command: "kubectl get"},
	{Alias: "kd", Command: "kubectl describe"},
	{Alias: "kdel", Command: "kubectl delete"},
	{Alias: "kgoyaml", Command: "kubectl get -o=yaml"},
	{Alias: "kgowide", Command: "kubectl get -o=wide"},
	{Alias: "kgojson", Command: "kubectl get -o=json"},
	{Alias: "kgsl", Command: "kubectl get --show-labels"},
	{Alias: "kgw", Command: "kubectl get --watch"},
	{Alias: "kgoyamlall", Command: "kubectl get -o=yaml --all-namespaces"},
	{Alias: "kgowideall", Command: "kubectl get -o=wide --all-namespaces"},
	{Alias: "kgojsonall", Command: "kubectl get -o=json --all-namespaces"},
	{Alias: "kgall", Command: "kubectl get --all-namespaces"},
	{Alias: "kdall", Command: "kubectl describe --all-namespaces"},
	{Alias: "kgalloyaml", Command: "kubectl get --all-namespaces -o=yaml"},
	{Alias: "kgallowide", Command: "kubectl get --all-namespaces -o=wide"},
	{Alias: "kgallojson", Command: "kubectl get --all-namespaces -o=json"},
	{Alias: "kgallsl", Command: "kubectl get --all-namespaces --show-labels"},
	{Alias: "kgallw", Command: "kubectl get --all-namespaces --watch"},
	{Alias: "kgslall", Command: "kubectl get --show-labels --all-namespaces"},
	{Alias: "kgwall", Command: "kubectl get --watch --all-namespaces"},

	// sys 格式组合
	{Alias: "ksysgoyaml", Command: "kubectl get --namespace=kube-system -o=yaml"},
	{Alias: "ksysgowide", Command: "kubectl get --namespace=kube-system -o=wide"},
	{Alias: "ksysgojson", Command: "kubectl get --namespace=kube-system -o=json"},
	{Alias: "ksysgsl", Command: "kubectl get --namespace=kube-system --show-labels"},
	{Alias: "ksysgw", Command: "kubectl get --namespace=kube-system --watch"},

	// ns 参数版本
	{Alias: "kgn", Command: "kubectl get --namespace"},
	{Alias: "kdn", Command: "kubectl describe --namespace"},
	{Alias: "kdeln", Command: "kubectl delete --namespace"},
	{Alias: "kgoyamln", Command: "kubectl get -o=yaml --namespace"},
	{Alias: "kgowiden", Command: "kubectl get -o=wide --namespace"},
	{Alias: "kgojsonn", Command: "kubectl get -o=json --namespace"},
	{Alias: "kgsln", Command: "kubectl get --show-labels --namespace"},
	{Alias: "kgwn", Command: "kubectl get --watch --namespace"},
	{Alias: "kexn", Command: "kubectl exec -i -t --namespace"},
	{Alias: "klfn", Command: "kubectl logs -f --namespace"},
	{Alias: "kpfn", Command: "kubectl port-forward --namespace"},

	// kubectl edit
	{Alias: "ked", Command: "kubectl edit"},
	{Alias: "kedn", Command: "kubectl edit --namespace"},

	// kubectl rollout
	{Alias: "kroll", Command: "kubectl rollout"},
	{Alias: "krollrestart", Command: "kubectl rollout restart"},
	{Alias: "krollstatus", Command: "kubectl rollout status"},
	{Alias: "krollhistory", Command: "kubectl rollout history"},
	{Alias: "krollundo", Command: "kubectl rollout undo"},
	{Alias: "krr", Command: "kubectl rollout restart"},

	// kubectl top
	{Alias: "ktop", Command: "kubectl top"},
	{Alias: "ksystop", Command: "kubectl top --namespace=kube-system"},

	// context / namespace 切换
	{Alias: "kctx", Command: "kubectl config use-context"},
	{Alias: "kns", Command: "kubectl config set-context --current --namespace"},

	// 节点管理
	{Alias: "kdrain", Command: "kubectl drain"},
	{Alias: "kcordon", Command: "kubectl cordon"},
	{Alias: "kuncordon", Command: "kubectl uncordon"},

	// 标签/注解
	{Alias: "klabel", Command: "kubectl label"},
	{Alias: "kannotate", Command: "kubectl annotate"},

	// 文件复制
	{Alias: "kcp", Command: "kubectl cp"},
}

// ─── 生成器 ─────────────────────────────────────────────────────────────────

type AliasEntry struct {
	Alias   string
	Command string
}

// AliasBuilder 组合生成别名（Builder Pattern）
type AliasBuilder struct {
	entries []AliasEntry
	seen    map[string]bool
}

func NewAliasBuilder() *AliasBuilder {
	return &AliasBuilder{seen: make(map[string]bool)}
}

func (b *AliasBuilder) Add(alias, command string) {
	if b.seen[alias] {
		return // 去重
	}
	b.seen[alias] = true
	b.entries = append(b.entries, AliasEntry{Alias: alias, Command: command})
}

func (b *AliasBuilder) Entries() []AliasEntry {
	return b.entries
}

// compatible 检查组件组合是否有效
func compatible(comps []Component) bool {
	present := make(map[string]bool)
	for _, c := range comps {
		present[c.Alias] = true
	}

	for _, c := range comps {
		// 检查 require：所需的组件必须在场
		if len(c.Require) > 0 {
			has := false
			for _, r := range c.Require {
				if present[r] {
					has = true
					break
				}
			}
			if !has {
				return false
			}
		}

		// 检查 exclude：互斥的组件不能在场
		for _, x := range c.Exclude {
			if present[x] {
				return false
			}
		}
	}
	return true
}

// generateCombos 生成所有有效组合（Composite Pattern）
func generateCombos() [][]Component {
	type level struct {
		items    []Component
		optional bool // true = 可以不选，false = 必须选一个
		multiple bool // true = 可选多个（排列），false = 只能选一个
	}

	levels := []level{
		{items: []Component{base}, optional: false, multiple: false},
		{items: scopes, optional: true, multiple: false},
		{items: verbs, optional: true, multiple: false},
		{items: resources, optional: true, multiple: false},
		{items: mods, optional: true, multiple: true},
		{items: ranges, optional: true, multiple: true},
	}

	var result [][]Component
	result = append(result, []Component{})

	for _, lv := range levels {
		var next [][]Component

		// 生成当前层的候选组合
		candidates := [][]Component{}
		if lv.optional {
			candidates = append(candidates, []Component{}) // 不选
		}
		for _, item := range lv.items {
			candidates = append(candidates, []Component{item})
		}
		// 如果允许多选，生成排列
		if lv.multiple && len(lv.items) > 1 {
			for i := 2; i <= len(lv.items); i++ {
				perms := permutations(lv.items, i)
				candidates = append(candidates, perms...)
			}
		}

		for _, combo := range result {
			for _, cand := range candidates {
				merged := append([]Component{}, combo...)
				merged = append(merged, cand...)
				if compatible(merged) {
					next = append(next, merged)
				}
			}
		}
		result = next
	}

	return result
}

func permutations(items []Component, n int) [][]Component {
	if n == 0 {
		return [][]Component{{}}
	}
	if n > len(items) {
		return nil
	}

	var result [][]Component
	for i, item := range items {
		rest := []Component{}
		rest = append(rest, items[:i]...)
		rest = append(rest, items[i+1:]...)
		for _, sub := range permutations(rest, n-1) {
			merged := append([]Component{item}, sub...)
			if compatible(merged) {
				result = append(result, merged)
			}
		}
	}
	return result
}

// ─── 输出策略（Strategy Pattern） ──────────────────────────────────────────

type ShellFormatter interface {
	Format(alias, command string) string
	Comment(text string) string
}

type BashZshFormatter struct{}

func (BashZshFormatter) Format(alias, command string) string {
	return fmt.Sprintf("alias %s='%s'", alias, command)
}

func (BashZshFormatter) Comment(text string) string {
	return "# " + text
}

type FishFormatter struct{}

func (FishFormatter) Format(alias, command string) string {
	return fmt.Sprintf("abbr --add %s \"%s\"", alias, command)
}

func (FishFormatter) Comment(text string) string {
	return "# " + text
}

func formatterFor(shell string) ShellFormatter {
	switch shell {
	case "fish":
		return FishFormatter{}
	default:
		return BashZshFormatter{}
	}
}

// ─── 主逻辑 ────────────────────────────────────────────────────────────────

func generate(builder *AliasBuilder, shell string) {
	combos := generateCombos()

	for _, combo := range combos {
		if len(combo) == 0 {
			continue
		}
		alias := ""
		parts := []string{}
		for _, c := range combo {
			alias += c.Alias
			parts = append(parts, c.Command)
		}
		// 跳过基础 k 本身（alias k='kubectl' 单独处理）
		if alias == "k" {
			continue
		}
		builder.Add(alias, strings.Join(parts, " "))
	}

	// 手动添加特殊组合
	addSpecialCombos(builder)
}

// addSpecialCombos 添加特殊格式组合（allowidesl, slowideall）
// 仅对 get 动词生效，因为 owide/sl 需要 g(get) 在场
func addSpecialCombos(b *AliasBuilder) {
	for _, scope := range scopes {
		for _, verb := range verbs {
			if verb.Alias != "g" {
				continue
			}
			for _, res := range resources {
				comps := []Component{base, scope, verb, res}
				if !compatible(comps) {
					continue
				}

				// no（nodes）和 ns（namespaces）是集群级资源，与 --all-namespaces 不兼容
				if res.Alias == "no" || res.Alias == "ns" {
					continue
				}

				// sys（kube-system）与 --all-namespaces 互斥
				if scope.Alias == "sys" {
					continue
				}

				// 构建基础命令（过滤空 scope）
				parts := []string{base.Command}
				if scope.Command != "" {
					parts = append(parts, scope.Command)
				}
				parts = append(parts, verb.Command, res.Command)

				prefix := "k" + scope.Alias + verb.Alias + res.Alias
				baseCmd := strings.Join(parts, " ")

				b.Add(prefix+"allowidesl",
					baseCmd+" --all-namespaces -o=wide --show-labels")
				b.Add(prefix+"slowideall",
					baseCmd+" --show-labels -o=wide --all-namespaces")
			}
		}
	}
}

// ─── 分组规则（按优先级排序，精确匹配优先于前缀匹配）────────────────────

type groupMatcher struct {
	name    string
	matchFn func(alias string) bool
}

// aliasGroup 返回别名所属的分组名称
func aliasGroup(name string) string {
	// 按优先级排序，越靠前越优先匹配
	matchers := []groupMatcher{
		{name: "文件复制", matchFn: func(a string) bool { return strings.HasPrefix(a, "kcp") }},
		{name: "context / namespace 切换", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "kctx") || strings.HasPrefix(a, "kns")
		}},
		{name: "节点管理", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "kdrain") || strings.HasPrefix(a, "kcordon") || strings.HasPrefix(a, "kuncordon")
		}},
		{name: "标签 / 注解", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "klabel") || strings.HasPrefix(a, "kannotate")
		}},
		{name: "kubectl edit", matchFn: func(a string) bool { return strings.HasPrefix(a, "ked") }},
		{name: "kubectl rollout", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "kroll") || a == "krr"
		}},
		{name: "kubectl top", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "ktop") || strings.HasPrefix(a, "ksystop")
		}},
		{name: "logs / exec / port-forward（无资源类型）", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "kl") || strings.HasPrefix(a, "kpf") || strings.HasPrefix(a, "kex") || a == "kp"
		}},
		{name: "kubectl run", matchFn: func(a string) bool {
			return a == "krun" || a == "ksysrun" || a == "krunn"
		}},
		{name: "kubectl apply", matchFn: func(a string) bool {
			return a == "ka" || a == "ksysa"
		}},
		{name: "kubectl kustomize", matchFn: func(a string) bool { return a == "kak" || a == "kk" }},
		// 动词独立 + 格式（无资源）必须在 kg/kd 之前匹配，因为 kg/kd 是更宽的前缀
		{name: "动词独立 + 格式（无资源）", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "kgoyaml") || strings.HasPrefix(a, "kgowide") ||
				strings.HasPrefix(a, "kgojson") || strings.HasPrefix(a, "kgsl") ||
				strings.HasPrefix(a, "kgw") || strings.HasPrefix(a, "kgall") ||
				strings.HasPrefix(a, "kdall") || strings.HasPrefix(a, "kgslall") ||
				strings.HasPrefix(a, "kgwall")
		}},
		{name: "kubectl get/describe -f", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "kgf") || strings.HasPrefix(a, "kdf")
		}},
		{name: "kubectl delete（强制/递归）", matchFn: func(a string) bool {
			return a == "kdelnow" || a == "ksysdelnow" || a == "kdelf" || a == "kdelall" || a == "ksysdelall"
		}},
		// --namespace 参数版本必须在 kd/kdel 之前匹配
		{name: "--namespace 参数版本", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "kgn") || strings.HasPrefix(a, "kdn") ||
				strings.HasPrefix(a, "kdeln") || strings.HasPrefix(a, "kexn") ||
				strings.HasPrefix(a, "klfn") || strings.HasPrefix(a, "kpfn") ||
				strings.HasPrefix(a, "kgoyamln") || strings.HasPrefix(a, "kgowiden") ||
				strings.HasPrefix(a, "kgojsonn") || strings.HasPrefix(a, "kgsln") ||
				strings.HasPrefix(a, "kgwn")
		}},
		{name: "kube-system 格式组合", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "ksysgoyaml") || strings.HasPrefix(a, "ksysgowide") ||
				strings.HasPrefix(a, "ksysgojson") || strings.HasPrefix(a, "ksysgsl") ||
				strings.HasPrefix(a, "ksysgw")
		}},
		{name: "kube-system → get", matchFn: func(a string) bool { return strings.HasPrefix(a, "ksysg") }},
		{name: "kube-system → describe/delete", matchFn: func(a string) bool {
			return strings.HasPrefix(a, "ksysd") || strings.HasPrefix(a, "ksysdel")
		}},
		{name: "基础 delete", matchFn: func(a string) bool { return strings.HasPrefix(a, "kdel") }},
		{name: "基础 describe", matchFn: func(a string) bool { return strings.HasPrefix(a, "kd") }},
		{name: "基础 get", matchFn: func(a string) bool { return strings.HasPrefix(a, "kg") }},
	}

	for _, m := range matchers {
		if m.matchFn(name) {
			return m.name
		}
	}
	return "其他"
}

// generateHeader 生成文件头注释
func generateHeader(shell, headShell string) string {
	return fmt.Sprintf(`# shellcheck shell=%s
# =============================================================================
# kubectl-aliases — 由 Go 生成器自动生成，请勿手动编辑
# 源文件: main.go
# =============================================================================
# 自动生成 691 条 kubectl 别名，覆盖 9 种资源 × 3 个动词 × 格式/范围修饰符
# 通过组合生成器动态构造，无需手工维护。%s 都能用。
#
# 命名规则: k[作用域][动词][资源][修饰符]
#   作用域  '' / sys（kube-system）
#   动词    g / d / del / l / ex / pf
#   修饰符  oyaml / owide / ojson / sl / w / all / n / l / f
#   示例    kgpooyamlall = kubectl get pods -o=yaml --all-namespaces
#           kdelnow      = kubectl delete --grace-period=0 --force
#           kl           = kubectl logs（不带资源类型，直接写 pod 名）
# =============================================================================`, shell, headShell)
}

// writeGuard 写入 shell guard clause（防重复 source）和基础 k='kubectl'
func writeGuard(w *os.File, shell string) {
	if shell == "fish" {
		fmt.Fprintln(w, `if set -q _K8S_ALIAS_LOADED; exit 0; end
set -g _K8S_ALIAS_LOADED 1`)
		fmt.Fprintln(w)
		fmt.Fprintln(w, `abbr --add k "kubectl"`)
	} else {
		fmt.Fprintln(w, `# 防止重复 source（POSIX 兼容：bash/zsh/ash/dash）
[ -n "$_K8S_ALIAS_LOADED" ] && return
export _K8S_ALIAS_LOADED=1`)
		fmt.Fprintln(w)
		fmt.Fprintln(w, `alias k='kubectl'`)
	}
}

// writeAliases 按分组输出所有别名
func writeAliases(w *os.File, f ShellFormatter, entries []AliasEntry) {
	// 分组
	byGroup := make(map[string][]AliasEntry)
	var groupOrder []string
	addToGroup := func(title string, entry AliasEntry) {
		if _, ok := byGroup[title]; !ok {
			groupOrder = append(groupOrder, title)
		}
		byGroup[title] = append(byGroup[title], entry)
	}

	for _, entry := range entries {
		if entry.Alias == "k" {
			continue
		}
		addToGroup(aliasGroup(entry.Alias), entry)
	}

	// 输出
	fmt.Fprintln(w)
	fmt.Fprintln(w, f.Comment("="+strings.Repeat("=", 77)))
	fmt.Fprintln(w, f.Comment("kubectl aliases — 自动生成（按类别分组）"))
	fmt.Fprintln(w, f.Comment("="+strings.Repeat("=", 77)))
	fmt.Fprintln(w)

	for _, title := range groupOrder {
		entries := byGroup[title]
		if len(entries) == 0 {
			continue
		}
		fmt.Fprintln(w)
		fmt.Fprintln(w, f.Comment("── "+title+" ──"))
		for _, entry := range entries {
			fmt.Fprintln(w, f.Format(entry.Alias, entry.Command))
		}
	}
}

// ─── 主入口 ─────────────────────────────────────────────────────────────────

func main() {
	shell := flag.String("shell", "bash", "target shell: bash, zsh, fish")
	output := flag.String("o", "", "output file (default: stdout)")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("kubectl-aliases %s\n", version)
		return
	}

	var w *os.File
	if *output != "" {
		var err error
		w, err = os.Create(*output)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error creating %s: %v\n", *output, err)
			os.Exit(1)
		}
		defer w.Close()
	} else {
		w = os.Stdout
	}

	headShell := "bash"
	if *shell == "fish" {
		headShell = "fish"
	} else if *shell == "zsh" {
		headShell = "zsh"
	}

	// 输出 header
	fmt.Fprintln(w, generateHeader(*shell, headShell))
	fmt.Fprintln(w)

	// 输出 guard clause
	writeGuard(w, *shell)
	fmt.Fprintln(w)

	// 生成别名
	// 先添加特殊别名（高优先级），生成器遇到同名会自动跳过
	f := formatterFor(*shell)
	builder := NewAliasBuilder()
	for _, sa := range specialAliases {
		builder.Add(sa.Alias, sa.Command)
	}
	generate(builder, *shell)

	// 按分组输出
	writeAliases(w, f, builder.Entries())
}
