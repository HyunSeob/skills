# 트리 보기 · 요소 찾기

## 도구 두 가지

**`scripts/ax_dump.swift`** (이 스킬): 앱의 AX 트리를 글자나 JSON으로 뽑는다. 에이전트가 직접 읽기 좋다.

```bash
swiftc -O SKILL_DIR/scripts/ax_dump.swift -o "$TMPDIR/ax_dump"
"$TMPDIR/ax_dump" --list-apps                         # 실행 중인 앱의 번들 ID
"$TMPDIR/ax_dump" --app com.apple.Notes --depth 8      # 앱 전체
"$TMPDIR/ax_dump" --app Notes --window "제목" --json  # 창 하나만, JSON
"$TMPDIR/ax_dump" --app Notes --values none            # 값은 빼고 구조만
```

한 줄은 `역할[서브역할] "제목" desc="설명" id="식별자" value="값" actions=[...] settable=[...]` 꼴이다.
큰 표(`AXTable` · `AXOutline`)는 화면에 보이는 행(`AXVisibleRows`)만 내려가고 전체 행 수를 `rows=` 로 적는다.

**Accessibility Inspector** (Xcode → Open Developer Tool → Accessibility Inspector):
과녁 버튼으로 화면의 요소를 가리키면 역할 · 속성 · 동작과 부모 경로가 나온다. 사람이 "이 버튼이 트리의 어디인가"를
찾을 때 빠르다. Xcode 전체가 없으면 덤프 도구만으로도 된다.

## 순서

1. **트리가 있는지**: 창 아래에 버튼 · 글자 · 표가 보이면 된다. 창 하나 · `AXGroup` 하나뿐이면 그 화면은 직접 그린 것이라
   AX로 어렵다. 사용자에게 말하고 다른 방법(공식 API 등)을 찾는다.
2. **사용자 작업을 단계로**: "검색창 누르기 → 이름 입력 → 결과 첫 줄 열기 → 입력창에 글 쓰기 → 보내기"처럼 적는다.
3. **단계마다 전 · 후 덤프**: 손으로 한 단계씩 하며 덤프를 떠서 `diff`로 바뀐 곳을 본다. 새로 생긴 창 · 메뉴 · 시트,
   값이 바뀐 요소가 그 단계의 대상이다.
4. **찾는 단서 고르기** (좋은 순서):
   - `AXIdentifier`: 개발자가 붙인 이름. 언어 설정이 바뀌어도 그대로다 (예: 메뉴 항목 `openChatRoom:` 같은 셀렉터 이름).
   - `AXRole` + `AXSubrole` + 위치 관계(어느 창 · 어느 표 밖/안).
   - `AXTitle` · `AXDescription`: 화면 언어에 따라 바뀐다. 한국어 · 영어 레이블을 둘 다 받는다.
   - 화면 순서 번호 · 좌표는 쓰지 않는다. 새 항목이 들어오면 바뀐다.
5. **동작 확인**: 각 요소의 `actions`(예: `AXPress`, `AXShowMenu`, `AXConfirm`, `AXRaise`, `AXScrollUpByPage`)와
   `settable`(예: `AXValue`, `AXFocused`, `AXSelectedText`)을 적는다. 동작이 목록에 있어도 실제로 안 되는 경우가 있다
   ([pitfalls.md](pitfalls.md)).

## 개인 정보

덤프의 `value`에는 화면의 글(대화 · 메일 · 이름)이 그대로 들어간다. 에이전트 대화에 붙이거나 파일로 남길 때는
`--values none`이나 `short`(앞 60자)를 쓰고, 저장소 · 이슈에 올리지 않는다.
