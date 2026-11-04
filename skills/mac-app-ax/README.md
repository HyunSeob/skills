# mac-app-ax

브라우저가 아닌 맥 앱을 접근성 트리(AX)로 읽고 조작하는 헬퍼를 만들어 에이전트에 연결하는 스킬입니다.

에이전트가 맥 앱을 쓸 때 스크린샷을 보고 좌표를 누르면 느리고 자주 틀립니다.
맥 앱 대부분은 화면 요소를 **접근성 트리**(손쉬운 사용 기능이 읽는 버튼 · 입력창 · 목록 구조)로 내보냅니다.
이 스킬은 그 트리를 직접 읽어서, 자주 하는 동작을 **네이티브 헬퍼 함수 하나**로 묶고,
그 함수를 MCP 도구나 스킬로 에이전트에 붙이는 과정을 순서대로 안내합니다.

에이전트에게 앱 이름과 자동화할 일만 알려 주면 됩니다.

```
"mac-app-ax 스킬로 <앱 이름>에서 <자주 하는 일>을 하는 헬퍼를 만들어 줘"
```

## 순서

1. **권한**: 실행하는 터미널 · 에이전트 앱에 "손쉬운 사용" 권한을 줍니다
2. **트리 보기**: `scripts/ax_dump.swift`나 Xcode의 Accessibility Inspector로 대상 앱의 요소를 봅니다
3. **헬퍼로 묶기**: 요소 찾기 → 확인 → 동작 → 결과 관찰을 한 번의 호출로 합칩니다
4. **에이전트에 연결**: MCP 서버나 스킬로 그 함수를 도구 하나로 내놓습니다
5. **확인 · 중복 막기**: 동작 뒤 화면을 다시 읽어 확인하고, 요청 ID로 같은 동작이 두 번 실행되지 않게 합니다

자세한 단계와 실제로 막혔던 곳은 [SKILL.md](SKILL.md)와 [references/](references/)에 있습니다.

## 되는 조건

- **macOS 앱이 AX 요소를 내보내야 합니다.** 일반 앱 화면(버튼 · 목록 · 입력창)은 대체로 됩니다.
  게임 · 캔버스에 직접 그리는 화면은 트리가 비어 있을 수 있습니다. 2단계에서 먼저 확인하세요.
- **브라우저 안의 웹페이지는 이 스킬 대신 브라우저 자동화(DOM · Playwright 등)가 더 맞습니다.**
  일렉트론 앱도 트리가 얕게 나오는 경우가 많습니다.
- 앱이 공식 API · CLI · AppleScript(스크립팅 사전)를 제공하면 그쪽을 먼저 쓰세요.
- **앱마다 약관을 확인하세요.** 자동화 프로그램 사용을 금지하는 서비스가 있고, 계정이 제한될 수 있습니다.
  쓰는 앱 · 계정에 대한 책임은 각자에게 있습니다. 다른 사람의 대화 · 정보를 모으는 데 쓰지 마세요.

## 필요한 것

macOS, Xcode 명령줄 도구(`xcode-select --install`, `swiftc`).
헬퍼를 MCP로 붙일 때는 Python 3.10 이상과 `mcp` 패키지. 설치는 [저장소 README](../../README.md#설치)를 보세요.

## 들어 있는 것

```
SKILL.md                     에이전트가 따라가는 순서
references/
  permissions.md             손쉬운 사용 권한
  inspect.md                 트리 덤프 · Accessibility Inspector로 요소 찾기
  helper-design.md           동작을 헬퍼 함수로 묶는 규칙
  verify-and-dedupe.md       다시 읽어 확인 · 요청 ID로 중복 막기
  agent-wiring.md            MCP 서버 · 스킬로 연결
  pitfalls.md                실제로 막혔던 곳
scripts/ax_dump.swift        앱의 AX 트리를 글자 · JSON으로 뽑는 도구
templates/
  helper_action.swift        네이티브 헬퍼 틀 (찾기 · 확인 · 한 번만 누르기)
  operation_journal.py       요청 ID 기록 (같은 요청은 다시 실행하지 않음)
  mcp_server.py              헬퍼를 MCP 도구로 내놓는 틀
agents/openai.yaml           Codex 표시 정보
tests/                       템플릿 단위 테스트
```

## 시험

이 폴더에서:

```bash
python3 -m unittest discover -s tests -v
swiftc -O scripts/ax_dump.swift -o "$TMPDIR/ax_dump" && "$TMPDIR/ax_dump" --list-apps
```
