# tmux-layout 가이드

Leader + N Agents 형태의 tmux 레이아웃을 한 줄로 생성하는 통합 스크립트.
**기본 레이아웃(빈 셸)과 Claude Code 연계(자동 `claude` 실행)를 옵션으로 모두 처리**하며,
프로젝트나 작업 디렉토리에 종속되지 않는다.

구성 파일:
- `tmux-layout.sh` — 통합 스크립트 (단독 실행, `~/.tmux.conf` 불필요)
- `tmux.conf` *(선택)* — 시스템 전역 tmux 테마를 같은 스타일로 맞추고 싶을 때만

---

## 1. 설치

이 디렉토리에 `tmux-layout.sh`가 있다고 가정한다. 실행 권한 부여:

```bash
chmod +x ./tmux-layout.sh
```

현재 디렉토리에서 호출:

```bash
./tmux-layout.sh --help
```

어디서든 호출하고 싶다면 PATH에 심볼릭 링크:

```bash
ln -sf "$PWD/tmux-layout.sh" ~/bin/tmux-layout.sh
# 또는 시스템 전역:
# sudo ln -sf "$PWD/tmux-layout.sh" /usr/local/bin/tmux-layout.sh
```

---

## 2. 사용법

```
./tmux-layout.sh [OPTIONS]

Options:
  -agent N          Leader(좌측) + Agent N개(우측 세로 스택), N: 0..10   (기본: 0)
  -claude           모든 pane에서 'claude' 명령을 자동 실행
  -dir PATH         모든 pane의 작업 디렉토리                           (기본: 현재 디렉토리)
  -session NAME     tmux 세션 이름                                        (기본: layout)
  -h, --help        도움말
```

> PATH에 링크했다면 `./` 없이 `tmux-layout.sh`로 호출 가능.

옵션은 **독립적으로 조합 가능**하다. 필요한 것만 켠다.

---

## 3. 시나리오별 예시

### 3.1 기본 레이아웃 — Leader만

```bash
./tmux-layout.sh
```

- pane 1개(Leader)
- 현재 디렉토리에서 기본 셸
- 세션명 `layout`

### 3.2 Agent 레이아웃 (빈 셸)

```bash
./tmux-layout.sh -agent 3
```

- Leader + Agent 3개
- 각 pane은 기본 셸
- tmux 레이아웃 테스트/일반 병렬 작업용

### 3.3 Claude 연계 — Leader + Agents에 claude 자동 실행

```bash
./tmux-layout.sh -agent 3 -claude
```

- 모든 pane에서 즉시 `claude` 명령 실행
- 현재 디렉토리 컨텍스트로 열림

### 3.4 특정 프로젝트 디렉토리에서 Claude 세션

```bash
./tmux-layout.sh -agent 3 -claude -dir ~/projects/my-app
./tmux-layout.sh -agent 3 -claude -dir /abs/path/to/project
./tmux-layout.sh -agent 3 -claude -dir .           # 현재 디렉토리 명시
```

### 3.5 여러 프로젝트 동시 작업 — 세션 이름 분리

```bash
./tmux-layout.sh -agent 3 -claude -dir ~/projects/app-a -session app-a
./tmux-layout.sh -agent 3 -claude -dir ~/projects/app-b -session app-b

# 전환
tmux switch-client -t app-a
tmux switch-client -t app-b
```

### 3.6 Leader만 Claude로 (Agent 없이)

```bash
./tmux-layout.sh -claude -dir ~/projects/my-app
```

단독 Claude 세션. Agent가 필요 없는 단일 작업용.

---

## 4. 레이아웃 구조

```
┌──────────────┬──────────────┐
│              │  Agent-1     │
│              ├──────────────┤
│  Leader      │  Agent-2     │
│              ├──────────────┤
│              │  Agent-3     │
└──────────────┴──────────────┘
```

- Leader: 윈도우 **왼쪽 절반**
- Agent-1..N: 오른쪽 절반을 **세로로 균등 분배**
- 각 pane 상단에 역할 라벨 (활성 pane은 `━━ Agent-1 ━━` 역상 블록으로 강조)

---

## 5. 스타일 / 라벨 메커니즘

- **자체 완결**: 스크립트가 세션 스코프로 `pane-border-*` 옵션을 직접 설정 → `~/.tmux.conf`가 없어도 동작.
- **색상 팔레트**: 파란 테마 — 테두리 `colour39`, 활성 라벨 배경 `colour27`, 비활성 라벨 `colour39` on default.
- **활성창 강조**: tmux 3.2a는 pane별 선 두께 지정 불가 → 활성 pane 상단 라벨을 `━━ Role ━━` 역상 블록으로 렌더해 두께감 대체.
- **라벨 소스**: pane별 사용자 옵션 `@role` (Leader / Agent-N). `claude`가 쓰는 `pane_title` (OSC 2)과 충돌 없음.

라벨 이름을 실행 중에 바꾸고 싶다면:

```bash
tmux set-option -pt layout:0.1 @role "Reviewer"   # Agent-1 → Reviewer
```

---

## 6. 이미 띄운 세션에 같은 스타일 적용 (one-off)

스크립트로 만들지 않은 임의의 세션 `$SESSION`에 이 테마만 입히려면:

```bash
SESSION=mywork   # 대상 세션

tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-lines heavy
tmux set-option -t "$SESSION" pane-border-style "fg=colour39"
tmux set-option -t "$SESSION" pane-active-border-style "fg=colour39,bold"
tmux set-option -t "$SESSION" pane-border-format \
  '#{?pane_active,#[fg=colour15#,bg=colour27#,bold] ━━ #{@role} ━━ ,#[fg=colour39#,bg=default] #{@role} }'

# 역할 라벨 (실제 pane 수만큼)
tmux set-option -pt "$SESSION:0.0" @role "Leader"
PANES=$(tmux list-panes -t "$SESSION:0" -F '#{pane_index}' | wc -l)
for ((i=1; i<PANES; i++)); do
  tmux set-option -pt "$SESSION:0.$i" @role "Agent-$i"
done
```

---

## 7. (선택) 전역 `~/.tmux.conf`

`tmux-layout.sh`로 만든 세션은 자체 스타일링을 하므로 `~/.tmux.conf`가 **필요 없다.**
다만 **다른 tmux 세션들(직접 열거나 다른 도구가 만드는)도 같은 파란 테마로 맞추고 싶다면** 현재 디렉토리의 `tmux.conf`를 홈으로 복사:

```bash
cp ./tmux.conf ~/.tmux.conf
tmux source-file ~/.tmux.conf
```

---

## 8. 트러블슈팅

- **`claude` 명령을 찾을 수 없음**: `-claude` 사용 시 pane이 즉시 종료됨. `which claude`로 확인 후 PATH에 추가.
- **같은 세션 이름이 이미 있음**: 기존 세션은 `kill` 후 재생성된다. 진행 중 작업 주의. 보존하려면 `-session` 으로 다른 이름 사용.
- **pane 크기가 어색함**: 터미널이 너무 좁으면 분할 실패 또는 깨짐. 터미널 크기를 충분히(최소 120×30 권장) 키우고 다시 실행.
- **tmux 안에서 실행 시**: 자동으로 `switch-client`되어 새 세션으로 전환된다. 원래 세션은 그대로 살아있다.
