#!/bin/bash
# 校验.sh —— skill 质量的守门人（只读，不改任何文件）
#
# 用法：
#   ./校验.sh          跑全部五项检查
#   ./校验.sh links    只查死链
#   ./校验.sh dup      只查重复段落
#
# 五项检查：
#   1. links     引用可达：文档里提到的 .md / assets 文件必须真实存在
#   2. contract  结构完整性：关键小节必须存在（越界处理、接收契约、失败上限）
#   3. version   版本一致：SKILL.md 的 version 与 README / 原理图里写的版本一致
#   4. size      体量预算：每个 SKILL.md ≤ 7000 字节（超出说明该下沉了）
#   5. dup       重复段落：两个文件间不许有 ≥3 行连续相同内容（单一事实源）
#   6. junk      卫生：不许 .DS_Store / 空目录
#
# 退出码：0 = 全过；1 = 有 fail（warning 不算 fail）

set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

exec python3 - "$ROOT" "${1:-all}" <<'PY'
import os, re, sys, collections

ROOT = sys.argv[1]
ONLY = sys.argv[2]
SKILLS_DIR = os.path.join(ROOT, "skills")
SIZE_BUDGET = 7000
SKILLS = ["my-dev-rules", "my-dev-workflow"]

GREEN, YELLOW, RED, DIM, BOLD, RESET = "\033[32m", "\033[33m", "\033[31m", "\033[2m", "\033[1m", "\033[0m"

fails, warns = [], []

def ok(msg):    print(f"  {GREEN}✓{RESET} {msg}")
def warn(msg):
    print(f"  {YELLOW}!{RESET} {msg}"); warns.append(msg)
def fail(msg):
    print(f"  {RED}✗{RESET} {msg}"); fails.append(msg)

def md_files():
    out = []
    for cur, dirs, files in os.walk(SKILLS_DIR):
        for f in files:
            if f.endswith(".md"):
                out.append(os.path.join(cur, f))
    return sorted(out)

ALL_MD = md_files()
BASENAMES = collections.defaultdict(list)
for p in ALL_MD:
    BASENAMES[os.path.basename(p)].append(p)

# ---------- 1. 引用可达 ----------
# 白名单：项目内路径 / 模板占位 / 用户级路径 / 举例用的日期名 / 项目根常见文件名
PROJECT_FILES = {"README.md", "AGENTS.md", "CLAUDE.md", "00-项目总览.md", "PRD.md", "契约.md"}

def is_exempt(name, ctx):
    if os.path.basename(name) in PROJECT_FILES:
        return True
    if "docs/" in ctx or ctx.startswith("docs"):
        return True
    if re.search(r"(YYYY|MM|DD|XXX|NNN|<|>|\*)", name):
        return True
    if "~" in ctx or "/Users/" in ctx or ".workbuddy/skills" in ctx:
        return True
    return False

def check_links():
    print(f"\n{BOLD}[1/6] 引用可达{RESET}")
    pat = re.compile(r"([\w\u4e00-\u9fa5./-]+\.md)\b")
    bad = 0
    for p in ALL_MD:
        rel = os.path.relpath(p, SKILLS_DIR)
        text = open(p, encoding="utf-8").read()
        for m in pat.finditer(text):
            name = m.group(1)
            ctx = text[max(0, m.start() - 30):m.end() + 5]
            if name.startswith("http") or is_exempt(name, ctx):
                continue
            base = os.path.basename(name)
            if base in BASENAMES:
                continue
            if os.path.exists(os.path.join(ROOT, name)):   # 根目录的 校验.sh / 自检任务.md
                continue
            # 允许相对路径（../../校验.sh 也会被 normpath 正确解析）
            abs_try = os.path.normpath(os.path.join(os.path.dirname(p), name))
            if os.path.exists(abs_try):
                continue
            fail(f"{rel}: 引用不存在的文件 `{name}`")
            bad += 1
    if bad == 0:
        ok(f"{len(ALL_MD)} 个文件的引用全部可达")

# ---------- 2. 版本一致 ----------
def version_of(skill):
    p = os.path.join(SKILLS_DIR, skill, "SKILL.md")
    m = re.search(r"^version:\s*\"?([\d.]+)\"?", open(p, encoding="utf-8").read(), re.M)
    return m.group(1) if m else None

# ---------- 2. 结构完整性 ----------
# 这些小节是"能力黑名单 / 任务接收契约 / 循环上限"的落点，缺了说明规则被改丢了
REQUIRED = {
    "my-dev-rules": [
        ("SKILL.md", ["边界与越界", "同级冲突", "规则优先级"]),
        ("references/技术-通用红线.md", ["验证闭环", "验证不了就说验证不了"]),
    ],
    "my-dev-workflow": [
        ("SKILL.md", ["边界与越界", "任务接收契约", "失败 2 次"]),
        ("references/sop/03-编码实现.md", ["失败上限"]),
        ("references/sop/04-审计复查.md", ["修复轮次上限"]),
    ],
}

def check_contract():
    print(f"\n{BOLD}[2/6] 结构完整性（关键小节必须存在）{RESET}")
    for skill, items in REQUIRED.items():
        for rel, keys in items:
            p = os.path.join(SKILLS_DIR, skill, rel)
            if not os.path.exists(p):
                fail(f"{skill}/{rel} 文件缺失"); continue
            text = open(p, encoding="utf-8").read()
            missing = [k for k in keys if k not in text]
            if missing:
                fail(f"{skill}/{rel} 缺小节：{'、'.join(missing)}")
            else:
                ok(f"{skill}/{rel} 关键小节齐全（{len(keys)} 项）")

def check_version():
    print(f"\n{BOLD}[3/6] 版本一致{RESET}")
    vers = {s: version_of(s) for s in SKILLS}
    for s, v in vers.items():
        if v: ok(f"{s} SKILL.md = v{v}")
        else: fail(f"{s} SKILL.md 缺 version 字段")

    docs = [os.path.join(ROOT, "README.md"), os.path.join(ROOT, "skill工作原理.md")]
    for d in docs:
        if not os.path.exists(d):
            warn(f"缺文档 {os.path.basename(d)}"); continue
        text = open(d, encoding="utf-8").read()
        for s, v in vers.items():
            if not v: continue
            short = s.replace("my-dev-", "")
            found = re.findall(rf"{short}\s*v(\d+\.\d+)", text, re.I)
            if not found:
                warn(f"{os.path.basename(d)} 未标注 {short} 版本号")
            else:
                stale = sorted({x for x in found if x != v})
                if stale:
                    fail(f"{os.path.basename(d)} 写的 {short} v{stale[0]}，SKILL.md 实为 v{v}")
                else:
                    ok(f"{os.path.basename(d)} 的 {short} 版本与 SKILL.md 一致（v{v}）")

# ---------- 3. 体量预算 ----------
def check_size():
    print(f"\n{BOLD}[4/6] 体量预算（SKILL.md ≤ {SIZE_BUDGET} 字节）{RESET}")
    for s in SKILLS:
        p = os.path.join(SKILLS_DIR, s, "SKILL.md")
        n = os.path.getsize(p)
        if n <= SIZE_BUDGET:
            ok(f"{s}/SKILL.md {n} 字节")
        else:
            fail(f"{s}/SKILL.md {n} 字节，超预算 {n - SIZE_BUDGET} 字节 —— 细节下沉到 references/")

# ---------- 4. 重复段落 ----------
def norm(line):
    return re.sub(r"\s+", " ", line.strip())

def check_dup():
    print(f"\n{BOLD}[5/6] 重复段落（跨文件 ≥3 行连续相同）{RESET}")
    WINDOW = 3
    seen = collections.defaultdict(set)
    for p in ALL_MD:
        lines = [norm(l) for l in open(p, encoding="utf-8").read().splitlines()]
        lines = [l for l in lines if l and not l.startswith("|---") and l != "|"]
        rel = os.path.relpath(p, SKILLS_DIR)
        for i in range(len(lines) - WINDOW + 1):
            block = tuple(lines[i:i + WINDOW])
            if sum(len(x) for x in block) < 60:   # 太短不算
                continue
            seen[block].add(rel)
    dups = {b: fs for b, fs in seen.items() if len(fs) > 1}
    if not dups:
        ok("没有跨文件重复的三行段落")
    else:
        shown = 0
        for block, files in list(dups.items())[:8]:
            fail(f"{' / '.join(sorted(files))} 有相同 {WINDOW} 行：`{block[0][:50]}…`")
            shown += 1
        if len(dups) > shown:
            warn(f"另有 {len(dups) - shown} 处重复未列出")

# ---------- 5. 卫生 ----------
def check_junk():
    print(f"\n{BOLD}[6/6] 卫生{RESET}")
    junk = []
    for cur, dirs, files in os.walk(ROOT):
        if "/.git" in cur or "/.workbuddy" in cur:
            dirs[:] = [d for d in dirs if d not in (".git", ".workbuddy")]
            continue
        for f in files:
            if f == ".DS_Store" or (f.startswith(".") and f not in (".gitignore",)):
                junk.append(os.path.relpath(os.path.join(cur, f), ROOT))
    if junk:
        for j in junk: warn(f"垃圾/点文件：{j}")
    else:
        ok("无 .DS_Store 等垃圾文件")
    # 空目录
    empties = []
    for cur, dirs, files in os.walk(SKILLS_DIR):
        if not dirs and not files:
            empties.append(os.path.relpath(cur, SKILLS_DIR))
    if empties:
        for e in empties: warn(f"空目录：{e}")
    else:
        ok("无空目录")

TASKS = {"links": check_links, "contract": check_contract, "version": check_version,
         "size": check_size, "dup": check_dup, "junk": check_junk}

if ONLY == "all":
    print(f"{BOLD}校验 {ROOT}{RESET}")
    for fn in TASKS.values():
        fn()
else:
    if ONLY not in TASKS:
        print(f"未知检查项：{ONLY}（可选：all / links / contract / version / size / dup / junk）")
        sys.exit(2)
    TASKS[ONLY]()

print()
if fails:
    print(f"{RED}{BOLD}结论：{len(fails)} 项 fail，{len(warns)} 项 warn{RESET}")
    sys.exit(1)
else:
    print(f"{GREEN}{BOLD}结论：全部通过{RESET}" + (f"（{len(warns)} 项 warn，建议看一眼）" if warns else ""))
    sys.exit(0)
PY
