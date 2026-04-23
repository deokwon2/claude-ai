사용자의 요청을 분석하여 claude-agent.sh를 자동으로 실행합니다.

## 스크립트 위치 결정

다음 순서로 claude-agent.sh를 탐색하세요:
1. 환경변수 `$CLAUDE_AGENT_SCRIPT` 가 설정된 경우 그 경로
2. `command -v claude-agent.sh` 로 PATH 탐색
3. `~/bin/claude-agent.sh` 존재 여부 확인

없으면 "claude-agent.sh를 찾을 수 없습니다. INSTALL.md를 참고하세요." 안내 후 중단.

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
```bash
SCRIPT="${CLAUDE_AGENT_SCRIPT:-$(command -v claude-agent.sh 2>/dev/null || echo "$HOME/bin/claude-agent.sh")}"
OUT=$(bash "$SCRIPT" -no-attach [파싱된 옵션들] 2>&1)
echo "$OUT"
SESSION=$(echo "$OUT" | grep -oP "(?<=세션 ')[^']+" | tail -1)
```

**2단계 — 세션 전환:**
```bash
tmux switch-client -t "$SESSION" 2>/dev/null || tmux attach-session -t "$SESSION"
```

두 단계 모두 Bash 툴로 실행하세요. 실행 후 세션 이름과 헬퍼 명령어를 안내하세요.

## 예시 변환

| 사용자 요청 | 실행 명령 |
|---|---|
| "에이전트 3개 서브에이전트로" | `bash "$SCRIPT" -agent 3` |
| "interface, infra, fe 팀으로 구성" | `bash "$SCRIPT" -team interface -team infra -team fe` |
| "에이전트팀 4명" | `bash "$SCRIPT" -mode agentteams -agent 4` |
| "opus로 backend, frontend 2팀" | `bash "$SCRIPT" -model opus -team backend -team frontend` |
