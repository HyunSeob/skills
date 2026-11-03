---
name: terminal-recording
description: "터미널 프로그램(Claude Code CLI · Codex CLI 등)을 전용 Ghostty 창에서 자동으로 녹화한다. tmux가 사람 속도로 프롬프트를 치고 답이 끝나길 기다리며, ScreenCaptureKit이 커서 없이 그 창만 찍는다. 에이전트 작업 화면 · CLI 데모 영상이 필요하거나, 자동 압축 같은 특정 순간을 찍거나, 테이크를 다시 찍을 때 쓴다."
---

# terminal-recording

Ghostty 창 하나를 녹화 전용으로 띄우고, 그 안의 프로그램을 tmux로 조작하면서 그 창만 녹화한다.
`SKILL_DIR`는 이 스킬 폴더의 절대 경로다.

| 스크립트 | 하는 일 |
|---|---|
| `scripts/window.sh [x y w h]` | 녹화 창을 띄운다: tmux 세션 `rec`, 창 제목 `REC-TERM`, 위치 · 크기 지정. 기본은 1460×821pt(16:9), 주 화면 가운데. `window.sh close`로 정리 |
| `scripts/record.py <take.json> --name take1` | 그 창에서 프로그램을 시작하고, 단계마다 입력하고, 답을 기다리며, 창을 녹화한다 |
| `scripts/wincap.swift` | 창 하나만 녹화 (ScreenCaptureKit, 커서 없음, 30fps, 제목으로 창을 찾음). `record.py`가 처음 쓸 때 `scripts/bin/wincap`으로 컴파일한다 |

예시 테이크: [examples/claude-code-take.json](examples/claude-code-take.json).

## 처음 한 번 (사용자가 직접 한다)

- **화면 녹화 권한**: 녹화를 실행하는 앱(터미널 · 에이전트 앱)에 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음.
- **손쉬운 사용 권한**: 같은 앱에 개인정보 보호 및 보안 → 손쉬운 사용. `window.sh`가 System Events로 창을 옮기고 크기를 바꾼다. 없으면 창이 macOS가 정한 곳에 뜬다.
- `brew install tmux`, [Ghostty](https://ghostty.org), Xcode 명령줄 도구(`swiftc`).
- Claude Code를 찍을 때: 녹화 전용 설정 폴더에 한 번 로그인한다. `CLAUDE_CONFIG_DIR=~/.claude-recording claude` → 로그인 → `/exit`. 에이전트는 로그인 정보를 입력하지 않는다.

## 순서

1. 프로젝트 옆에 `take.json`을 쓴다 (형식은 `record.py` 머리 주석): `workdir`, `command`, `ready`(입력을 기다리는 중임을 뜻하는 정규식), `busy`(작업 중에 보이는 정규식), 선택 `watch`(시각과 함께 기록할 정규식), `out`, `steps`(`type` / `wait_idle` / `pause` / `keys`).
2. `SKILL_DIR/scripts/window.sh`로 창을 띄운다. 화면이 여러 개면 `x y w h`로 자리를 준다. 옮길 화면보다 창이 크면 macOS가 줄여 버리니 그 화면 폭 안으로 잡는다.
3. 사용자에게 **찍는 동안 창을 가리지 말라고** 말한 뒤(아래 함정), `python3 SKILL_DIR/scripts/record.py <take.json> --name take1`을 백그라운드로 돌리고 `<out>/take1.log`를 지켜본다.
4. 확인: 로그에 찍힌 시각에서 프레임을 뽑아(`ffmpeg -ss <t> -i take1.mov -frames:v 1 f.png`) 직접 본다. 계정 이름이 든 경로 · 알림 같은 개인 정보가 보이면 편집에서 가린다.

`out`에 남는 것: `take1.mov`(기본 창 크기에서 2920×1642), `take1.log`(`SENT`, `IDLE`, `COMPACT START/END` 같은 watch 기록), `take1.final.txt`(끝난 뒤 화면 전체 글자).

## Claude Code 테이크

```
env CLAUDE_CONFIG_DIR=$HOME/.claude-recording CLAUDE_CODE_HIDE_CWD=1 ENABLE_CLAUDEAI_MCP_SERVERS=false claude --model haiku
```

- `~/.claude-recording`은 깨끗한 설정 폴더다. 평소 쓰는 플러그인 · MCP 서버 · 설정이 화면에 안 나온다.
  그 안의 `settings.json` 예: [examples/claude-recording-settings.json](examples/claude-recording-settings.json).
  `spinnerTipsEnabled: false`, `showTurnDuration: false`, `theme: dark`, `permissions.deny`에 `Agent` · `Task`(하위 에이전트 대신 본 대화에서 읽게) · `Bash`(셸 명령이 계정 이름이 든 임시 경로를 찍었다).
- `ENABLE_CLAUDEAI_MCP_SERVERS=false`는 "N MCP servers need authentication" 알림을, `CLAUDE_CODE_HIDE_CWD=1`은 로고 옆 폴더 경로를 숨긴다.
- 계정 스킬은 그래도 불러온다. `/context`가 스킬 이름을 다 보여 주므로 `/context`는 찍지 않는다. 필요하면 화면 밖에서 숫자를 받아 그림으로 다시 만든다.
- 자동 압축을 원하는 때 보기: `CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000`(최솟값)을 더하면 약 67k 사용에서 압축된다. 압축 뒤 최근 파일을 다시 읽어 한 세션에서 2~3번 압축될 수 있으니, 원하는 순간이 한 번만 오게 작업 크기를 맞춘다.
- 화면 글자(찍을 때 버전 기준, 버전마다 바뀔 수 있다): 작업 중 `esc to interrupt`, 입력 대기 `shift+tab`, 하단 `N% until auto-compact`, `Compacting conversation…`, `Conversation compacted`.
- 모델은 사용자가 따로 원하지 않으면 가장 싼 모델(`--model haiku`)로 찍는다.
- Claude가 읽을 가짜 자료는 시드를 고정한 스크립트로 만든다. 모델은 틀로 찍어 낸 자료(반복 문장, 있을 수 없는 날짜, 들쭉날쭉한 숫자)를 알아채고 답에서 지적하며, 그게 화면에 나온다. 자료끼리 앞뒤가 맞게 만든다.

## 함정

- **가려진 Ghostty 창은 다시 그리지 않는다.** 그 위에 뭔가 있는 동안 녹화가 멈춘다. `record.py`가 시작할 때 창을 앞으로 올린다.
- **Ghostty에 `-e tmux attach -t rec`를 넘기면 창이 하나 더 생긴다**(빈 `tmux` 세션 `1`, `2`…). `window.sh`는 `--command=<스크립트>`를 쓴다. 창은 크기가 아니라 제목으로 찾는다.
- Ghostty 프로세스가 창보다 오래 살아남을 수 있다. `window.sh`는 프로세스가 아니라 tmux에 붙은 클라이언트가 있는지 보고, 없으면 다시 띄운다.
- `screencapture -v`는 커서가 찍히고 영역 계산이 필요하며, ffmpeg avfoundation은 멈춘 적이 있다. `wincap`을 쓴다. 명령줄에서 ScreenCaptureKit을 쓰려면 `NSApplication.shared`를 먼저 초기화해야 한다(`wincap.swift`에 있음).
- 입력창에 남은 글자가 첫 프롬프트 앞에 붙는다. `record.py`가 입력 전에 `C-u`를 보낸다.
- 맨 `zsh -f`에는 UTF-8 로캘이 없어 한글 입력이 바이트로 깨진다. 맨 셸을 찍을 때는 `command`에 `LANG=ko_KR.UTF-8`을 넣는다. Claude Code 자체는 괜찮다.
- 웹페이지는 이 스킬이 아니라 브라우저 녹화 도구로 찍는다.
