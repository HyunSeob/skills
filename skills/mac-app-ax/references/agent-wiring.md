# MCP · 스킬로 에이전트에 연결

틀: [templates/mcp_server.py](../templates/mcp_server.py).

## MCP 서버

- 헬퍼 함수 하나 = MCP 도구 하나. 이름은 `<앱>_ax_<동작>` (예: `notes_ax_read`, `notes_ax_add`).
- 도구 설명(docstring)에 쓰는 것: 무엇을 바꾸는지 · 안 바꾸는지, 읽는 범위의 한계, 결과 상태의 뜻,
  `outcome_unknown`일 때 할 일(같은 ID로 결과 조회, 재시도 금지).
- 도구 주석: 읽기는 `readOnlyHint=True`, 화면 이동은 `idempotentHint=True`, 되돌릴 수 없는 동작은 `readOnlyHint=False, idempotentHint=False`.
- 서버 `instructions`에 "이 앱은 이 도구로만. 스크린샷 · 좌표 클릭으로 대체하지 말 것"을 적는다.

Claude Code에 붙이기:

```bash
claude mcp add myapp-ax -- /절대경로/.venv/bin/python /절대경로/mcp_server.py
```

다른 MCP 클라이언트 설정 예:

```json
{ "mcpServers": { "myapp-ax": { "command": "/절대경로/.venv/bin/python", "args": ["/절대경로/mcp_server.py"] } } }
```

## 앱 전용 스킬

헬퍼 저장소 안에 `skills/<앱>-ax/SKILL.md`를 둔다. 담을 것:

- 언제 쓰나 (설명 줄에 앱 이름 · 별칭을 넣어 에이전트가 찾게).
- 쓸 도구 목록과 고르는 법 (여러 대상은 일괄 도구).
- 결과를 읽는 법: `items`는 보이는 범위, `hasMore=false`도 전체의 끝이 아님, 모르는 값은 추측하지 않음.
- 되돌릴 수 없는 동작은 사용자가 명시적으로 요청한 대상 · 내용에만, 요청 ID 규칙.
- MCP가 연결되지 않았을 때 쓰는 CLI 경로 (사용자 텍스트는 JSON 파일로).

카카오톡 사례: [`kakaotalk-ax`의 스킬](https://github.com/HyunSeob/kakaotalk-ax/tree/main/skills/kakaotalk-ax).
