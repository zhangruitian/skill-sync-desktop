# README.md — 通用 Skill 同步指南

## 是什么

`sync-skills.sh` 是一个一键脚本，将 skill hub 目录下的所有 skill 同步到各智能体平台。默认管理脚本所在目录，也可通过 `--hub` 参数或 `HUB_ROOT` 环境变量指向其他目录。

目前支持的智能体目标：

| 标签 | 路径 | 对应应用 |
|------|------|----------|
| `claude` | `~/.claude/skills/` | Claude Code（Anthropic） |
| `codex` | `~/.codex/skills/` | Codex CLI（OpenAI） |
| `agents` | `~/.agents/skills/` | Codex / OpenAI Agents SDK（用户级 skills） |

如需添加或删除目标，编辑脚本顶部 `AGENTS_CONFIG` 即可。

## 快速上手

```bash
# 查看状态——最常用的命令
./sync-skills.sh status

# 管理另一个 hub 目录
./sync-skills.sh --hub ~/skill-wip status
HUB_ROOT=~/skill-wip ./sync-skills.sh sync -y

# 对比差异
./sync-skills.sh diff

# 同步所有 skill 到所有智能体（软链，跳过确认）
./sync-skills.sh sync -y

# 查看所有命令
./sync-skills.sh help
```

## 目录约定

- 把每个 skill 作为独立子目录放在 `skill-hub/` 下
- 每个 skill 目录根层级必须包含 `SKILL.md`
- 自动排除 `docs/`、备份残留（`*.backup-*`）、隐藏文件、`node_modules/`

```
skill-hub/
├── sync-skills.sh          # 同步脚本
├── README.md                 # 本文档
├── docs/                   # 会被自动跳过
├── my-skill/               # 一个 skill
│   ├── SKILL.md
│   ├── references/
│   │   └── ...
│   └── agents/             # 智能体配置（同步时跳过，不安装到智能体端）
│       └── my-skill.yaml
└── another-skill/          # 另一个 skill
    └── SKILL.md
```

## 全部命令

### `help` — 查看帮助

```
./sync-skills.sh help
```

### `status` — 查看同步状态

```
./sync-skills.sh status
```

输出分两部分：

1. **Hub skills**：以 hub 中的 skill 为基准，展示在每个智能体的安装状态

   | 状态 | 含义 |
   |------|------|
   | `link` | 软链到 hub 且目标正确，自动跟随变更 |
   | `link(stale)` | 软链存在但指向了非 hub 位置（见下方 Stale links detail 区块） |
   | `copy` | 复制安装，内容与 hub 一致 |
   | `outdated` | 复制安装但内容与 hub 有差异（不包括 .git、docs、LICENSE 等非运行时文件） |
   | `-` | 未安装 |

2. **Stale links detail**：仅在有 `link(stale)` 条目时出现，逐条展示当前实际指向路径 vs 预期指向路径

3. **External skills**：智能体端存在但 hub 中没有的 skill（通过其他途径安装），仅供查看，sync 不会影响它们

底部还会有备份残留提示（如有）。

### `diff` — 对比差异

```bash
# 对比所有 skill
./sync-skills.sh diff

# 对比指定 skill
./sync-skills.sh diff my-skill another-skill
```

以 hub 为基准逐文件对比，自动忽略 `.git`、`.DS_Store`、`LICENSE`、`README.md`、`CHANGELOG.md`、`docs/`、`agents/`、`.github/`、`.vscode/`、`.idea/` 等开发期文件。完整的忽略列表见脚本顶部的 `SYNC_IGNORE_GLOBS` 配置。

### `sync` — 同步到智能体

```bash
# 同步所有 skill（软链方式，默认）
./sync-skills.sh sync

# 跳过确认
./sync-skills.sh sync -y

# 复制方式（适合分发场景）
./sync-skills.sh sync --copy

# 只同步指定 skill
./sync-skills.sh sync my-skill another-skill
```

执行前打印变更摘要（新增/覆盖/跳过），确认后执行。覆盖前自动备份为 `*.backup-<timestamp>`，可用 `clean-backups` 清理。

**重要安全规则**：
- sync **只新增/覆盖，绝不删除**智能体端已有的 skill
- 如果 hub 删了某个 skill，智能体端的对应 skill 会保留
- 与 hub 无关的外部 skill 完全不受影响
- 需要删除智能体端的 skill 时使用 `unlink` 显式操作

### `unlink` — 移除智能体端 skill

```bash
./sync-skills.sh unlink old-skill
```

需要**两次确认**（不接受 `-y` 跳过），仅删除智能体端的 skill，不会删 hub 源文件。

### `clean-backups` — 清理备份残留

```bash
./sync-skills.sh clean-backups
```

扫描各智能体目录下的 `*.backup-*` 残留，确认后删除。

### `watch` — 开发模式

```bash
# 软链模式（默认）
./sync-skills.sh watch

# 复制模式
./sync-skills.sh watch --copy
```

需要安装 `fswatch`（macOS: `brew install fswatch`）。启动时先全量同步一次，之后持续监听 hub 目录变更，自动同步到所有智能体。带 2 秒防抖，避免频繁写入。

## 配置

编辑 `sync-skills.sh` 顶部**配置区**（第 16–56 行）：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `AGENTS_CONFIG` | 智能体目标（`标签\|路径`） | claude、codex、agents |
| `EXCLUDE_PATTERNS` | hub 中不作为 skill 的目录（正则） | docs、scripts、backup-*、隐藏文件 |
| `SYNC_IGNORE_GLOBS` | 同步时从 skill 内部跳过的文件（glob） | .git、LICENSE、docs/、agents/ 等 |
| `DEFAULT_INSTALL_MODE` | 默认安装方式 | `link` |
| `AUTO_BACKUP` | 覆盖前是否自动备份 | `true` |

### 添加新智能体目标

编辑 `AGENTS_CONFIG`，一行一个：

```bash
read -r -d '' AGENTS_CONFIG <<'EOF' || true
claude|HOME_PLACEHOLDER/.claude/skills
codex|HOME_PLACEHOLDER/.codex/skills
agents|HOME_PLACEHOLDER/.agents/skills
cursor|HOME_PLACEHOLDER/.cursor/skills    # 新增 Cursor
EOF
```

## 典型工作流

### 开发新 skill

```bash
# 1. 在 hub 中创建目录和 SKILL.md
mkdir my-skill
echo '---
name: my-skill
description: description
---
# My Skill' > my-skill/SKILL.md

# 2. 开启 watch 或手动 sync
./sync-skills.sh watch &
# 或
./sync-skills.sh sync my-skill -y

# 3. 修改 hub 中的文件，智能体端自动跟随（软链模式）
# 4. 在智能体中测试
# 5. 完善后提交到 git
```

### 分发 stable 版本

```bash
# 复制安装，保证智能体拿到独立副本
./sync-skills.sh sync --copy -y
```

### 废弃 skill

```bash
# 1. 从智能体移除（二次确认）
./sync-skills.sh unlink old-skill

# 2. 手动删除 hub 源（或移动到 archives/）
rm -rf skill-hub/old-skill
```

## 注意事项

1. **软链 vs 复制**：软链改 hub 智能体自动跟随，适合开发；复制是独立副本，适合稳定分发，但改 hub 后要重新 sync
2. **备份残留**：每次 sync 覆盖前会生成 `*.backup-<timestamp>` 备份，时间久了会累积，定期运行 `clean-backups`
3. **sed 版本差异**：macOS 默认的 bash 3.x 不支持关联数组（`declare -A`），脚本已做了兼容处理
4. **同步后需重启**：修改 skill 后通常需要重启智能体应用或开新会话，才能让智能体重新扫描 skills 目录
5. **外部 skill 安全**：智能体端那些不是从 hub 安装的 skill，sync 完全不会动它们，可以放心
6. **hub 是唯一 truth source**：所有修改都以 hub 为准，不要在智能体端直接改 skill（软链除外——它本来就是同一个文件）

## 常见问题

### Q: sync 会不会删除智能体端已有的外部 skill？
不会。sync 只管理 hub 中存在的 skill。

### Q: 软链和复制怎么选？
- **软链（默认）**：修改 hub 自动生效，适合开发迭代
- **复制**：独立副本，适合稳定分发，需手动 re-sync

### Q: 同步后需要重启智能体吗？
通常需要。智能体在启动时扫描 skills 目录，运行时不一定能检测到新文件。

### Q: outdated 是什么情况？
复制安装后 hub 端有更新。常见场景：
- hub 新增了 reference 文件或 eval 用例
- hub 修改了 SKILL.md

运行 `diff` 看具体差异，然后 `sync` 覆盖即可。

### Q: 如何把外部 skill 纳入 hub 管理？
直接把对应的 skill 目录复制到 hub 目录下，然后 `sync` 即可。下次 `status` 它就会从 External 移到 Hub skills。

### Q: 如何管理多个 hub？
通过 `--hub` 参数或 `HUB_ROOT` 环境变量指向不同目录：
```bash
./sync-skills.sh --hub ~/skill-wip status
HUB_ROOT=~/skill-wip ./sync-skills.sh sync -y
```

### Q: 能不能不对比某些文件？
编辑 `SYNC_IGNORE_GLOBS`，添加需要跳过的文件名或目录名（glob 模式），如需要跳过 `package.json`，加一行 `"package.json"`。
