#!/usr/bin/env bash
# =============================================================================
# sync-skills.sh — 通用 Skill 同步脚本
# 将 skill-hub 中的 skill 一键同步到各智能体平台
#
# 用法: ./sync-skills.sh <command> [options]
#
# 智能体目标（可在脚本顶部配置区修改）:
#   - Claude Code:   ~/.claude/skills/
#   - Codex:         ~/.codex/skills/
#   - Agents:        ~/.agents/skills/
# =============================================================================

set -euo pipefail

# ============================== 配置区 ======================================

# 智能体 skill 目录列表
# 格式: "label|path"，每行一个
read -r -d '' AGENTS_CONFIG <<'EOF' || true
claude|HOME_PLACEHOLDER/.claude/skills
codex|HOME_PLACEHOLDER/.codex/skills
agents|HOME_PLACEHOLDER/.agents/skills
EOF

# 需要从 skill 目录中排除的目录名（正则，按文件名匹配）
EXCLUDE_PATTERNS=(
  "^docs$"
  "^scripts$"
  "^backup-"
  "\.backup-"    # 如 obsidian-kb-manager.backup-20260709-001137
  "^\..*"       # 隐藏文件/目录
  "^node_modules$"
)

# 同步时从 skill 内部跳过的文件/目录（glob 模式，供 diff -x / find -name 使用）
# 这些是开发过程产生的，智能体运行时不需要
SYNC_IGNORE_GLOBS=(
  ".git"
  ".gitattributes"
  ".DS_Store"
  "LICENSE"
  "README.md"
  "CHANGELOG.md"
  "docs"
  "agents"
  ".github"
  ".vscode"
  ".idea"
)

# 默认安装方式: link | copy
DEFAULT_INSTALL_MODE="link"

# 覆盖前是否自动备份: true | false
AUTO_BACKUP="true"

# ============================== 工具函数 ====================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_ROOT="${HUB_ROOT:-$SCRIPT_DIR}"

# 替换配置中的 HOME_PLACEHOLDER 为实际 home
AGENTS_CONFIG="${AGENTS_CONFIG//HOME_PLACEHOLDER/$HOME}"

# 终端颜色（真正的 ANSI 转义字符，echo / cat 通用）
BOLD="$(printf '\033[1m')"
DIM="$(printf '\033[2m')"
RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
CYAN="$(printf '\033[36m')"
NC="$(printf '\033[0m')"

# 输出辅助
header()   { printf "\n${BOLD}${BLUE}═══ %s ═══${NC}\n" "$*"; }
success()  { echo "  ${GREEN}✓${NC} $*"; }
warn()     { echo "  ${YELLOW}⚠${NC} $*"; }
error()    { echo "  ${RED}✗${NC} $*"; }
info()     { echo "  ${DIM}→${NC} $*"; }

# 构建 diff 排除参数（供 diff -rq 和 copy 清理使用）
build_diff_excludes() {
  local args=()
  for pattern in "${SYNC_IGNORE_GLOBS[@]}"; do
    args+=("-x" "$pattern")
  done
  echo "${args[@]}"
}

# 对比两个目录是否内容相同（忽略开发文件）
dirs_synced() {
  local dir1="$1"
  local dir2="$2"
  local excludes
  excludes="$(build_diff_excludes)"
  # shellcheck disable=SC2086
  diff -rq $excludes "$dir1" "$dir2" 2>/dev/null > /dev/null
}

# 清理目录中的忽略文件/目录（sync 的 copy 模式使用）
clean_sync_ignores() {
  local target="$1"
  for pattern in "${SYNC_IGNORE_GLOBS[@]}"; do
    find "$target" -maxdepth 3 -name "$pattern" -exec rm -rf {} + 2>/dev/null || true
  done
}

# 输出两个目录的差异（忽略开发文件）
dirs_diff_output() {
  local dir1="$1"
  local dir2="$2"
  local excludes
  excludes="$(build_diff_excludes)"
  # shellcheck disable=SC2086
  diff -rq $excludes "$dir1" "$dir2" 2>/dev/null
}

die() {
  echo "${RED}${BOLD}Error:${NC} $*" >&2
  exit 1
}

# 获取 agent label 列表（空格分隔）
get_agent_labels() {
  local labels=()
  while IFS='|' read -r label path; do
    if [[ -n "$label" ]]; then
      labels+=("$label")
    fi
  done <<< "$AGENTS_CONFIG"
  echo "${labels[*]}"
}

# 获取 agent path（通过 label）
get_agent_path() {
  local search_label="$1"
  while IFS='|' read -r label path; do
    if [[ "$label" == "$search_label" ]]; then
      echo "$path"
      return
    fi
  done <<< "$AGENTS_CONFIG"
}

# 获取实际存在的 agent label 列表
get_active_agent_labels() {
  local labels=()
  while IFS='|' read -r label path; do
    if [[ -n "$label" ]] && [[ -d "$path" ]]; then
      labels+=("$label")
    fi
  done <<< "$AGENTS_CONFIG"
  echo "${labels[*]}"
}

# 获取 hub 中所有 skill 名称（包含 SKILL.md 的子目录名）
get_hub_skills() {
  local skills=()
  for dir in "$HUB_ROOT"/*/; do
    local name
    name="$(basename "$dir")"

    # 检查排除项
    local excluded=false
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
      if [[ "$name" =~ $pattern ]]; then
        excluded=true
        break
      fi
    done
    if $excluded; then continue; fi

    # 必须有 SKILL.md
    if [[ -f "${dir}SKILL.md" ]]; then
      skills+=("$name")
    fi
  done
  echo "${skills[*]}"
}

# 获取指定智能体目录下的所有 skill 名称
get_agent_skills() {
  local agent_path="$1"
  local skills=()
  if [[ ! -d "$agent_path" ]]; then
    echo ""
    return
  fi
  for dir in "$agent_path"/*/; do
    local name
    name="$(basename "$dir")"
    # 排除 backup 残留和隐藏文件
    if [[ "$name" =~ ^backup- ]] || [[ "$name" =~ \.backup- ]] || [[ "$name" =~ ^\. ]]; then
      continue
    fi
    skills+=("$name")
  done
  echo "${skills[*]}"
}

# 判断 skill 在智能体端的安装状态
# 返回值:
#   link        软链到 hub 且目标正确
#   link-stale  软链但目标不正确（指向其他位置）
#   copy-synced 复制安装且内容与 hub 一致
#   outdated    复制安装但内容与 hub 不一致
#   not-found   未安装
#   error       无法判断
get_skill_state() {
  local skill_name="$1"
  local agent_path="$2"
  local target="${agent_path}/${skill_name}"
  local hub_source="${HUB_ROOT}/${skill_name}"

  # 软链：无论目标是否存在，先判断是否为软链
  if [[ -L "$target" ]]; then
    local link_target
    link_target="$(readlink "$target")"
    # 解析为绝对路径
    local resolved_link
    resolved_link="$(cd "$(dirname "$target")" 2>/dev/null && cd "$link_target" 2>/dev/null && pwd 2>/dev/null || echo "")"
    local resolved_hub
    resolved_hub="$(cd "$hub_source" 2>/dev/null && pwd 2>/dev/null || echo "")"

    if [[ "$resolved_link" == "$resolved_hub" ]]; then
      echo "link"
    else
      echo "link-stale"
    fi
    return
  fi

  # 完全不存在（也不是软链）
  if [[ ! -e "$target" ]]; then
    echo "not-found"
    return
  fi

  # 真实目录
  if [[ -d "$target" ]]; then
    # 快速对比 SKILL.md
    if [[ -f "${target}/SKILL.md" ]] && [[ -f "${hub_source}/SKILL.md" ]]; then
      if diff -q "${target}/SKILL.md" "${hub_source}/SKILL.md" > /dev/null 2>&1; then
        # 进一步对比整个目录
        if dirs_synced "$target" "$hub_source"; then
          echo "copy-synced"
        else
          echo "outdated"
        fi
      else
        echo "outdated"
      fi
    else
      echo "outdated"
    fi
    return
  fi

  echo "error"
}

# 获取 skill 状态的纯文本标签（供制表使用）
get_state_label() {
  local state="$1"
  case "$state" in
    "link")        echo "link" ;;
    "link-stale")  echo "link(stale)" ;;
    "copy-synced") echo "copy" ;;
    "outdated")    echo "outdated" ;;
    "not-found")   echo "-" ;;
    *)             echo "?" ;;
  esac
}

# 获取 skill 状态的带颜色显示
get_state_display() {
  local state="$1"
  case "$state" in
    "link")        echo "${GREEN}link${NC}" ;;
    "link-stale")  echo "${YELLOW}link(stale)${NC}" ;;
    "copy-synced") echo "${GREEN}copy${NC}" ;;
    "outdated")    echo "${RED}outdated${NC}" ;;
    "not-found")   echo "${DIM}-${NC}" ;;
    *)             echo "${RED}?${NC}" ;;
  esac
}

# 表格分隔线
table_sep() {
  local cols="$1"
  for _ in $(seq 1 "$cols"); do
    printf "─"
  done
}

# ============================== 命令：status =================================

cmd_status() {
  local hub_skills_list
  hub_skills_list="$(get_hub_skills)"
  local -a hub_skills
  read -ra hub_skills <<< "$hub_skills_list"

  local agents_list
  agents_list="$(get_active_agent_labels)"
  local -a agents
  read -ra agents <<< "$agents_list"

  local col_skill=24
  local col_agent=16

  # ─── Hub skills 表格 ───
  header "Hub skills"
  if [[ -z "$hub_skills_list" ]]; then
    warn "hub 中没有检测到任何 skill"
  else
    # 表头
    printf "  %-*s" "$col_skill" "Skill"
    for agent in "${agents[@]}"; do
      printf "%-*s" "$col_agent" "$agent"
    done
    echo ""
    printf "  %-*s" "$col_skill" "$(table_sep $col_skill)"
    for agent in "${agents[@]}"; do
      printf "%-*s" "$col_agent" "$(table_sep $col_agent)"
    done
    echo ""

    # 收集 stale 条目，供后续详情区块展示
    local stale_entries=""

    # 表行
    for skill in "${hub_skills[@]}"; do
      [[ -z "$skill" ]] && continue
      printf "  %-*s" "$col_skill" "$skill"
      for agent in "${agents[@]}"; do
        local state
        state="$(get_skill_state "$skill" "$(get_agent_path "$agent")")"
        printf "%-*s" "$col_agent" "$(get_state_label "$state")"
        # 记录 stale 条目供后续详情
        if [[ "$state" == "link-stale" ]]; then
          local agent_path
          agent_path="$(get_agent_path "$agent")"
          local target="${agent_path}/${skill}"
          local current_target
          current_target="$(readlink "$target")"
          local hub_source="${HUB_ROOT}/${skill}"
          stale_entries="${stale_entries}${skill}|${agent}|${current_target}|${hub_source}"$'\n'
        fi
      done
      echo ""
    done
  fi

  # ─── Stale links 详情 ───
  if [[ -n "$stale_entries" ]]; then
    echo ""
    header "Stale links detail"
    printf "  ${BOLD}%-24s %-12s   %s${NC}\n" "Skill" "Agent" "Current → Expected"
    printf "  ${DIM}%-24s %-12s   %s${NC}\n" "$(table_sep 24)" "$(table_sep 12)" "$(table_sep 60)"
    while IFS='|' read -r skill agent current expected; do
      [[ -z "$skill" ]] && continue
      # 将 ~ 展开以便阅读
      local current_short="${current/$HOME/~}"
      local expected_short="${expected/$HOME/~}"
      printf "  %-24s ${CYAN}%-12s${NC}   ${YELLOW}%s${NC} ${DIM}→${NC} ${GREEN}%s${NC}\n" \
        "$skill" "$agent" "$current_short" "$expected_short"
    done <<< "$stale_entries"
    echo ""
    info "运行 ${BOLD}./sync-skills.sh sync -y${NC} 即可修正所有软链指向"
  fi

  # ─── External skills 表格 ───
  echo ""

  # 收集所有不在 hub 中的外部 skill
  local all_external=""
  for agent in "${agents[@]}"; do
    local agent_path
    agent_path="$(get_agent_path "$agent")"
    local agent_skills
    agent_skills="$(get_agent_skills "$agent_path")"
    for skill in $agent_skills; do
      local in_hub=false
      for hskill in "${hub_skills[@]}"; do
        if [[ "$skill" == "$hskill" ]]; then
          in_hub=true
          break
        fi
      done
      if ! $in_hub; then
        # 去重
        local already=false
        for e in $all_external; do
          [[ "$e" == "$skill" ]] && already=true
        done
        if ! $already; then
          all_external="$all_external $skill"
        fi
      fi
    done
  done
  # trim leading space
  all_external="${all_external# }"

  if [[ -n "$all_external" ]]; then
    header "External skills（仅在智能体端存在，hub 中没有）"
    printf "  %-*s" "$col_skill" "Skill"
    for agent in "${agents[@]}"; do
      printf "%-*s" "$col_agent" "$agent"
    done
    echo ""
    printf "  %-*s" "$col_skill" "$(table_sep $col_skill)"
    for agent in "${agents[@]}"; do
      printf "%-*s" "$col_agent" "$(table_sep $col_agent)"
    done
    echo ""

    for skill in $all_external; do
      [[ -z "$skill" ]] && continue
      printf "  %-*s" "$col_skill" "$skill"
      for agent in "${agents[@]}"; do
        local target
        target="$(get_agent_path "$agent")/${skill}"
        local label="-"
        if [[ -L "$target" ]]; then
          label="link"
        elif [[ -d "$target" ]]; then
          label="copy"
        fi
        printf "%-*s" "$col_agent" "$label"
      done
      echo ""
    done
    echo ""
    info "这些 skill 不在 hub 管理中，sync 不会影响它们。"
    info "如需管理，将其复制到 ${HUB_ROOT} 后再 sync。"
  fi

  # ─── 备份残留 ───
  echo ""
  local backup_count=0
  for agent in "${agents[@]}"; do
    local agent_path
    agent_path="$(get_agent_path "$agent")"
    local count
    count=$(find "$agent_path" -maxdepth 1 -name "*.backup-*" -print 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      if [[ $backup_count -eq 0 ]]; then
        warn "发现备份残留:"
      fi
      echo "    ${DIM}${agent}: ${count} 个 backup-* 目录${NC}"
      backup_count=$((backup_count + count))
    fi
  done
  if [[ $backup_count -gt 0 ]]; then
    echo ""
    info "运行 ${BOLD}./sync-skills.sh clean-backups${NC} 清理"
  fi
}

# ============================== 命令：diff ===================================

cmd_diff() {
  local skills_to_diff="$*"

  local hub_skills_list
  hub_skills_list="$(get_hub_skills)"
  local -a hub_skills
  read -ra hub_skills <<< "$hub_skills_list"

  local agents_list
  agents_list="$(get_active_agent_labels)"
  local -a agents
  read -ra agents <<< "$agents_list"

  # 如果未指定 skill，对比所有
  if [[ -z "$skills_to_diff" ]]; then
    skills_to_diff="$hub_skills_list"
  fi

  for skill in $skills_to_diff; do
    local hub_source="${HUB_ROOT}/${skill}"
    if [[ ! -d "$hub_source" ]]; then
      error "skill '${skill}' 在 hub 中不存在"
      continue
    fi

    for agent in "${agents[@]}"; do
      local target
      target="$(get_agent_path "$agent")/${skill}"
      if [[ ! -e "$target" ]]; then
        echo "${DIM}  ${skill} @ ${agent}: 未安装${NC}"
        continue
      fi

      local state
      state="$(get_skill_state "$skill" "$(get_agent_path "$agent")")"

      case "$state" in
        "link")
          success "${skill} @ ${agent}: 软链到 hub，无差异"
          ;;
        "link-stale")
          local link_target
          link_target="$(readlink "$target")"
          warn "${skill} @ ${agent}: 软链指向 ${link_target}，与 hub 不一致"
          ;;
        "copy-synced")
          success "${skill} @ ${agent}: 内容一致"
          ;;
        "outdated")
          warn "${skill} @ ${agent}: 内容有差异 (hub → agent)"
          if command -v diff &>/dev/null; then
            dirs_diff_output "$hub_source" "$target" \
              | head -20 | while IFS= read -r line; do
              echo "    ${DIM}${line}${NC}"
            done
          fi
          ;;

          "*")
          error "${skill} @ ${agent}: 状态异常"
          ;;
      esac
    done
  done
}

# 执行单个 skill 到单个 agent 的同步
sync_skill_to_agent() {
  local skill_name="$1"
  local agent_label="$2"
  local agent_path="$3"
  local mode="$4"

  local source="${HUB_ROOT}/${skill_name}"
  local target="${agent_path}/${skill_name}"
  local existing_state
  existing_state="$(get_skill_state "$skill_name" "$agent_path")"

  # 已是干净的软链，跳过
  if [[ "$existing_state" == "link" ]] && [[ "$mode" == "link" ]]; then
    success "${skill_name} → ${agent_label}: 已是最新软链，跳过"
    return 0
  fi

  # 已是干净的复制，跳过
  if [[ "$existing_state" == "copy-synced" ]] && [[ "$mode" == "copy" ]]; then
    success "${skill_name} → ${agent_label}: 内容已一致，跳过"
    return 0
  fi

  # 覆盖前备份（-e 对 broken symlink 返回 false，所以用 -e || -L）
  if { [[ -e "$target" ]] || [[ -L "$target" ]]; } && $AUTO_BACKUP; then
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local backup_path="${agent_path}/${skill_name}.backup-${timestamp}"
    info "备份: ${target} → ${backup_path}"
    mv "$target" "$backup_path"
  fi

  # 清理旧文件
  if [[ -e "$target" ]] || [[ -L "$target" ]]; then
    rm -rf "$target"
  fi

  # 安装
  mkdir -p "$agent_path"

  if [[ "$mode" == "link" ]]; then
    ln -sfn "$source" "$target"
    success "${skill_name} → ${agent_label}: 软链安装完成"
  else
    cp -R "$source" "$target"
    # 清理开发文件（.git、docs、LICENSE 等）
    clean_sync_ignores "$target"
    success "${skill_name} → ${agent_label}: 复制安装完成"
  fi
}

cmd_sync() {
  local install_mode="$DEFAULT_INSTALL_MODE"
  local auto_yes=false
  local skills_to_sync=""

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --copy) install_mode="copy"; shift ;;
      --link) install_mode="link"; shift ;;
      -y|--yes) auto_yes=true; shift ;;
      *) skills_to_sync="$skills_to_sync $1"; shift ;;
    esac
  done

  # trim
  skills_to_sync="${skills_to_sync# }"

  # 默认同步所有
  if [[ -z "$skills_to_sync" ]]; then
    skills_to_sync="$(get_hub_skills)"
  fi

  if [[ -z "$skills_to_sync" ]]; then
    warn "hub 中没有可同步的 skill"
    return 0
  fi

  local agents_list
  agents_list="$(get_active_agent_labels)"
  local -a agents
  read -ra agents <<< "$agents_list"

  if [[ ${#agents[@]} -eq 0 ]]; then
    die "没有可用的智能体目录，请检查配置"
  fi

  # ─── 打印变更摘要 ───
  header "同步预览"
  echo "  安装方式: ${BOLD}${install_mode}${NC}"
  echo "  Skills:   ${BOLD}${skills_to_sync}${NC}"
  echo "  目标:     ${BOLD}${agents_list}${NC}"
  echo ""

  local has_changes=false
  for skill in $skills_to_sync; do
    [[ -z "$skill" ]] && continue
    local source="${HUB_ROOT}/${skill}"
    if [[ ! -d "$source" ]]; then
      error "skill '${skill}' 在 hub 中不存在，跳过"
      continue
    fi

    for agent in "${agents[@]}"; do
      local state
      state="$(get_skill_state "$skill" "$(get_agent_path "$agent")")"
      local action=""

      case "$state" in
        "link")
          if [[ "$install_mode" == "copy" ]]; then
            action="软链 → 复制"
          else
            continue
          fi
          ;;
        "copy-synced")
          if [[ "$install_mode" == "link" ]]; then
            action="复制 → 软链"
          else
            continue
          fi
          ;;
        "not-found") action="${GREEN}新增${NC}" ;;
        "outdated")  action="${YELLOW}覆盖${NC}" ;;
        "link-stale") action="${YELLOW}修正软链${NC}" ;;
        *)           action="${RED}修复${NC}" ;;
      esac

      if [[ -n "$action" ]]; then
        has_changes=true
        echo "  $(get_state_label "$state") ${skill} @ ${agent} ${DIM}→${NC} $action"
      fi
    done
  done

  if ! $has_changes; then
    success "所有 skill 已是最新状态，无需同步"
    return 0
  fi

  # ─── 确认 ───
  if ! $auto_yes; then
    echo ""
    echo -ne "  确认执行同步？[y/N] "
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      info "已取消"
      return 0
    fi
  fi

  # ─── 执行 ───
  header "执行同步"
  for skill in $skills_to_sync; do
    [[ -z "$skill" ]] && continue
    for agent in "${agents[@]}"; do
      sync_skill_to_agent "$skill" "$agent" "$(get_agent_path "$agent")" "$install_mode"
    done
  done

  echo ""
  success "同步完成。重启智能体或开启新会话生效。"
}

# ============================== 命令：unlink =================================

cmd_unlink() {
  local skills_to_unlink="$*"
  local agents_list
  agents_list="$(get_active_agent_labels)"
  local -a agents
  read -ra agents <<< "$agents_list"

  if [[ -z "$skills_to_unlink" ]]; then
    die "请指定要移除的 skill 名称。用法: ./sync-skills.sh unlink <skill1> [skill2...]"
  fi

  # 验证所有 skill 名称
  for skill in $skills_to_unlink; do
    [[ -z "$skill" ]] && continue
    local found=false
    for agent in "${agents[@]}"; do
      if [[ -e "$(get_agent_path "$agent")/${skill}" ]]; then
        found=true
        break
      fi
    done
    if ! $found; then
      warn "'${skill}' 在所有智能体端都不存在，跳过"
    fi
  done

  header "移除预览"
  for skill in $skills_to_unlink; do
    [[ -z "$skill" ]] && continue
    for agent in "${agents[@]}"; do
      local target
      target="$(get_agent_path "$agent")/${skill}"
      if [[ -e "$target" ]]; then
        local typ="目录"
        [[ -L "$target" ]] && typ="软链"
        echo "  ${RED}移除${NC} ${skill} @ ${agent} (${typ}: ${target})"
      fi
    done
  done

  echo ""
  echo -ne "  ${RED}${BOLD}确认移除以上 skill？此操作不可撤销 [y/N]${NC} "
  read -r confirm1
  if [[ ! "$confirm1" =~ ^[Yy]$ ]]; then
    info "已取消"
    return 0
  fi

  echo -ne "  ${RED}${BOLD}再次确认：[y/N]${NC} "
  read -r confirm2
  if [[ ! "$confirm2" =~ ^[Yy]$ ]]; then
    info "已取消"
    return 0
  fi

  header "执行移除"
  for skill in $skills_to_unlink; do
    [[ -z "$skill" ]] && continue
    for agent in "${agents[@]}"; do
      local target
      target="$(get_agent_path "$agent")/${skill}"
      if [[ -e "$target" ]]; then
        rm -rf "$target"
        success "${skill} @ ${agent}: 已移除"
      fi
    done
  done
  echo ""
  info "注意: hub 中的源文件 ${BOLD}未被删除${NC}。如有需要请手动清理 ${HUB_ROOT}"
}

# ============================== 命令：clean-backups ==========================

cmd_clean_backups() {
  local agents_list
  agents_list="$(get_active_agent_labels)"
  local -a agents
  read -ra agents <<< "$agents_list"

  header "备份残留扫描"
  local total=0
  for agent in "${agents[@]}"; do
    local agent_path
    agent_path="$(get_agent_path "$agent")"
    if [[ ! -d "$agent_path" ]]; then continue; fi
    while IFS= read -r -d '' dir; do
      echo "  ${DIM}${agent}: $(basename "$dir")${NC}"
      total=$((total + 1))
    done < <(find "$agent_path" -maxdepth 1 -name "*.backup-*" -print0 2>/dev/null)
  done

  if [[ $total -eq 0 ]]; then
    success "没有备份残留"
    return 0
  fi

  echo ""
  echo -ne "  确认删除以上 ${total} 个备份目录？[y/N] "
  read -r answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    info "已取消"
    return 0
  fi

  for agent in "${agents[@]}"; do
    local agent_path
    agent_path="$(get_agent_path "$agent")"
    if [[ ! -d "$agent_path" ]]; then continue; fi
    find "$agent_path" -maxdepth 1 -name "*.backup-*" -exec rm -rf {} + 2>/dev/null
  done
  success "已清理 ${total} 个备份目录"
}

# ============================== 命令：watch ==================================

cmd_watch() {
  if ! command -v fswatch &>/dev/null; then
    die "需要安装 fswatch。macOS: brew install fswatch"
  fi

  local install_mode="${1:-$DEFAULT_INSTALL_MODE}"
  case "$install_mode" in
    --link|link)  install_mode="link" ;;
    --copy|copy)  install_mode="copy" ;;
    *)            install_mode="$DEFAULT_INSTALL_MODE" ;;
  esac

  header "watch 模式启动（${install_mode}）"
  info "监听目录: ${HUB_ROOT}"
  info "按 Ctrl+C 停止"

  # 首次全量同步
  cmd_sync --yes "--${install_mode}" 2>/dev/null || true

  echo ""
  info "持续监听变更中..."
  fswatch -0 -r "$HUB_ROOT" \
    --exclude='\.git/' \
    --exclude='\.DS_Store' \
    --exclude='node_modules/' \
    --exclude='backup-' \
    2>/dev/null | while IFS= read -r -d '' changed_file; do

    # 确定受影响的 skill
    local rel_path="${changed_file#$HUB_ROOT/}"
    local skill_name="${rel_path%%/*}"

    # 验证是有效的 skill
    local source="${HUB_ROOT}/${skill_name}"
    if [[ ! -d "$source" ]] || [[ ! -f "${source}/SKILL.md" ]]; then
      continue
    fi

    # 防抖：同一 skill 在 2 秒内只处理一次
    local now
    now="$(date +%s)"
    local last_file="/tmp/sync-skills-watch-${skill_name}.ts"
    local last_ts=0
    if [[ -f "$last_file" ]]; then
      last_ts="$(cat "$last_file" 2>/dev/null || echo 0)"
    fi
    if [[ $(( now - last_ts )) -lt 2 ]]; then
      continue
    fi
    echo "$now" > "$last_file"

    # 同步
    local agents_list
    agents_list="$(get_active_agent_labels)"
    local -a agents
    read -ra agents <<< "$agents_list"
    for agent in "${agents[@]}"; do
      sync_skill_to_agent "$skill_name" "$agent" "$(get_agent_path "$agent")" "$install_mode"
    done
    echo "  ${DIM}[$(date +%H:%M:%S)]${NC} ${skill_name} 已同步"
  done
}

# ============================== 帮助 =========================================

cmd_help() {
  cat <<HELP
${BOLD}sync-skills.sh${NC} — 通用 Skill 同步脚本

将指定目录中的 skill 同步到各智能体平台。
默认 hub: ${SCRIPT_DIR}
可通过 --hub <路径> 或环境变量 HUB_ROOT 指定其他 hub。

${BOLD}用法:${NC}
  ./sync-skills.sh [--hub <路径>] <command> [options]

${BOLD}命令:${NC}
  ${GREEN}status${NC}              查看所有 skill 在各智能体的同步状态
  ${GREEN}sync [skill...]${NC}     同步 skill 到各智能体（默认全部）
                      选项:
                        --link      软链安装（默认，适合开发）
                        --copy      复制安装（适合分发）
                        -y, --yes   跳过确认直接执行
  ${GREEN}diff [skill...]${NC}     对比 hub 与智能体端的 skill 差异
  ${GREEN}unlink <skill...>${NC}   从智能体端移除指定 skill（需二次确认）
  ${GREEN}clean-backups${NC}       清理智能体目录下的 *.backup-* 残留
  ${GREEN}watch [--link|--copy]${NC}  监听 hub 变更自动同步（需要 fswatch）
  ${GREEN}help${NC}                显示此帮助

${BOLD}示例:${NC}
  ./sync-skills.sh --hub ~/other-hub status   # 管理另一个 hub
  HUB_ROOT=~/wip ./sync-skills.sh sync -y     # 通过环境变量指定

  ./sync-skills.sh status                     # 查看整体状态
  ./sync-skills.sh diff android-ui-replica    # 对比某个 skill 的差异
  ./sync-skills.sh sync -y                    # 一键全量同步（软链）
  ./sync-skills.sh sync --copy my-skill       # 复制安装单个 skill
  ./sync-skills.sh unlink old-skill           # 从智能体端移除
  ./sync-skills.sh clean-backups              # 清理备份残留
  ./sync-skills.sh watch                      # 开发模式：自动同步

${BOLD}智能体目标:${NC}
HELP
  # 列出当前活跃的智能体
  while IFS='|' read -r label path; do
    if [[ -n "$label" ]] && [[ -d "$path" ]]; then
      local count
      count=$(find "$path" -mindepth 1 -maxdepth 1 -not -name "*.backup-*" -not -name ".*" 2>/dev/null | wc -l | tr -d ' ')
      printf "  %-12s → %-40s (%d skills)\n" "$label" "$path" "$count"
    fi
  done <<< "$AGENTS_CONFIG"

  echo ""
  echo "${DIM}配置编辑: 修改脚本顶部的「配置区」${NC}"
}

# ============================== 入口 =========================================

main() {
  # 全局 --hub 参数（必须在子命令前指定）
  if [[ "${1:-}" == "--hub" ]]; then
    HUB_ROOT="${2:?请指定 hub 路径}"
    shift 2
  fi

  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    status)         cmd_status "$@" ;;
    sync)           cmd_sync "$@" ;;
    diff)           cmd_diff "$@" ;;
    unlink)         cmd_unlink "$@" ;;
    clean-backups)  cmd_clean_backups "$@" ;;
    watch)          cmd_watch "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
      echo "${RED}未知命令: ${cmd}${NC}" >&2
      echo ""
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
