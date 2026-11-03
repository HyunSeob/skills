# terminal-recording

Claude Code · Codex 같은 터미널 프로그램의 작업 화면을 자동으로 녹화하는 스킬입니다.

에이전트에게 "이 작업을 하는 Claude Code 화면을 찍어 줘"라고 하면, 녹화 전용 터미널 창을 띄우고
프롬프트를 사람 속도로 입력하고, 답이 끝날 때까지 기다리며, **그 창만 커서 없이** 녹화합니다.
몇 번이고 같은 테이크를 다시 찍을 수 있고, 로그에 "언제 무엇을 보냈고 언제 끝났는지"가 시각과 함께 남아 편집이 쉽습니다.

## 필요한 것

- macOS, [Ghostty](https://ghostty.org), `tmux`(`brew install tmux`), Xcode 명령줄 도구(`swiftc`), Python 3
- 녹화를 실행하는 앱(터미널 · 에이전트 앱)에 **화면 녹화**와 **손쉬운 사용** 권한
- 녹화 중에는 그 창을 다른 창으로 가리지 않기 (가리면 화면이 멈춥니다)

## 쓰는 법

```
"terminal-recording 스킬로 ~/demo-project에서 Claude Code가 README를 요약하는 화면을 찍어 줘"
```

직접 돌릴 때:

```bash
scripts/window.sh                                       # 녹화 창 띄우기
python3 scripts/record.py examples/claude-code-take.json --name take1
scripts/window.sh close                                 # 정리
```

결과: `takes/take1.mov`(영상), `take1.log`(시각 기록), `take1.final.txt`(마지막 화면 글자).
테이크 형식과 Claude Code를 깨끗하게 찍는 설정(개인 플러그인 · 경로 숨기기)은 [SKILL.md](SKILL.md)에 있습니다.

## 들어 있는 것

```
SKILL.md                              에이전트가 따라가는 순서 · 함정
scripts/window.sh                     녹화 전용 Ghostty + tmux 창
scripts/record.py                     테이크 실행 · 입력 · 대기 · 녹화
scripts/wincap.swift                  창 하나만 녹화 (ScreenCaptureKit)
examples/claude-code-take.json        테이크 예시
examples/claude-recording-settings.json  녹화 전용 Claude Code 설정 예시
```
