# Claude Agent Team — 설치 가이드

tmux 기반 Claude Code 멀티 에이전트 환경 구성 가이드.  
팀리더 + 서브에이전트 N명을 tmux 분할 창에서 동시에 운용한다.

---

## 빠른 시작 — 처음 설치 (환경 없음)

### Windows (WSL2)

#### 1단계. WSL 설치

PowerShell(관리자)에서 실행:

```powershell
wsl --install
```

재시작 후 Start 메뉴에서 **Ubuntu** 실행 → 사용자명·비밀번호 설정.

> 이미 WSL이 있다면 Ubuntu 터미널을 열면 된다.

---

#### 2단계. 패키지 업데이트 & tmux 설치

Ubuntu 터미널 (일반 유저, sudo 사용):

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y tmux jq
```

> `tmux`는 sudo(관리자 권한)로 **설치**하고, **실행은 일반 유저**로 한다.  
> root로 로그인하지 않아도 된다.

---

#### 3단계. Node.js & Claude Code 설치

```bash
# Node.js 20.x 설치 (22.x도 가능)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Claude Code 설치
npm install -g @anthropic-ai/claude-code
```

설치 확인:

```bash
node --version    # v20.x.x
claude --version  # 2.x.x
tmux -V           # tmux 3.x
```

---

#### 4단계. agent-tmux.sh 설치

```bash
mkdir -p ~/bin
cp /mnt/d/Project/agent-tmux.sh ~/bin/
chmod +x ~/bin/agent-tmux.sh

# PATH에 등록 (없으면)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

#### 5단계. 실행

```bash
# 일반 유저에서 tmux 시작
tmux

# tmux 창 안에서 claude 실행
claude
```

멀티 에이전트 세션 시작:

```bash
# tmux 창 안에서 실행
bash ~/bin/agent-tmux.sh -agent 3
```

---

### macOS

```bash
brew install tmux jq

# Node.js (없으면)
brew install node

npm install -g @anthropic-ai/claude-code
```

---

### Ubuntu / Debian (Linux 직접 설치)

WSL과 동일하게 2단계부터 진행:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y tmux jq

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
npm install -g @anthropic-ai/claude-code
```

---

## 전제조건 (설치 검증)

| 도구 | 최소 버전 | 확인 명령 |
|---|---|---|
| Claude Code CLI | 2.x | `claude --version` |
| tmux | 3.2a+ | `tmux -V` |
| Node.js | 20.x+ | `node --version` |
| bash | 5.x | `bash --version` |
| jq *(선택)* | 1.6+ | `jq --version` — 모델 자동 감지에 사용 |

---

## 1. 스크립트 설치

### 방법 A — 특정 프로젝트 디렉토리 (권장)

```bash
mkdir -p ~/tools
cp agent-tmux.sh ~/tools/
chmod +x ~/tools/agent-tmux.sh
```

### 방법 B — PATH에 추가 (전역 사용)

```bash
mkdir -p ~/bin
cp agent-tmux.sh ~/bin/
chmod +x ~/bin/agent-tmux.sh

# ~/bin 이 PATH에 없으면 추가 (~/.bashrc 또는 ~/.zshrc)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

PATH에 등록하면 어디서든 `agent-tmux.sh` 직접 호출 가능.

---

## 2. `/agent-tmux` Claude 스킬 설치

Claude Code에서 `/agent-tmux` 명령으로 바로 에이전트 세션을 생성하려면 커스텀 슬래시 커맨드를 등록한다.

```bash
mkdir -p ~/.claude/commands
```

`~/.claude/commands/agent-tmux.md` 파일 생성:

```markdown
사용자의 요청을 분석하여 agent-tmux.sh를 자동으로 실행합니다.

## 스크립트 위치 결정

다음 순서로 agent-tmux.sh를 찾으세요:
1. 환경변수 `$CLAUDE_AGENT_SCRIPT` 가 설정된 경우 그 경로 사용
2. `command -v agent-tmux.sh` 로 PATH 탐색
3. `~/bin/agent-tmux.sh` 존재 여부 확인
4. 없으면 "agent-tmux.sh를 찾을 수 없습니다. INSTALL.md 참고" 안내

## 파싱 규칙

$ARGUMENTS 또는 대화 맥락에서 다음을 파악하세요:

**모드 결정:**
- "서브에이전트", "subagent", "전문화", "위임" → `-mode subagent` (기본값)
- "에이전트팀", "agentteams", "자율", "협업" → `-mode agentteams`
- 팀 이름이 명시되면 자동으로 subagent 모드

**에이전트 수:**
- "N개", "N명", "N팀" → `-agent N` (이름 미지정 시)
- 이름이 명시된 경우 → `-team 이름1 -team 이름2 ...`

**모델:**
- 명시 없으면 생략 (스크립트가 ~/.claude/settings.json 에서 자동 감지)
- "opus" → `-model opus`, "haiku" → `-model haiku`

## 실행

파싱 결과를 바탕으로 아래 두 단계를 순서대로 실행하세요:

**1단계 — 스크립트 위치 확인 후 실행 (`-no-attach`):**
\`\`\`bash
SCRIPT="${CLAUDE_AGENT_SCRIPT:-$(command -v agent-tmux.sh 2>/dev/null || echo "$HOME/bin/agent-tmux.sh")}"
OUT=$(bash "$SCRIPT" -no-attach [파싱된 옵션들] 2>&1)
echo "$OUT"
SESSION=$(echo "$OUT" | grep -oP "(?<=세션 ')[^']+" | tail -1)
\`\`\`

**2단계 — 세션 전환:**
\`\`\`bash
tmux switch-client -t "$SESSION" 2>/dev/null || tmux attach-session -t "$SESSION"
\`\`\`

두 단계 모두 Bash 툴로 실행하세요. 실행 후 세션 이름과 헬퍼 명령어를 안내하세요.

## 예시 변환

| 사용자 요청 | 실행 명령 |
|---|---|
| "에이전트 3개 서브에이전트로" | `bash "$SCRIPT" -agent 3` |
| "interface, infra, fe 팀으로 구성" | `bash "$SCRIPT" -team interface -team infra -team fe` |
| "에이전트팀 4명" | `bash "$SCRIPT" -mode agentteams -agent 4` |
| "opus로 backend, frontend 2팀" | `bash "$SCRIPT" -model opus -team backend -team frontend` |
```

**환경변수로 경로 고정하고 싶을 때 (선택):**
```bash
# ~/.bashrc 또는 ~/.zshrc 에 추가
export CLAUDE_AGENT_SCRIPT="$HOME/tools/agent-tmux.sh"
```

---

## 3. CLAUDE.md 자동 트리거 설정

Claude Code가 에이전트 관련 표현을 감지하면 자동으로 스크립트를 실행하도록 한다.  
프로젝트 루트 또는 `~/CLAUDE.md` (글로벌) 에 추가:

```markdown
## Claude Agent 자동화

사용자가 에이전트 구성을 요청하면 agent-tmux.sh를 자동으로 실행한다.
스크립트 위치: $CLAUDE_AGENT_SCRIPT 환경변수 또는 ~/bin/agent-tmux.sh

### 인식 트리거

다음 표현이 포함되면 에이전트 구성 요청으로 간주한다:
- "에이전트 N개", "에이전트 N명", "N명으로 구성", "팀 구성"
- "서브에이전트", "에이전트팀", "agentteams", "subagent"
- "에이전트 추가", "팀 추가", "1명 더", "N명 더"

### 파싱 규칙

**모드:**
- "서브에이전트", "subagent" → `-mode subagent` (기본)
- "에이전트팀", "agentteams", "자율" → `-mode agentteams`

**에이전트 수:**
- 이름 없이 숫자만 → `-agent N`
- 이름 명시 → `-team 이름1 -team 이름2 ...`
```

---

## 4. 동작 확인

```bash
# 1. 스크립트 직접 실행 (팀리더만, attach 없이)
bash ~/bin/agent-tmux.sh -agent 2 -no-attach

# 2. 세션 생성 확인
tmux list-sessions

# 3. 세션 접속
tmux attach -t subagent-<디렉토리명>

# 4. 헬퍼 확인
./.claude-agent/team status

# 5. Claude Code 에서 슬래시 커맨드 테스트
# Claude Code 실행 후: /agents 에이전트 3명
```

---

## 5. 디렉토리 구조 (실행 후)

```
<작업 디렉토리>/
└── .claude-agent/          # 세션별 런타임 데이터 (git ignore 권장)
    ├── config              # SESSION, MODE, MODEL 등
    ├── members             # 에이전트 이름 목록
    ├── team                # 헬퍼 스크립트 (자동 생성)
    └── README.md           # 빠른 참조 (자동 생성)
```

`.gitignore` 에 추가:
```
.claude-agent/
```

---

## 6. 주요 헬퍼 명령 참조

```bash
# 팀 현황
./.claude-agent/team status
./.claude-agent/team list

# 업무 배정 (타이틀에 [진행중] 자동 표시)
./.claude-agent/team assign 1 "API 설계" "OpenAPI spec 작성해줘"
./.claude-agent/team assign interface "화면 구현" "Login 페이지 만들어줘"

# 완료 처리 (타이틀 → ": 완료")
./.claude-agent/team done 1
./.claude-agent/team done interface

# 메시지 전송
./.claude-agent/team send 1 "진행 상태 보고해줘"
./.claude-agent/team broadcast "전체 공지사항"
./.claude-agent/team leader "리더에게 메시지"

# 동적 스케일
./.claude-agent/team scale 5    # 5명으로 변경
./.claude-agent/team add        # 1명 추가
./.claude-agent/team remove     # 마지막 제거

# pane 출력 확인
./.claude-agent/team view 1 30
```

---

## 7. 타이틀 형식

| 상황 | 팀리더 | 에이전트 |
|---|---|---|
| 초기 | `[Subagent] Team Leader(Sonnet 4.6)` | `Agent-1(Sonnet 4.6)` |
| 업무 배정 후 | — | `Agent-1(Sonnet 4.6) : API 설계 [진행중]` |
| 완료 | — | `Agent-1(Sonnet 4.6) : 완료` |

모드 라벨(`[Subagent]` / `[AgentTeams]`)은 팀리더 창에만 표시.

---

## 8. 트러블슈팅

**`claude` 명령을 찾을 수 없음**
```bash
which claude          # 위치 확인
echo $PATH            # PATH 확인
# npm global bin이 PATH에 없는 경우:
export PATH="$(npm root -g)/../bin:$PATH"
# 영구 적용:
echo 'export PATH="$(npm root -g)/../bin:$PATH"' >> ~/.bashrc
```

**WSL에서 기본 유저가 root인 경우**
```bash
# Ubuntu에서 일반 유저 생성
sudo adduser myuser
sudo usermod -aG sudo myuser
su - myuser
# 또는 WSL 기본 유저 변경 (PowerShell):
# ubuntu config --default-user myuser
```

**tmux 세션이 이미 존재함**
```bash
tmux kill-session -t subagent-lucida-01   # 기존 세션 종료 후 재실행
# 또는 -session 옵션으로 다른 이름 사용
bash agent-tmux.sh -agent 3 -session mywork
```

**WSL2에서 tmux attach 안 됨**
```bash
# Windows Terminal 또는 wezterm에서 직접 실행
# VS Code 터미널에서는 tmux attach가 제대로 동작하지 않을 수 있음
```

**모델 자동 감지 실패**
```bash
# ~/.claude/settings.json 에 model 필드 추가
echo '{"model": "claude-sonnet-4-6"}' > ~/.claude/settings.json
# 또는 환경변수
export ANTHROPIC_MODEL=claude-sonnet-4-6
```

**Node.js 버전이 낮음 (npm 설치 전 확인)**
```bash
node --version   # v20 미만이면 재설치
# 기존 nodejs 제거 후 nodesource로 재설치
sudo apt remove -y nodejs
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```
