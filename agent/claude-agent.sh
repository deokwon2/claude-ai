#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# claude-agent.sh — Claude Agent Team 통합 구성기
#
#   -mode agentteams  자율적 팀원 구성, 리더가 조율
#   -mode subagent    전문화 서브에이전트, 리더가 위임 (기본)
#
#   Pane 타이틀:
#     [AgentTeams] Team Leader(Sonnet 4.6)
#     [AgentTeams] Agent-1(Sonnet 4.6) : 시장조사
#     [Subagent] Team Leader(Opus 4.7)
#     [Subagent] Agent-1(Sonnet 4.6) : M0 구현
#
#   실행 중 동적 제어 (./.claude-agent/team):
#     scale N      pane 추가/제거 + claude 자동 실행
#     assign N 타이틀 [메시지]   업무 배정 + 타이틀 갱신
#     title N 타이틀             타이틀만 변경
# ============================================================

MODE="subagent"
SESSION=""
DIR="$PWD"
NO_ATTACH=0
TEAM_NAMES=()
TEAM_PROMPTS=()
AGENT_SIZE=""
MODEL_FLAG=""   # claude --model 에 넘길 값 (sonnet / opus / claude-sonnet-4-6 등)
MODEL_DISPLAY="" # pane 타이틀 표시용 (Sonnet 4.6 / Opus 4.7 / Haiku 4.5)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -mode agentteams|subagent   팀 모드 (기본: subagent)
  -model MODEL                사용 모델 (sonnet/opus/haiku 또는 full ID)
                              미지정 시 ~/.claude/settings.json 자동 감지
  -agent N                    총 팀 인원 (리더 1 + Agent N-1), N: 2..11
  -team NAME [PROMPT]         이름 기반 팀 등록, 여러 번 사용 가능
                              PROMPT: 파일경로 or "인라인텍스트" (선택)
  -dir PATH                   작업 디렉토리 (기본: 현재)
  -session NAME               tmux 세션 이름 (기본: 모드-디렉토리명)
  -no-attach                  생성 후 attach/switch 생략
  -h, --help                  도움말

Modes:
  agentteams  번호 기반 팀원, 자율 협업 조율
  subagent    이름 기반 전문화 에이전트, 리더 위임

Examples:
  # AgentTeams: 번호 기반 4명
  $(basename "$0") -mode agentteams -agent 4

  # Subagent: 이름 기반 (자동 subagent 모드)
  $(basename "$0") -team interface -team infra -team fe

  # Subagent: 초기 프롬프트 자동 주입
  $(basename "$0") \\
    -team interface 에이전트프롬프트/M0-인터페이스설계.md \\
    -team infra     에이전트프롬프트/M0-인프라구성.md \\
    -team fe        에이전트프롬프트/M0-프론트엔드.md

Helper (생성 후 .claude-agent/team):
  team assign 1 "시장조사" "경쟁사 분석해줘"   # 업무 배정 + 타이틀 표시
  team assign interface "M0 구현" "proto 작성해줘"
  team scale 5                                  # 3명 → 5명 동적 확장
  team send 1 "진행 상태 보고해줘"
  team status
EOF
}

# ── 모델 감지 + 표시명 변환 ──────────────────────────────────
shorten_model() {
  case "$1" in
    claude-opus-4-7*|claude-opus-4*)      echo "Opus 4.7" ;;
    claude-sonnet-4-6*|claude-sonnet-4*)  echo "Sonnet 4.6" ;;
    claude-haiku-4-5*|claude-haiku-4*)    echo "Haiku 4.5" ;;
    opus)   echo "Opus 4.7" ;;
    sonnet) echo "Sonnet 4.6" ;;
    haiku)  echo "Haiku 4.5" ;;
    "")     echo "Sonnet 4.6" ;;
    *)      echo "$1" ;;
  esac
}

detect_model() {
  local m=""
  # 1. 환경변수 우선
  m="${ANTHROPIC_MODEL:-}"
  # 2. ~/.claude/settings.json
  if [[ -z "$m" && -f "$HOME/.claude/settings.json" ]]; then
    if command -v jq >/dev/null 2>&1; then
      m=$(jq -r '.model // empty' "$HOME/.claude/settings.json" 2>/dev/null || echo "")
    else
      m=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.claude/settings.json" \
          | sed 's/.*"model"[^"]*"\([^"]*\)".*/\1/' | head -1 || echo "")
    fi
  fi
  echo "${m:-sonnet}"
}

# ── 인자 파싱 ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -mode)
      MODE="${2:-}"; shift 2
      [[ "$MODE" == "agentteams" || "$MODE" == "subagent" ]] || {
        echo "Error: -mode 는 agentteams 또는 subagent" >&2; exit 1
      }
      ;;
    -model)
      MODEL_FLAG="${2:-}"; shift 2
      ;;
    -agent)
      AGENT_SIZE="${2:-}"; shift 2
      ;;
    -team)
      [[ -n "${2:-}" ]] || { echo "Error: -team NAME 필요" >&2; exit 1; }
      TEAM_NAMES+=("$2")
      if [[ -n "${3:-}" ]] && [[ "$3" != -* ]]; then
        TEAM_PROMPTS+=("$3"); shift 3
      else
        TEAM_PROMPTS+=(""); shift 2
      fi
      ;;
    -dir)       DIR="${2:-}"; shift 2 ;;
    -session)   SESSION="${2:-}"; shift 2 ;;
    -no-attach) NO_ATTACH=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "알 수 없는 옵션: $1" >&2; usage; exit 1 ;;
  esac
done

# -team 사용 시 자동 subagent 모드
[[ ${#TEAM_NAMES[@]} -gt 0 ]] && MODE="subagent"

# -agent N → 번호 기반 팀 생성
if [[ -n "$AGENT_SIZE" ]]; then
  [[ ${#TEAM_NAMES[@]} -gt 0 ]] && { echo "Error: -agent 와 -team 동시 사용 불가" >&2; exit 1; }
  [[ "$AGENT_SIZE" =~ ^[0-9]+$ ]] && (( AGENT_SIZE >= 1 )) || {
    echo "Error: -agent 최소값 1 (팀리더만)" >&2; exit 1
  }
  (( AGENT_SIZE <= 11 )) || { echo "Error: -agent 최대값 11" >&2; exit 1; }
  for (( i=1; i<=AGENT_SIZE-1; i++ )); do
    TEAM_NAMES+=("agent-$i"); TEAM_PROMPTS+=("")
  done
fi

# 인자 미지정 시 기본값: subagent 모드, 팀리더만
[[ -z "$AGENT_SIZE" && ${#TEAM_NAMES[@]} -eq 0 ]] && AGENT_SIZE=1

TEAM_COUNT=${#TEAM_NAMES[@]}
(( TEAM_COUNT <= 10 )) || { echo "Error: 최대 10팀" >&2; exit 1; }

DIR="${DIR/#\~/$HOME}"
[[ -d "$DIR" ]] || { echo "Error: 디렉토리 없음: $DIR" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd)

# 세션 이름 자동 생성
if [[ -z "$SESSION" ]]; then
  SLUG=$(basename "$DIR" | tr -c '[:alnum:]_-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
  [[ -z "$SLUG" ]] && SLUG="root"
  SESSION="${MODE}-${SLUG}"
fi

command -v claude >/dev/null 2>&1 || echo "Warning: 'claude' 명령을 PATH에서 찾을 수 없음" >&2

# 모델 결정 (명시 > 자동감지 > 기본값)
if [[ -z "$MODEL_FLAG" ]]; then
  MODEL_FLAG=$(detect_model)
fi
MODEL_DISPLAY=$(shorten_model "$MODEL_FLAG")

if [[ "$(id -u)" == "0" ]]; then
  CLAUDE_CMD="claude --permission-mode dontAsk --model $MODEL_FLAG"
else
  CLAUDE_CMD="claude --dangerously-skip-permissions --model $MODEL_FLAG"
fi

# 팀 이름 중복 체크
declare -A _seen
for name in "${TEAM_NAMES[@]}"; do
  [[ -n "${_seen[$name]:-}" ]] && { echo "Error: 팀 이름 중복: $name" >&2; exit 1; }
  _seen["$name"]=1
done

# 모드 레이블
case "$MODE" in
  agentteams) MODE_LABEL="[AgentTeams]" ;;
  subagent)   MODE_LABEL="[Subagent]" ;;
esac

# ── 헬퍼 생성 ─────────────────────────────────────────────────
write_agent_helper() {
  local helper_dir="$DIR/.claude-agent"
  mkdir -p "$helper_dir"

  # config (런타임에 team 스크립트가 읽음)
  cat > "$helper_dir/config" <<CONFEOF
SESSION=$SESSION
DIR=$DIR
MODE=$MODE
MODE_LABEL=$MODE_LABEL
MODEL_FLAG=$MODEL_FLAG
MODEL_DISPLAY=$MODEL_DISPLAY
CONFEOF

  # members (에이전트 이름 목록, scale/add/remove 로 동적 변경)
  printf '%s\n' "${TEAM_NAMES[@]}" > "$helper_dir/members"

  # team 헬퍼 — <<'TEAMEOF': 런타임 변수 처리 (현재 스크립트 변수 미전개)
  cat > "$helper_dir/team" <<'TEAMEOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="$(grep '^SESSION=' "$SCRIPT_DIR/config" | cut -d= -f2-)"
DIR="$(grep '^DIR=' "$SCRIPT_DIR/config" | cut -d= -f2-)"
MODE="$(grep '^MODE=' "$SCRIPT_DIR/config" | cut -d= -f2-)"
MODE_LABEL="$(grep '^MODE_LABEL=' "$SCRIPT_DIR/config" | cut -d= -f2-)"
MODEL_FLAG="$(grep '^MODEL_FLAG=' "$SCRIPT_DIR/config" | cut -d= -f2-)"
MODEL_DISPLAY="$(grep '^MODEL_DISPLAY=' "$SCRIPT_DIR/config" | cut -d= -f2-)"
if [[ "$(id -u)" == "0" ]]; then
  CLAUDE_CMD="claude --permission-mode dontAsk --model $MODEL_FLAG"
else
  CLAUDE_CMD="claude --dangerously-skip-permissions --model $MODEL_FLAG"
fi

# ── 멤버 로드 ────────────────────────────────────────────────
load_members() {
  mapfile -t NAMES < "$SCRIPT_DIR/members" 2>/dev/null || NAMES=()
  AGENT_COUNT=${#NAMES[@]}
}

# ── 유틸 ────────────────────────────────────────────────────
check_session() {
  tmux has-session -t "$SESSION" 2>/dev/null || {
    echo "Error: 세션 '$SESSION' 없음" >&2; exit 1
  }
}

resolve() {
  local arg="$1"
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    (( arg >= 1 && arg <= AGENT_COUNT )) || {
      echo "Error: 번호 범위 1..$AGENT_COUNT" >&2; exit 1
    }
    echo "$arg"; return
  fi
  for i in "${!NAMES[@]}"; do
    [[ "${NAMES[$i]}" == "$arg" ]] && { echo $(( i + 1 )); return; }
  done
  echo "Error: 팀 없음: '$arg'  (사용 가능: ${NAMES[*]:-없음})" >&2
  exit 1
}

send_to_pane() {
  tmux send-keys -t "$1" -l "$2"
  tmux send-keys -t "$1" Enter
}

# 에이전트 타이틀 문자열 생성
#   make_role_title IDX [TASK]
#   [Subagent] Agent-1(Sonnet 4.6)
#   [Subagent] Agent-1(Sonnet 4.6) : M0 구현
make_role_title() {
  local idx="$1" task="${2:-}"
  local base="$MODE_LABEL Agent-$idx($MODEL_DISPLAY)"
  [[ -n "$task" ]] && echo "$base : $task" || echo "$base"
}

set_pane_title() {
  local idx="$1" title="$2"
  tmux set-option -pt "$SESSION:0.$idx" @role "$title" 2>/dev/null || true
}

rebalance_heights() {
  local total="$1"
  (( total == 0 )) && return
  local win_h
  win_h=$(tmux display-message -t "$SESSION:0" -p '#{window_height}' 2>/dev/null || echo 24)
  local each=$(( (win_h - 1) / total ))
  (( each < 3 )) && each=3
  for (( j=1; j<=total; j++ )); do
    tmux resize-pane -t "$SESSION:0.$j" -y "$each" 2>/dev/null || true
  done
}

# ── scale 핵심 로직 ──────────────────────────────────────────
do_scale() {
  local target="$1"
  load_members
  local current="$AGENT_COUNT"

  if (( target > current )); then
    local last_idx="$current"
    for (( i=current+1; i<=target; i++ )); do
      local new_name="agent-$i" new_id split_from
      if (( last_idx == 0 )); then
        split_from="$SESSION:0.0"
        new_id=$(tmux split-window -h -t "$split_from" -c "$DIR" -P -F '#{pane_id}' "$CLAUDE_CMD")
      else
        split_from="$SESSION:0.$last_idx"
        new_id=$(tmux split-window -v -t "$split_from" -c "$DIR" -P -F '#{pane_id}' "$CLAUDE_CMD")
      fi
      local new_idx
      new_idx=$(tmux display-message -pt "$new_id" '#{pane_index}')
      echo "$new_name" >> "$SCRIPT_DIR/members"
      load_members
      tmux set-option -pt "$new_id" @role "$(make_role_title "$new_idx")"
      last_idx="$new_idx"
      echo "  ✓ Agent-$new_idx ($new_name) 추가됨 — claude 실행 중"
    done
  elif (( target < current )); then
    for (( i=current; i>target; i-- )); do
      tmux kill-pane -t "$SESSION:0.$i" 2>/dev/null && echo "  ✗ Agent-$i 제거됨" || true
    done
    { head -n "$target" "$SCRIPT_DIR/members" > "$SCRIPT_DIR/members.tmp" \
      && mv "$SCRIPT_DIR/members.tmp" "$SCRIPT_DIR/members"; } 2>/dev/null || true
  else
    echo "  변경 없음 (현재: $current 명)"; return 0
  fi

  rebalance_heights "$target"
  load_members
  echo "→ 현재 에이전트 수: ${#NAMES[@]}"
}

# ── 명령 함수 ────────────────────────────────────────────────
cmd_list() {
  check_session; load_members
  printf "Mode: %s   Session: %s\n" "$MODE" "$SESSION"
  echo "──────────────────────────────────────────────────────"
  local role
  role=$(tmux display-message -pt "$SESSION:0.0" -p '#{@role}' 2>/dev/null \
    || echo "$MODE_LABEL Team Leader")
  printf "  %2s  %-44s  %s\n" "0" "$role" "$SESSION:0.0"
  for i in "${!NAMES[@]}"; do
    local n=$(( i + 1 ))
    role=$(tmux display-message -pt "$SESSION:0.$n" -p '#{@role}' 2>/dev/null \
      || echo "$(make_role_title "$n")")
    printf "  %2s  %-44s  %s\n" "$n" "$role" "$SESSION:0.$n"
  done
}

cmd_send() {
  check_session; load_members
  local target="${1:?'send <NAME|N> <message> 필요'}"; shift
  local msg="$*"
  [[ -n "$msg" ]] || { echo "Error: message 필요" >&2; exit 1; }
  local idx; idx=$(resolve "$target")
  send_to_pane "$SESSION:0.$idx" "$msg"
  echo "→ [$(make_role_title "$idx")]: $msg"
}

cmd_broadcast() {
  check_session; load_members
  local msg="$*"
  [[ -n "$msg" ]] || { echo "Error: message 필요" >&2; exit 1; }
  for (( i=1; i<=AGENT_COUNT; i++ )); do
    send_to_pane "$SESSION:0.$i" "$msg"
  done
  echo "→ 전체 $AGENT_COUNT 팀: $msg"
}

cmd_view() {
  check_session; load_members
  local target="${1:?'view <NAME|N> 필요'}" lines="${2:-40}"
  local idx; idx=$(resolve "$target")
  echo "── [$(make_role_title "$idx")] 최근 $lines 줄 ──────────────────"
  tmux capture-pane -pt "$SESSION:0.$idx" -S "-$lines"
}

cmd_leader() {
  check_session
  local msg="$*"
  [[ -n "$msg" ]] || { echo "Error: message 필요" >&2; exit 1; }
  send_to_pane "$SESSION:0.0" "$msg"
  echo "→ [$MODE_LABEL Team Leader]: $msg"
}

cmd_status() {
  check_session; load_members
  printf "%-46s %-22s %s\n" "타이틀" "Pane" "프로세스"
  printf "%-46s %-22s %s\n" \
    "──────────────────────────────────────────────" \
    "──────────────────────" "────────"
  local cmd role
  role="$MODE_LABEL Team Leader($MODEL_DISPLAY)"
  cmd=$(tmux display-message -pt "$SESSION:0.0" '#{pane_current_command}' 2>/dev/null || echo "?")
  printf "%-46s %-22s %s\n" "$role" "$SESSION:0.0" "$cmd"
  for i in "${!NAMES[@]}"; do
    local n=$(( i + 1 ))
    role=$(tmux display-message -pt "$SESSION:0.$n" -p '#{@role}' 2>/dev/null \
      || echo "$(make_role_title "$n")")
    cmd=$(tmux display-message -pt "$SESSION:0.$n" '#{pane_current_command}' 2>/dev/null || echo "?")
    printf "%-46s %-22s %s\n" "$role" "$SESSION:0.$n" "$cmd"
  done
}

# assign: 업무 타이틀 설정 + 메시지 전송 (pane 타이틀에 실시간 반영)
cmd_assign() {
  check_session; load_members
  local target="${1:?'assign <NAME|N> <TITLE> [MESSAGE] 필요'}"; shift
  local task_title="${1:?'담당업무 TITLE 필요'}"; shift
  local msg="${*:-}"
  local idx; idx=$(resolve "$target")
  local new_title; new_title="$(make_role_title "$idx" "$task_title")"
  set_pane_title "$idx" "$new_title"
  echo "  타이틀 → $new_title"
  if [[ -n "$msg" ]]; then
    send_to_pane "$SESSION:0.$idx" "$msg"
    echo "  메시지 → $msg"
  fi
}

# title: 타이틀만 변경
cmd_title() {
  check_session; load_members
  local target="${1:?'title <NAME|N> <TITLE> 필요'}"; shift
  local task_title="${*:?'TITLE 필요'}"
  local idx; idx=$(resolve "$target")
  local new_title; new_title="$(make_role_title "$idx" "$task_title")"
  set_pane_title "$idx" "$new_title"
  echo "  타이틀 → $new_title"
}

cmd_scale() {
  check_session
  local target="${1:?'scale <N> 필요 (N = 에이전트 수, 리더 제외)'}"
  [[ "$target" =~ ^[0-9]+$ ]] || { echo "Error: 숫자 필요" >&2; exit 1; }
  (( target >= 1 && target <= 20 )) || { echo "Error: 범위 1..20" >&2; exit 1; }
  do_scale "$target"
}

cmd_add() {
  check_session; load_members
  local custom_name="${1:-}"
  local new_num=$(( AGENT_COUNT + 1 ))
  do_scale "$new_num"
  if [[ -n "$custom_name" && "$custom_name" != "agent-$new_num" ]]; then
    sed -i "$ s/.*/$(printf '%s' "$custom_name" | sed 's/[&/\]/\\&/g')/" "$SCRIPT_DIR/members"
    load_members
    tmux set-option -pt "$SESSION:0.$new_num" @role \
      "$(make_role_title "$new_num")" 2>/dev/null || true
    echo "  → 이름: agent-$new_num → $custom_name"
  fi
}

cmd_remove() {
  check_session; load_members
  (( AGENT_COUNT >= 1 )) || { echo "Error: 제거할 에이전트 없음" >&2; exit 1; }
  do_scale $(( AGENT_COUNT - 1 ))
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Mode: $MODE  Session: $SESSION

Commands:
  list                              현재 팀 목록 + 타이틀
  send <NAME|N> <message>           메시지 전송
  broadcast <message>               전체 전송
  view <NAME|N> [lines]             pane 출력 (기본 40줄)
  leader <message>                  리더에게 메시지
  status                            상태 + 타이틀 전체 조회
  assign <NAME|N> <TITLE> [MSG]     업무 타이틀 설정 + 메시지 전송
  title <NAME|N> <TITLE>            타이틀만 변경
  scale <N>                         에이전트를 N명으로 변경 (pane 자동 추가/제거)
  add [NAME]                        에이전트 1명 추가
  remove                            마지막 에이전트 제거

Examples:
  $(basename "$0") assign 1 "시장조사" "경쟁사 3개사 분석 시작해줘"
  $(basename "$0") assign interface "M0 구현" "proto 파일 작성해줘"
  $(basename "$0") title 2 "DB 설계"
  $(basename "$0") scale 5
  $(basename "$0") add backend
  $(basename "$0") send 1 "진행 상태 보고해줘"
  $(basename "$0") status
EOF
}

# ── 디스패치 ────────────────────────────────────────────────
SUBCMD="${1:-}"; shift || true
case "$SUBCMD" in
  list)      cmd_list ;;
  send)      cmd_send      "$@" ;;
  broadcast) cmd_broadcast "$@" ;;
  view)      cmd_view      "$@" ;;
  leader)    cmd_leader    "$@" ;;
  status)    cmd_status    ;;
  assign)    cmd_assign    "$@" ;;
  title)     cmd_title     "$@" ;;
  scale)     cmd_scale     "$@" ;;
  add)       cmd_add       "$@" ;;
  remove)    cmd_remove    ;;
  ""|-h|--help) usage ;;
  *) echo "Unknown: $SUBCMD" >&2; usage; exit 1 ;;
esac
TEAMEOF
  chmod +x "$helper_dir/team"

  cat > "$helper_dir/README.md" <<READMEEOF
# Claude Agent Team

**모드**: $MODE_LABEL · **세션**: \`$SESSION\`

## 업무 배정 + 타이틀 (pane 타이틀에 실시간 반영)

\`\`\`bash
./.claude-agent/team assign 1 "시장조사" "경쟁사 분석 시작해줘"
./.claude-agent/team assign interface "M0 구현" "proto 파일 작성해줘"
./.claude-agent/team title 2 "DB 설계"   # 타이틀만 변경
\`\`\`

## 동적 스케일 (실행 중 언제든)

\`\`\`bash
./.claude-agent/team scale 5     # N명으로 확장/축소 (pane 자동 추가 + claude 실행)
./.claude-agent/team add backend # 이름 지정 추가
./.claude-agent/team remove      # 마지막 제거
\`\`\`

## 기본 제어

\`\`\`bash
./.claude-agent/team list
./.claude-agent/team send <이름|번호> "메시지"
./.claude-agent/team broadcast "전체 공지"
./.claude-agent/team view <이름|번호> [줄수]
./.claude-agent/team status
\`\`\`

## Pane 타이틀 형식

\`\`\`
$MODE_LABEL Team Leader
$MODE_LABEL Agent-N (이름) · 담당업무
\`\`\`
READMEEOF
}

# ── 세션 재생성 ───────────────────────────────────────────────
if [[ -n "${TMUX:-}" ]]; then
  CURRENT_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "")
  [[ "$CURRENT_SESSION" == "$SESSION" ]] && {
    echo "Error: 현재 세션 '$SESSION' 재생성 불가. -session 으로 다른 이름 지정." >&2
    exit 1
  }
fi
tmux kill-session -t "$SESSION" 2>/dev/null || true

tmux new-session -d -s "$SESSION" -n main -c "$DIR" "$CLAUDE_CMD"
tmux set-option -g history-limit 50000 >/dev/null 2>&1 || true

# ── 스타일링 ─────────────────────────────────────────────────
tmux set-option -t "$SESSION" mouse on
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-lines heavy
tmux set-option -t "$SESSION" pane-border-style "fg=colour39"
tmux set-option -t "$SESSION" pane-active-border-style "fg=colour39,bold"
tmux set-option -t "$SESSION" pane-border-format \
  '#{?pane_active,#[fg=colour15#,bg=colour27#,bold] ━━ #{@role} ━━ ,#[fg=colour39#,bg=default]  #{@role}  }'

tmux bind-key -T root WheelUpPane \
  if-shell -F -t = "#{pane_in_mode}" "send-keys -M" "copy-mode -eu"
tmux bind-key -T copy-mode    WheelUpPane   send-keys -X -N 5 scroll-up
tmux bind-key -T copy-mode    WheelDownPane send-keys -X -N 5 scroll-down
tmux bind-key -T copy-mode-vi WheelUpPane   send-keys -X -N 5 scroll-up
tmux bind-key -T copy-mode-vi WheelDownPane send-keys -X -N 5 scroll-down

# ── Pane 구성 ─────────────────────────────────────────────────
LEADER=$(tmux display-message -t "$SESSION:main" -p '#{pane_id}')
tmux set-option -pt "$LEADER" @role "$MODE_LABEL Team Leader($MODEL_DISPLAY)"

PANE_IDS=()
PREV="$LEADER"
for i in "${!TEAM_NAMES[@]}"; do
  n=$(( i + 1 ))
  if (( i == 0 )); then
    PANE_ID=$(tmux split-window -h -t "$LEADER" -c "$DIR" -P -F '#{pane_id}' "$CLAUDE_CMD")
  else
    PANE_ID=$(tmux split-window -v -t "$PREV" -c "$DIR" -P -F '#{pane_id}' "$CLAUDE_CMD")
  fi
  # 초기 타이틀: [Mode] Agent-N(Model)
  tmux set-option -pt "$PANE_ID" @role "$MODE_LABEL Agent-$n($MODEL_DISPLAY)"
  PANE_IDS+=("$PANE_ID")
  PREV="$PANE_ID"
done

# 크기 조정
W_WIDTH=$(tmux display-message -t "$LEADER" -p '#{window_width}')
tmux resize-pane -t "$LEADER" -x $(( W_WIDTH / 2 ))
if (( TEAM_COUNT > 1 )); then
  W_HEIGHT=$(tmux display-message -t "$LEADER" -p '#{window_height}')
  EACH=$(( (W_HEIGHT - 1) / TEAM_COUNT ))
  (( EACH < 3 )) && EACH=3
  for pid in "${PANE_IDS[@]}"; do
    tmux resize-pane -t "$pid" -y "$EACH" 2>/dev/null || true
  done
fi
tmux select-pane -t "$LEADER"

# ── 헬퍼 생성 ─────────────────────────────────────────────────
write_agent_helper

# ── 초기 프롬프트 주입 (에이전트에 명시적으로 지정된 경우에만) ──
INJECT_NEEDED=0
for prompt in "${TEAM_PROMPTS[@]}"; do [[ -n "$prompt" ]] && INJECT_NEEDED=1; done

if (( INJECT_NEEDED )); then
  (
    sleep 4
    for i in "${!TEAM_NAMES[@]}"; do
      prompt="${TEAM_PROMPTS[$i]}"
      [[ -z "$prompt" ]] && continue
      pane_id="${PANE_IDS[$i]}"
      if [[ -f "$prompt" ]]; then
        prompt_text="$(cat "$prompt")"
      else
        prompt_text="$prompt"
      fi
      tmux send-keys -t "$pane_id" -l "$prompt_text"
      tmux send-keys -t "$pane_id" Enter
    done
  ) &
fi

# ── 완료 안내 ─────────────────────────────────────────────────
cat <<BANNER >&2

✓ Claude Agent Team 준비 완료
  모드:    $MODE_LABEL
  세션:    $SESSION
  구성:    $( (( TEAM_COUNT == 0 )) && echo "Team Leader만" || echo "Team Leader + Agent ${TEAM_COUNT}명" )
  팀 매핑:
$(for i in "${!TEAM_NAMES[@]}"; do
  n=$(( i + 1 ))
  if [[ "${TEAM_NAMES[$i]}" == "agent-$n" ]]; then
    echo "    Agent-$n"
  else
    echo "    Agent-$n → ${TEAM_NAMES[$i]}"
  fi
done)
  헬퍼:    ./.claude-agent/team

  주요 명령:
    ./.claude-agent/team assign 1 "담당업무" "작업 지시"
    ./.claude-agent/team scale 5
    ./.claude-agent/team status

BANNER
if (( INJECT_NEEDED )); then
  echo "  초기 프롬프트: 4초 후 각 Agent pane에 자동 주입" >&2
  echo "" >&2
fi

# ── Attach / Switch ───────────────────────────────────────────
if (( NO_ATTACH )); then
  cat <<HINT >&2
✓ 세션 '$SESSION' 생성 완료 (attach 생략)
  tmux attach -t $SESSION
  tmux switch-client -t $SESSION
HINT
  exit 0
fi

if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$SESSION"
elif [[ -t 1 ]]; then
  tmux attach-session -t "$SESSION"
else
  tmux switch-client -t "$SESSION" 2>/dev/null || true
fi
