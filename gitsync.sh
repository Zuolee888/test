#!/usr/bin/env bash
# ================================================================
#  gitsync.sh —— Git 仓库一键同步工具（推送 / 拉取 / 同步 / 异常处理）
# ----------------------------------------------------------------
#  用法：
#     bash gitsync.sh                 # 打开交互菜单（推荐）
#     bash gitsync.sh push            # 一键提交并推送
#     bash gitsync.sh push -m "说明"  # 指定提交信息后推送
#     bash gitsync.sh pull            # 一键拉取远端更新
#     bash gitsync.sh sync            # 先拉后推（日常最常用）
#     bash gitsync.sh status          # 查看仓库状态
#     bash gitsync.sh log             # 查看提交历史
#     bash gitsync.sh -h              # 查看帮助
#
#  Windows 下可直接双击 gitsync.cmd
#
#  异常情况应对（内置）：
#    · 文件正被 Word / Excel / 编辑器 / 播放器打开 —— 拉取前预检，失败后给出明确提示
#    · 上次 git 被强行中断留下 index.lock —— 检测是否有 git 进程，无则一键清理
#    · 卡在变基 / 合并 / 冲突中途 —— 菜单 7 可继续或放弃，不会让仓库烂掉
#    · 断网、超时、认证失败、被墙 —— 自动重试 + 分类诊断
#    · 磁盘空间不足、路径过长、超大文件 —— 提交前拦截
#    · 拉取前自动打还原点 tag —— 万一整合出错可一键回到原样
#    · 索引损坏、远端地址错误、分支未关联 —— 按场景给出修复动作
#
#  设计原则：不删除你的文件、不 --force 推送、不静默覆盖；遇到问题先停手并说明怎么办。
# ================================================================

set -o pipefail

# ---------------------------------------------------------------- 颜色
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'
  M=$'\033[35m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; N=$'\033[0m'
else
  R=''; G=''; Y=''; C=''; M=''; BOLD=''; DIM=''; N=''
fi

hr()    { printf '%s\n' "${DIM}------------------------------------------------------------${N}"; }
title() { printf '\n%s\n' "${BOLD}${C}$*${N}"; }
info()  { printf '%s\n' "  $*"; }
ok()    { printf '%s\n' "  ${G}[OK]${N} $*"; }
warn()  { printf '%s\n' "  ${Y}[!]${N} $*"; }
err()   { printf '%s\n' "  ${R}[错误]${N} $*"; }
step()  { printf '%s\n' "  ${M}==>${N} $*"; }
hint()  { printf '%s\n' "      ${DIM}$*${N}"; }

# ---------------------------------------------------------------- 定位仓库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR" 2>/dev/null || { err "无法进入脚本所在目录"; exit 1; }

GITC_OPTS=(-c core.quotepath=false)
gitc() { git "${GITC_OPTS[@]}" "$@"; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  err "这里不是 Git 仓库：$SCRIPT_DIR"
  info "请把 gitsync.sh 放在仓库根目录，或在仓库里执行：git init"
  exit 1
fi

ROOT="$(gitc rev-parse --show-toplevel)"
GITDIR="$(gitc rev-parse --git-dir)"
case "$GITDIR" in /*) ;; *) GITDIR="$ROOT/$GITDIR" ;; esac
LOG_FILE="$GITDIR/gitsync.log"
RESCUE_PREFIX="gitsync-backup"
NET_OPTS=(-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60)
NET_ERR_PAT='could not resolve host|Failed to connect|Connection (reset|timed out|refused)|operation timed out|network is unreachable|RPC failed|unexpected disconnect|early EOF|TLS|SSL|The remote end hung up|HTTP 5[0-9][0-9]|502|503|504'
LAST_OUT=""
cd "$ROOT" || exit 1

trap 'printf "\n"; warn "操作被中断"; if in_rebase 2>/dev/null || in_merge 2>/dev/null; then err "仓库目前停在整合中途，请用「菜单 7 异常处理」继续或放弃，切勿直接关掉不管"; fi; exit 130' INT

logline() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null; }

# ---------------------------------------------------------------- 基础查询
cur_branch()   { gitc symbolic-ref --short -q HEAD 2>/dev/null || true; }
has_upstream() { gitc rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; }
has_commit()   { gitc rev-parse --verify HEAD >/dev/null 2>&1; }
remote_name() {
  local b r; b="$(cur_branch)"; r="$(gitc config "branch.$b.remote" 2>/dev/null)"
  if [ -n "$r" ] && [ "$r" != "." ]; then printf '%s' "$r"; else printf 'origin'; fi
}
remote_url()  { gitc remote get-url "$(remote_name)" 2>/dev/null || true; }
in_rebase()   { [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; }
in_merge()    { [ -f "$GITDIR/MERGE_HEAD" ]; }
in_cherry()   { [ -f "$GITDIR/CHERRY_PICK_HEAD" ]; }
in_revert()   { [ -f "$GITDIR/REVERT_HEAD" ]; }

state_desc() {
  if in_rebase; then
    if [ -d "$GITDIR/rebase-merge" ]; then
      printf '变基进行中（%s/%s 步）' \
        "$(cat "$GITDIR/rebase-merge/msgnum" 2>/dev/null || echo '?')" \
        "$(cat "$GITDIR/rebase-merge/end" 2>/dev/null || echo '?')"
    else printf '变基/打补丁进行中'; fi
  elif in_merge;  then printf '合并冲突未解决'
  elif in_cherry; then printf '拣选(cherry-pick)未完成'
  elif in_revert; then printf '回滚(revert)未完成'
  else printf '正常'; fi
}

read_ab() {
  AHEAD=0; BEHIND=0
  if has_upstream; then
    local out; out="$(gitc rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"
    if [ -n "$out" ]; then
      BEHIND="$(printf '%s' "$out" | cut -f1)"
      AHEAD="$(printf '%s' "$out" | cut -f2)"
      : "${BEHIND:=0}" "${AHEAD:=0}"
    fi
  fi
}

change_count() { gitc status --porcelain -uall 2>/dev/null | wc -l | tr -d ' '; }
staged_count() { gitc diff --cached --name-only 2>/dev/null | wc -l | tr -d ' '; }

is_tty() { [ -n "${GITSYNC_FORCE_TTY:-}" ] && return 0; [ -t 0 ]; }

confirm() { # $1=提示 $2=默认值(y/n)；非交互环境不阻塞，直接采用默认值
  local ans
  if ! is_tty; then case "$2" in y|Y) return 0 ;; *) return 1 ;; esac; fi
  printf '%s' "  $1 "
  if ! read -r ans; then echo; return 1; fi
  ans="${ans:-$2}"
  case "$ans" in y|Y|yes|YES|是|好) return 0 ;; *) return 1 ;; esac
}

pause_any() {
  printf '%s' "  ${DIM}按回车返回...${N}"
  read -r _ || true
  echo
}

show_out() { # 缩进输出最近一次 git 输出
  [ -n "${LAST_OUT:-}" ] || return 0
  printf '%s\n' "$LAST_OUT" | sed '/^$/d' | sed 's/^/     /'
}

# ---------------------------------------------------------------- 进程与占用
git_proc_count() {
  local n=0
  if command -v ps >/dev/null 2>&1; then
    n="$(ps -W 2>/dev/null | grep -icE '(^|[/\\])(git|git-remote-https|git-remote-http|git-lfs)\.exe' || true)"
  fi
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# 探测单个文件是否能被写入（能发现被 Word/Excel 独占锁定、只读属性）
file_write_ok() {
  local f="$1"
  [ -f "$f" ] || return 0
  [ -w "$f" ] || return 1
  # 追加 0 字节：不改变内容，只探测写句柄能否拿到；先屏蔽子 shell 的报错信息
  if ( exec 2>/dev/null; : >>"$f" ); then return 0; else return 1; fi
}

check_locked_files() { # 拉取前：检查即将被更新、但可能被占用的文件
  local f n=0
  local files
  files="$(gitc diff --name-only "HEAD" '@{u}' 2>/dev/null | head -40)"
  [ -z "$files" ] && return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! file_write_ok "$f"; then
      warn "文件被占用或只读：$f"
      hint "请先在 Word / Excel / 编辑器 / 播放器里关闭它，或取消只读属性"
      n=$((n+1))
    fi
  done <<<"$files"
  if [ "$n" -gt 0 ]; then
    warn "共有 $n 个文件无法写入，直接拉取很可能失败"
    if confirm "仍然继续拉取? [y/N]" n; then return 0; else return 1; fi
  fi
  return 0
}

# ---------------------------------------------------------------- 预检
preflight() {
  local bad=0

  # 1. .git 目录是否可写（只读盘、权限、杀软保护、OneDrive 占用）
  if [ ! -w "$GITDIR" ]; then
    err "仓库的 .git 目录不可写：$GITDIR"
    hint "可能原因：目录只读、没有权限、被安全软件保护、或在只读网盘上"
    return 1
  fi

  # 2. 是否能正常读取仓库状态（索引损坏会在这里暴露）
  if ! gitc status --porcelain -uall >/dev/null 2>&1; then
    err "读取仓库状态失败，可能 .git/index 已损坏"
    LAST_OUT="$(gitc status 2>&1)"
    show_out
    if confirm "尝试重建索引?（只重建索引记录，不会改动你的文件内容）[y/N]" n; then
      mv "$GITDIR/index" "$GITDIR/index.broken.$(date +%s)" 2>/dev/null
      if gitc reset -q >/dev/null 2>&1; then ok "索引已重建"; else err "重建失败，建议重新克隆仓库"; return 1; fi
    else
      return 1
    fi
  fi

  # 3. 残留的 index.lock（上次被强行中断、关窗口、断电、杀进程）
  if [ -f "$GITDIR/index.lock" ]; then
    warn "发现残留锁文件 .git/index.lock —— 通常是上次 git 被强制中断留下的"
    local np; np="$(git_proc_count)"
    if [ "$np" -gt 0 ]; then
      err "检测到仍有 $np 个 git 进程在运行，请等它结束，不要删除锁文件"
      hint "若确认卡死，可在任务管理器结束 git.exe 后重试"
      return 1
    fi
    if confirm "当前没有 git 进程在运行，删除残留锁文件并继续? [y/N]" n; then
      rm -f "$GITDIR/index.lock" && ok "已清理残留锁文件"
    else
      info "已取消。你也可以手动删除：$GITDIR/index.lock"; return 1
    fi
  fi

  # 4. 是否卡在变基 / 合并 / 拣选中途
  local st; st="$(state_desc)"
  if [ "$st" != "正常" ]; then
    err "仓库当前状态：$st"
    hint "请先用「菜单 7 异常处理」继续或放弃这次操作，再执行同步"
    LAST_OUT="$(gitc status -s 2>&1 | head -15)"
    show_out
    return 1
  fi

  # 5. 磁盘剩余空间
  local free_mb
  free_mb="$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2{print int($4/1024)}')"
  case "$free_mb" in ''|*[!0-9]*) ;; *)
    if [ "$free_mb" -lt 200 ]; then
      warn "磁盘剩余空间只有 ${free_mb}MB，操作可能中途失败"
      confirm "仍然继续? [y/N]" n || bad=1
    fi ;;
  esac
  [ "$bad" -eq 1 ] && return 1

  # 6. 路径过长（Windows 260 字符限制）
  local longn=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ $(( ${#ROOT} + ${#f} + 2 )) -gt 240 ]; then
      warn "路径过长（可能触发 Windows 260 字符限制）：$f"
      longn=$((longn+1))
    fi
  done < <(gitc status --porcelain -uall 2>/dev/null | cut -c4- | head -200)
  [ "$longn" -gt 0 ] && hint "可把仓库移到更短的路径，如 D:/git/xxx"

  # 7. 云同步目录提醒（OneDrive 会同步 .git 导致锁冲突）
  case "$ROOT" in
    *OneDrive*|*onedrive*|*坚果云*|*Nutstore*|*Dropbox*|*百度网盘*)
      warn "仓库位于云同步目录中，同步软件可能在后台读写 .git 造成锁冲突"
      hint "建议暂停该目录的实时同步，或把仓库移到本地普通目录" ;;
  esac

  return 0
}

# ---------------------------------------------------------------- 还原点
make_rescue() {
  has_commit || return 0
  local tag="${RESCUE_PREFIX}-$(date '+%Y%m%d-%H%M%S')"
  if gitc tag "$tag" HEAD >/dev/null 2>&1; then
    RESCUE_TAG="$tag"
    info "已创建还原点：${DIM}$tag${N}（万一整合出错，菜单 7 可一键回来）"
  fi
}

list_rescue() { gitc tag -l "${RESCUE_PREFIX}-*" --sort=-creatordate 2>/dev/null; }

restore_rescue() {
  title "从还原点恢复"
  local tags; tags="$(list_rescue)"
  if [ -z "$tags" ]; then info "还没有还原点（每次拉取前会自动创建一个）"; return 0; fi
  local i=1
  local -a arr=()
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    arr+=("$t")
    info "$i) $t   $(gitc log -1 --format='%ad %s' --date=format:'%m-%d %H:%M' "$t" 2>/dev/null)"
    i=$((i+1))
    [ "$i" -gt 9 ] && break
  done <<<"$tags"
  printf '  选择要回到的还原点序号（回车取消）: '
  local pick; read -r pick || return 0
  case "$pick" in ''|*[!0-9]*) info "已取消"; return 0 ;; esac
  [ "$pick" -lt 1 ] || [ "$pick" -gt "${#arr[@]}" ] && { err "序号无效"; return 1; }
  local tag="${arr[$((pick-1))]}"
  echo
  warn "这会把当前分支回退到 $tag 那个时刻"
  info "现在的未提交改动会先自动存进 stash，不会丢；之后可用 git stash apply 取回"
  printf '  %s确认请输入「恢复」两个字: %s' "${R}${BOLD}" "${N}"
  local sure; read -r sure || return 0
  [ "$sure" = "恢复" ] || { info "已取消"; return 0; }
  if [ "$(change_count)" -gt 0 ]; then
    step "先把当前改动存进 stash"
    if gitc stash push -u -m "gitsync-restore-$(date '+%Y%m%d-%H%M%S')" >/dev/null 2>&1; then
      ok "当前改动已存入 stash（git stash list 可查看，git stash apply 可取回）"
    else
      err "本地改动无法存入 stash（多半有文件正被其他程序占用）"
      info "为保证不丢东西，已中止恢复，仓库没有任何改动"
      hint "先关掉占用文件的程序，或手动提交改动后再试"
      return 1
    fi
  fi
  if gitc reset --hard "$tag" >/dev/null 2>&1; then
    ok "已回到 $tag"
    logline "restore $tag"
  else
    err "恢复失败"; return 1
  fi
}

clean_rescue() {
  local tags; tags="$(list_rescue)"
  [ -z "$tags" ] && { info "没有还原点需要清理"; return 0; }
  local total; total="$(printf '%s\n' "$tags" | wc -l | tr -d ' ')"
  if [ "$total" -le 5 ]; then ok "还原点共 $total 个，暂时不需要清理"; return 0; fi
  warn "保留最近 5 个，其余 $((total-5)) 个将被删除"
  if confirm "确认清理? [y/N]" n; then
    printf '%s\n' "$tags" | tail -n +6 | while IFS= read -r t; do
      [ -n "$t" ] && gitc tag -d "$t" >/dev/null && info "已删除 $t"
    done
    ok "清理完成"
  fi
}

# ---------------------------------------------------------------- 失败诊断
diagnose_failure() {
  local o="${1:-}"
  [ -n "$o" ] || return 0
  local hit=0

  if printf '%s' "$o" | grep -qiE 'unable to unlink|cannot create file|Permission denied|being used by another process|另一个程序正在使用|拒绝访问|Operation not permitted'; then
    hit=1; hr
    err "有文件正被其他程序占用，git 无法覆盖它"
    info "处理办法："
    info "  1. 关掉正在打开这些文件的程序：Word / Excel / PDF 阅读器 / 播放器 / 编辑器"
    info "  2. 如果是只读属性：右键文件 → 属性 → 取消「只读」"
    info "  3. 如果是云盘同步中：暂停同步后重试"
    info "  4. 然后再执行一次拉取即可（本地不会丢东西）"
  fi

  if printf '%s' "$o" | grep -qiE 'index\.lock|Unable to create .*\.lock|File exists'; then
    hit=1; hr
    err "git 锁文件冲突：另一个 git 进程可能正在操作这个仓库"
    info "处理办法："
    info "  1. 关掉 VS Code / GitHub Desktop / SourceTree 等正在刷新仓库的工具"
    info "  2. 确认任务管理器里没有 git.exe 在跑"
    info "  3. 删除残留锁：菜单 7 → 5，或手动 rm .git/index.lock"
  fi

  if printf '%s' "$o" | grep -qiE 'Authentication failed|could not read Username|terminal prompts disabled|403|401|Permission to .* denied|invalid username or password'; then
    hit=1; hr
    err "身份验证失败"
    info "处理办法："
    info "  · GitHub 已不支持用账号密码推送，密码位置要填 Personal Access Token"
    info "  · 或让凭据管理器重新登录：控制面板 → 凭据管理器 → 删除 git:https://github.com"
    info "  · 重新执行一次，会弹窗让你登录"
  fi

  if printf '%s' "$o" | grep -qiE 'could not resolve host|Failed to connect|Connection (reset|timed out|refused)|network is unreachable|timed out'; then
    hit=1; hr
    err "连不上远端（网络问题）"
    info "处理办法："
    info "  · 检查网络；开了代理的话确认终端也走代理"
    info "  · 浏览器能打开 github.com 而 git 不行，通常是代理没生效"
    info "  · 稍后重试，脚本已自动重试过 3 次"
  fi

  if printf '%s' "$o" | grep -qiE 'non-fast-forward|\[rejected\]|fetch first|failed to push some refs'; then
    hit=1; hr
    err "远端有你没有的提交，推送被拒绝（这是保护，不是故障）"
    info "处理办法：用「菜单 3 同步」先拉取合并，再推送即可"
  fi

  if printf '%s' "$o" | grep -qiE 'RPC failed|unexpected disconnect|early EOF|The remote end hung up'; then
    hit=1; hr
    err "传输中途断开（大文件 / 网络不稳 / 服务端限制）"
    info "处理办法："
    info "  · 重试一次（脚本已自动重试）"
    info "  · 仍然失败可执行：git config http.version HTTP/1.1"
    info "  · 文件过大建议改用 Git LFS"
  fi

  if printf '%s' "$o" | grep -qiE 'exceeds|larger than|GH001|GH005|file size limit'; then
    hit=1; hr
    err "文件超过 GitHub 体积限制（单文件 100MB）"
    info "处理办法：把大文件移出仓库，或用 Git LFS 管理"
  fi

  if printf '%s' "$o" | grep -qiE 'No space left|disk quota'; then
    hit=1; hr
    err "磁盘空间不足"; info "清理磁盘后重试"
  fi

  if printf '%s' "$o" | grep -qiE 'Repository not found|does not appear to be a git repository|not found'; then
    hit=1; hr
    err "远端仓库不存在或地址有误（也可能是没有访问权限）"
    info "检查：菜单 6 → 1 查看远端地址；私有仓库需先登录有权限的账号"
  fi

  if printf '%s' "$o" | grep -qiE 'CONFLICT|needs merge|would be overwritten'; then
    hit=1; hr
    err "存在冲突 / 本地改动会被覆盖"
    info "先用「菜单 7」处理冲突，或先提交本地改动再拉取"
  fi

  if [ "$hit" -eq 0 ]; then
    hr; info "未匹配到已知原因，上面是 git 的原始输出，可对照查看"
  fi
  echo
}

# ---------------------------------------------------------------- 网络执行（带重试）
net_exec() { # 用法：net_exec fetch --prune origin
  LAST_OUT=""; local i=1 rc
  while :; do
    LAST_OUT="$(git "${GITC_OPTS[@]}" "${NET_OPTS[@]}" "$@" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && return 0
    if [ "$i" -lt 3 ] && printf '%s' "$LAST_OUT" | grep -qiE "$NET_ERR_PAT"; then
      warn "第 $i 次尝试失败（网络中断），$((i*2)) 秒后重试…"
      sleep $((i*2)); i=$((i+1)); continue
    fi
    return "$rc"
  done
}

# ---------------------------------------------------------------- 远端配置
offer_add_remote() {
  warn "当前仓库没有配置远端"
  if confirm "现在添加一个远端地址? [y/N]" n; then
    printf '  远端地址（例：https://github.com/用户名/仓库.git）: '
    local url; read -r url || return 1
    [ -z "$url" ] && { err "地址为空，已取消"; return 1; }
    gitc remote add origin "$url" 2>/dev/null || gitc remote set-url origin "$url"
    ok "已设置 origin -> $url"
  else
    return 1
  fi
}

# ---------------------------------------------------------------- 提交前检查
check_big_files() {
  local lim_warn=$((50*1024*1024)) lim_block=$((100*1024*1024))
  local f size big=0 blocked=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    size=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if [ "$size" -gt "$lim_block" ]; then
      err "超大文件 $(du -h "$f" 2>/dev/null | cut -f1)：$f （GitHub 单文件上限 100MB）"
      blocked=1
    elif [ "$size" -gt "$lim_warn" ]; then
      warn "较大的文件 $(du -h "$f" 2>/dev/null | cut -f1)：$f"
      big=1
    fi
  done < <(gitc status --porcelain -uall 2>/dev/null | cut -c4-)

  if [ "$blocked" -eq 1 ]; then
    err "存在超过 100MB 的文件，无法推送。请移出仓库或改用 Git LFS。"
    return 1
  fi
  [ "$big" -eq 1 ] && { confirm "以上文件较大，仍要提交吗? [y/N]" n || return 1; }
  return 0
}

ask_message() {
  local def; def="更新 $(date '+%Y-%m-%d %H:%M')"
  if ! is_tty; then printf '%s' "$def"; return 0; fi   # 定时任务不阻塞
  printf '  提交说明 [%s]: ' "$def"
  local m; read -r m || m=""
  [ -z "$m" ] && m="$def"
  printf '%s' "$m"
}

# ---------------------------------------------------------------- 推送
do_push() {
  local msg="${MSG:-}"
  title "推送到远端"
  preflight || { err "预检未通过，已中止推送"; return 1; }

  if [ -z "$(gitc remote)" ]; then offer_add_remote || return 1; fi

  local branch; branch="$(cur_branch)"
  if [ -z "$branch" ]; then
    err "当前处于游离 HEAD 状态（不在任何分支上），提交容易丢失"
    hint "先切回分支：git switch main"
    return 1
  fi
  info "仓库：$ROOT"
  info "分支：${BOLD}$branch${N}   远端：$(remote_name) -> $(remote_url)"

  local changes; changes="$(change_count)"
  if [ "$changes" -gt 0 ]; then
    step "本地有 $changes 处改动"
    gitc status -s -uall | head -20 | sed 's/^/     /'
    [ "$changes" -gt 20 ] && info "${DIM}... 其余 $((changes-20)) 项省略${N}"

    # 先查占用：被独占打开的文件会导致 git add 失败，这比大文件更常见
    local locked=0 f
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      file_write_ok "$f" || { warn "文件被占用或只读：$f"; locked=1; }
    done < <(gitc status --porcelain -uall 2>/dev/null | cut -c4- | head -40)
    if [ "$locked" -eq 1 ]; then
      warn "有文件正被其他程序锁定（Word/Excel/播放器等），提交可能失败"
      confirm "先关掉相关程序再继续? 按 y 继续尝试，n 取消 [y/N]" n || return 1
    fi

    check_big_files || return 1

    [ -z "$msg" ] && msg="$(ask_message)"
    [ -z "$msg" ] && { err "提交说明为空，已取消"; return 1; }

    gitc add -A 2>"$GITDIR/.gitsync_add_err"
    local add_rc=$?
    if [ "$add_rc" -ne 0 ]; then
      LAST_OUT="$(cat "$GITDIR/.gitsync_add_err" 2>/dev/null)"
      rm -f "$GITDIR/.gitsync_add_err"
      err "暂存文件失败"
      show_out
      diagnose_failure "$LAST_OUT"
      return 1
    fi
    rm -f "$GITDIR/.gitsync_add_err"

    if gitc diff --cached --quiet; then
      ok "没有实际内容改动，跳过提交"
    else
      local nfiles; nfiles="$(gitc diff --cached --name-only | wc -l | tr -d ' ')"
      if gitc commit -m "$msg" >/dev/null 2>&1; then
        ok "已提交：$msg（$nfiles 个文件）"
        logline "commit: $msg ($nfiles files)"
      else
        LAST_OUT="$(gitc commit -m "$msg" 2>&1)"
        err "提交失败"
        show_out
        if printf '%s' "$LAST_OUT" | grep -qiE 'Please tell me who you are|empty ident'; then
          info "还没设置提交署名，去 菜单 6 → 3 设置姓名和邮箱即可"
        else
          diagnose_failure "$LAST_OUT"
        fi
        return 1
      fi
    fi
  else
    ok "工作区干净，没有需要提交的改动"
  fi

  # 首次推送：建立上游关联
  if ! has_upstream; then
    warn "当前分支还没有关联远端分支"
    if confirm "现在推送 ${branch} 到 $(remote_name) 并建立关联? [Y/n]" y; then
      if net_exec push -u "$(remote_name)" "$branch"; then
        show_out
        ok "推送完成，已建立关联 $(remote_name)/$branch"
        logline "push -u $branch"
        return 0
      else
        err "推送失败"; show_out; diagnose_failure "$LAST_OUT"; return 1
      fi
    fi
    return 1
  fi

  # 先看远端有没有新东西，避免被拒绝
  step "检查远端是否有新提交"
  if ! net_exec fetch --prune "$(remote_name)"; then
    warn "无法访问远端（网络或认证问题），仍尝试推送"
    printf '%s\n' "$LAST_OUT" | sed '/^$/d' | head -5 | sed 's/^/     /'
  fi
  read_ab
  if [ "$BEHIND" -gt 0 ]; then
    warn "远端有 $BEHIND 个你还没有的新提交，直接推送会被拒绝"
    info "远端新增："
    gitc --no-pager log --oneline --no-decorate "HEAD..@{u}" | head -10 | sed 's/^/     /'
    if confirm "先拉取整合（变基）再推送? [Y/n]" y; then
      do_pull_inner || { err "拉取未成功，已中止推送"; return 1; }
    else
      warn "已取消推送（避免覆盖远端）"; return 1
    fi
  fi

  step "执行推送"
  if net_exec push "$(remote_name)" "$branch"; then
    show_out
    read_ab
    ok "推送完成：$branch -> $(remote_name)/$branch（未推送：$AHEAD）"
    logline "push $branch"
    return 0
  else
    err "推送失败"
    show_out
    diagnose_failure "$LAST_OUT"
    return 1
  fi
}

# ---------------------------------------------------------------- 拉取
do_pull() {
  title "从远端拉取"
  preflight || { err "预检未通过，已中止拉取"; return 1; }
  if [ -z "$(gitc remote)" ]; then offer_add_remote || return 1; fi

  local branch; branch="$(cur_branch)"
  if [ -z "$branch" ]; then err "当前处于游离 HEAD 状态，请先切换分支"; return 1; fi
  if ! has_upstream; then
    err "当前分支未关联远端分支，无法判断要拉取什么"
    hint "先执行一次推送（会自动建立关联），或：git branch --set-upstream-to=origin/$branch $branch"
    return 1
  fi

  step "连接远端"
  if ! net_exec fetch --prune "$(remote_name)"; then
    err "拉取失败：无法访问远端"
    show_out
    diagnose_failure "$LAST_OUT"
    return 1
  fi

  read_ab
  if [ "$BEHIND" -eq 0 ]; then
    ok "已经是最新版本，远端没有新提交"
    [ "$AHEAD" -gt 0 ] && warn "本地有 $AHEAD 个提交尚未推送，用菜单 1 推送"
    return 0
  fi

  info "远端有 ${BOLD}$BEHIND${N} 个新提交："
  gitc --no-pager log --oneline --no-decorate "HEAD..@{u}" | head -15 | sed 's/^/     /'
  echo
  [ "$AHEAD" -gt 0 ] && warn "注意：本地也有 $AHEAD 个未推送提交，两边的历史需要整合（变基）"

  check_locked_files || { warn "已取消拉取"; return 1; }

  do_pull_inner || return 1
  return 0
}

do_pull_inner() {
  local branch; branch="$(cur_branch)"

  if [ "$(change_count)" -gt 0 ]; then
    warn "本地有未提交的改动，会自动暂存（autostash）后再拉取，不会丢"
  fi
  make_rescue

  step "拉取并变基（git pull --rebase --autostash）"
  if net_exec pull --rebase --autostash "$(remote_name)" "$branch"; then
    show_out
    read_ab
    ok "拉取完成，本地已更新（落后 $BEHIND / 领先 $AHEAD）"
    logline "pull $branch"
    return 0
  fi

  # ---- 失败分类处理 ----
  show_out

  if in_rebase; then
    local conflicts
    conflicts="$(gitc diff --name-only --diff-filter=U 2>/dev/null)"
    err "拉取时发生冲突，需要你手动选一下保留哪边"
    hr
    info "冲突文件："
    [ -n "$conflicts" ] && printf '%s\n' "$conflicts" | sed 's/^/       /'
    echo
    info "处理步骤："
    info "  1. 用编辑器打开冲突文件，找到 <<<<<<<  =======  >>>>>>> 标记"
    info "  2. 删掉标记，保留你需要的内容（通常两边都要留一部分）"
    info "  3. 保存后执行：git add <文件名>"
    info "  4. 然后菜单 7 → 2 继续变基（等价于 git rebase --continue）"
    info "  或者现在放弃：菜单 7 → 3（等价于 git rebase --abort），本地回到拉取前"
    hr
    if confirm "现在放弃本次拉取、恢复到拉取前的状态? [y/N]" n; then
      gitc rebase --abort >/dev/null 2>&1 && ok "已恢复，文件回到拉取前的样子"
    else
      warn "已保留冲突现场，请按上面步骤解决后执行「菜单 7 → 2」"
    fi
    return 1
  fi

  if gitc status --porcelain -uall | grep -q '^??'; then
    err "拉取失败：远端新增的文件与本地未跟踪文件同名，git 不敢覆盖"
    info "冲突的本地文件："
    gitc status -s -uall | grep '^??' | head -10 | sed 's/^/     /'
    hint "把本地同名文件改名或移到别处，再重新拉取（内容不会丢）"
    return 1
  fi

  diagnose_failure "$LAST_OUT"
  return 1
}

# ---------------------------------------------------------------- 同步
do_sync() {
  title "同步（先拉取，再推送）"
  preflight || { err "预检未通过，已中止同步"; return 1; }
  do_pull_inner || { err "同步中止：拉取未成功，未执行推送"; return 1; }
  do_push
}

# ---------------------------------------------------------------- 查看
show_status() {
  title "仓库状态"
  local branch; branch="$(cur_branch)"
  info "路径   : $ROOT"
  info "分支   : ${BOLD}${branch:-（游离 HEAD）}${N}"
  info "远端   : $(remote_name) -> $(remote_url)"
  local st; st="$(state_desc)"
  if [ "$st" = "正常" ]; then
    info "状态   : ${G}正常${N}"
  else
    warn "状态   : ${R}$st${N}（用菜单 7 处理）"
  fi
  if has_upstream; then
    read_ab
    info "跟踪   : $(gitc rev-parse --abbrev-ref '@{u}')   领先 ↑$AHEAD  落后 ↓$BEHIND"
  else
    warn "当前分支未关联远端分支"
  fi

  local changes; changes="$(change_count)"
  if [ "$changes" -eq 0 ]; then
    ok "工作区干净，没有未提交的改动"
  else
    info "改动   : ${Y}$changes${N} 项（已暂存 $(staged_count)）"
    gitc status -s -uall | head -25 | sed 's/^/     /'
    [ "$changes" -gt 25 ] && info "${DIM}... 其余 $((changes-25)) 项省略${N}"
  fi

  info "最近提交："
  gitc --no-pager log --oneline --no-decorate -5 2>/dev/null | sed 's/^/     /'
  echo
}

show_log() {
  title "提交历史"
  gitc --no-pager log --graph --decorate --oneline --date=short \
       --pretty=format:'%C(yellow)%h%C(reset) %C(cyan)%ad%C(reset) %C(green)%an%C(reset) %s' -20 2>/dev/null
  echo; echo
}

# ---------------------------------------------------------------- 异常处理面板
exception_menu() {
  while :; do
    title "异常处理 / 恢复"
    local st; st="$(state_desc)"
    if [ "$st" = "正常" ]; then info "当前状态：${G}正常${N}"
    else warn "当前状态：${R}$st${N}"; fi
    echo
    info "  1  检查是否存在卡住的中途操作"
    info "  2  继续变基（解决完冲突后用）"
    info "  3  放弃变基，回到操作前"
    info "  4  放弃合并（merge --abort）"
    info "  5  清理残留锁文件 index.lock"
    info "  6  重建损坏的索引"
    info "  7  查看并恢复到还原点"
    info "  8  清理过旧的还原点"
    info "  0  返回"
    printf '  %s请选择: %s' "${C}" "${N}"
    local c; read -r c || return 0
    echo
    case "$c" in
      1) info "状态：$st"
         if [ "$st" != "正常" ]; then
           gitc status -s | head -20 | sed 's/^/     /'
           echo; info "用 2 继续 / 3 放弃 来处理"
         else
           ok "没有卡住的操作"
           [ -f "$GITDIR/index.lock" ] && warn "但存在 index.lock，可用 5 清理"
         fi
         pause_any ;;
      2) if ! in_rebase; then warn "当前没有进行中的变基"; else
           if gitc diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
             err "还有未解决的冲突文件，先 git add 之后再继续"
           else
             if net_exec rebase --continue; then show_out; ok "变基已完成"
             else show_out; err "继续失败"; diagnose_failure "$LAST_OUT"; fi
           fi
         fi
         pause_any ;;
      3) if ! in_rebase; then warn "当前没有进行中的变基"; else
           confirm "放弃本次变基，回到操作前的样子? [y/N]" n \
             && { gitc rebase --abort >/dev/null 2>&1 && ok "已放弃变基" || err "放弃失败"; }
         fi
         pause_any ;;
      4) if ! in_merge; then warn "当前没有进行中的合并"; else
           confirm "放弃本次合并? [y/N]" n \
             && { gitc merge --abort >/dev/null 2>&1 && ok "已放弃合并" || err "放弃失败"; }
         fi
         pause_any ;;
      5) if [ ! -f "$GITDIR/index.lock" ]; then ok "没有残留锁文件"; else
           local np; np="$(git_proc_count)"
           if [ "$np" -gt 0 ]; then err "仍有 $np 个 git 进程在跑，请先等它结束或结束进程"
           else rm -f "$GITDIR/index.lock" && ok "已删除 index.lock"; fi
         fi
         pause_any ;;
      6) warn "只在索引确实损坏时用（症状：git status 报 index file smaller / corrupt）"
         confirm "重建索引?（不改动工作区文件）[y/N]" n && {
           mv "$GITDIR/index" "$GITDIR/index.broken.$(date +%s)" 2>/dev/null
           gitc reset -q >/dev/null 2>&1 && ok "索引已重建" || err "失败，建议重新克隆仓库"
         }
         pause_any ;;
      7) restore_rescue; pause_any ;;
      8) clean_rescue; pause_any ;;
      0|"") return 0 ;;
      *) warn "无效选项"; pause_any ;;
    esac
  done
}

# ---------------------------------------------------------------- 设置
doctor() {
  title "仓库体检"
  info "未提交改动        : $(change_count) 项"
  info "当前状态          : $(state_desc)"
  if [ -f .gitignore ]; then ok ".gitignore 已存在（$(wc -l <.gitignore | tr -d ' ') 行）"
  else warn "没有 .gitignore，容易出现 __pycache__ / 临时文件的噪音提交"; fi
  local big; big="$(find . -path ./.git -prune -o -type f -size +10M -print 2>/dev/null | head -5)"
  if [ -n "$big" ]; then warn "仓库里有大于 10MB 的文件："; printf '%s\n' "$big" | sed 's/^/     /'
  else ok "没有大于 10MB 的文件"; fi
  info "仓库体积          : $(du -sh .git 2>/dev/null | cut -f1)（.git）"
  info "被跟踪文件数      : $(gitc ls-files | wc -l | tr -d ' ')"
  info "提交署名          : $(gitc config user.name 2>/dev/null || echo '未设置') <$(gitc config user.email 2>/dev/null || echo '未设置')>"
  info "凭据管理器        : $(gitc config --get credential.helper 2>/dev/null || gitc config --global --get credential.helper 2>/dev/null || echo '未配置')"
  info "运行中的 git 进程 : $(git_proc_count) 个"
  if [ -f "$GITDIR/index.lock" ]; then warn "存在 index.lock，若确认没有 git 在跑可清理（菜单 7 → 5）"; fi
  if in_rebase; then err "存在未完成的变基（菜单 7 处理）"; fi
  local nres; nres="$(list_rescue | wc -l | tr -d ' ')"
  info "还原点数量        : $nres 个"
  echo
}

make_gitignore() {
  title "生成 .gitignore"
  if [ -f .gitignore ]; then
    warn ".gitignore 已存在，不会覆盖"
    confirm "查看现有内容? [y/N]" n && { sed 's/^/     /' .gitignore; }
    return 0
  fi
  cat >.gitignore <<'EOF'
# ---- 系统 / 编辑器 ----
.DS_Store
Thumbs.db
desktop.ini
.vscode/
.idea/
*.swp

# ---- Python ----
__pycache__/
*.py[cod]
.venv/
venv/

# ---- 编译产物 ----
*.exe
*.o
*.obj
*.class
a.out

# ---- 临时文件 ----
*.tmp
*.bak
*.log
EOF
  ok "已生成 .gitignore（此后不再跟踪这些文件，已被跟踪的不受影响）"
}

settings() {
  while :; do
    title "设置"
    info "  1  查看远端地址"
    info "  2  更换 / 添加远端地址"
    info "  3  修改提交署名（user.name / user.email）"
    info "  4  生成 .gitignore"
    info "  5  仓库体检"
    info "  6  清理本地无用对象（git gc）"
    info "  0  返回"
    printf '  %s请选择: %s' "${C}" "${N}"
    local c; read -r c || return 0
    echo
    case "$c" in
      1) info "$(remote_name) -> $(remote_url)"; pause_any ;;
      2) info "当前：$(remote_url)"
         printf '  新的远端地址: '; local u; read -r u || continue
         if [ -n "$u" ]; then
           if [ -z "$(gitc remote)" ]; then gitc remote add origin "$u"; else gitc remote set-url origin "$u"; fi
           ok "已设置 origin -> $u"; logline "set-url $u"
         fi
         pause_any ;;
      3) printf '  姓名: '; local nm; read -r nm || continue
         printf '  邮箱: '; local em; read -r em || continue
         [ -n "$nm" ] && gitc config user.name "$nm"
         [ -n "$em" ] && gitc config user.email "$em"
         ok "已更新：$(gitc config user.name) <$(gitc config user.email)>"
         pause_any ;;
      4) make_gitignore; pause_any ;;
      5) doctor; pause_any ;;
      6) gitc gc --prune=now --quiet && ok "清理完成，当前 .git 体积 $(du -sh .git 2>/dev/null | cut -f1)"; pause_any ;;
      0|"") return 0 ;;
      *) warn "无效选项"; pause_any ;;
    esac
  done
}

# ---------------------------------------------------------------- 菜单
banner() {
  local branch st; branch="$(cur_branch)"; st="$(state_desc)"
  read_ab
  printf '%s\n' "${BOLD}${C}============================================================${N}"
  printf '%s\n' "${BOLD}  Git 一键同步   $(basename "$ROOT")${N}"
  printf '%s\n' "  分支 ${BOLD}${branch:-游离}${N}   远端 $(remote_name)   领先 ↑${AHEAD}  落后 ↓${BEHIND}"
  if [ "$st" = "正常" ]; then
    printf '%s\n' "  改动 $(change_count) 项   状态 ${G}正常${N}       $(date '+%Y-%m-%d %H:%M')"
  else
    printf '%s\n' "  改动 $(change_count) 项   状态 ${R}${st}${N}"
  fi
  printf '%s\n' "${BOLD}${C}============================================================${N}"
}

menu() {
  while :; do
    clear 2>/dev/null || true
    banner
    info ""
    info "  ${BOLD}1${N}  推送      提交本地改动并上传到远端"
    info "  ${BOLD}2${N}  拉取      下载远端最新内容到本地"
    info "  ${BOLD}3${N}  同步      先拉取再推送（日常最常用）"
    info "  ${BOLD}4${N}  状态      改了哪些文件、领先落后多少"
    info "  ${BOLD}5${N}  历史      最近提交记录"
    info "  ${BOLD}6${N}  设置      远端 / 署名 / .gitignore / 体检"
    info "  ${BOLD}7${N}  异常处理  冲突、锁文件、中断、还原点"
    info "  ${BOLD}0${N}  退出"
    info ""
    printf '  %s请选择 [0-7]: %s' "${C}" "${N}"
    local c; read -r c || exit 0
    case "$c" in
      1) do_push ;;
      2) do_pull ;;
      3) do_sync ;;
      4) show_status ;;
      5) show_log ;;
      6) settings ;;
      7) exception_menu ;;
      0|q|Q|exit) info "已退出"; exit 0 ;;
      "") : ;;
      *) warn "无效选项，请输入 0-7" ;;
    esac
    echo
    pause_any
  done
}

usage() {
  cat <<'EOF'
gitsync.sh —— Git 仓库一键同步工具

  bash gitsync.sh                 打开交互菜单
  bash gitsync.sh push            提交 + 推送
  bash gitsync.sh push -m "说明"  指定提交说明后推送
  bash gitsync.sh pull            拉取远端更新
  bash gitsync.sh sync            先拉后推（= pull + push）
  bash gitsync.sh status          查看状态
  bash gitsync.sh log             查看提交历史
  bash gitsync.sh -h              显示本帮助

Windows：双击 gitsync.cmd 打开菜单。
异常处理（冲突 / 锁文件 / 中断恢复）请用菜单 7。
EOF
}

# ---------------------------------------------------------------- 入口
CMD=""
MSG=""
while [ $# -gt 0 ]; do
  case "$1" in
    push|p|推|推送)   CMD=push ;;
    pull|l|拉|拉取)   CMD=pull ;;
    sync|s|同步)      CMD=sync ;;
    status|st|状态)   CMD=status ;;
    log|history|历史) CMD=log ;;
    -m|--message)     shift; MSG="${1:-}" ;;
    -h|--help|help)   usage; exit 0 ;;
    *) warn "忽略未知参数：$1" ;;
  esac
  [ $# -gt 0 ] && shift
done

case "$CMD" in
  push)   do_push;     exit $? ;;
  pull)   do_pull;     exit $? ;;
  sync)   do_sync;     exit $? ;;
  status) show_status; exit 0 ;;
  log)    show_log;    exit 0 ;;
  *)      menu ;;
esac
