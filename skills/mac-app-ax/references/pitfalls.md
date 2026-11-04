# 실제로 막혔던 곳

실제 앱에서 헬퍼를 만들며 부딪힌 것들이다. 앱마다 다르게 나올 수 있으니
"이렇게 될 수 있다"로 읽고, 2단계 덤프 · 6단계 확인에서 직접 본다.

## 1. `AXValue`만 바꾸면 앱이 반응하지 않는다

**증상**: 검색창에 `AXValue`를 넣으면 화면 글자는 바뀌는데 목록이 걸러지지 않는다.
앱은 키보드 입력 · 편집 이벤트를 듣고 있고, 값 교체는 그 이벤트를 만들지 않는다.

**고친 순서**:

```swift
AXUIElementSetAttributeValue(field, "AXFocused" as CFString, kCFBooleanTrue)          // 1. 포커스
var range = CFRange(location: 0, length: currentValue.utf16.count)
AXUIElementSetAttributeValue(field, "AXSelectedTextRange" as CFString, AXValueCreate(.cfRange, &range)!) // 2. 전체 선택
AXUIElementSetAttributeValue(field, "AXSelectedText" as CFString, query as CFString)  // 3. 선택 영역을 바꿔 쓰기 = 실제 편집
if actions(field).contains("AXConfirm") { AXUIElementPerformAction(field, "AXConfirm" as CFString) } // 4. 확정
Thread.sleep(forTimeInterval: 0.65)                                                     // 5. 앱의 검색 지연(디바운스)을 기다림
```

- 바로 읽으면 **이전 검색어의 결과**가 나온다. 앱이 입력을 잠깐 모았다 처리하기 때문이다. 기다린 뒤 읽는다.
- 바꾼 뒤 `AXValue`를 다시 읽어 넣은 값과 같은지 확인한다.
- 이 편집 함수는 검색용 `AXTextField` · `AXSearchField`에만 허용하고, 본문 입력창(`AXTextArea`)에는 못 쓰게 막았다.
  실수로 사용자가 쓰던 글을 지우지 않게.

반대로 본문 입력창은 `AXValue` 설정만으로 값이 들어가고 버튼이 활성화되기도 한다. 요소마다 다르니 둘 다 시험한다.

## 2. `AXPress`가 오류를 줘도 실행된다 → 재시도 금지

**증상**: 버튼에 `AXPress`를 하면 `-25200`(`kAXErrorFailure`)이 돌아오는데, 동작은 실제로 실행됐다.
다른 AX 기반 도구로 같은 버튼을 눌러도 같은 오류가 났다.

**대응**: 반환값으로 성공을 판단하지 않는다. 한 번만 누르고, `dispatch_result_unknown`으로 기록한 뒤
화면을 다시 읽어 기대한 변화를 관찰한다 ([verify-and-dedupe.md](verify-and-dedupe.md)).
"오류니까 한 번 더"를 하면 두 번 실행된다.

## 3. 큰 목록에서 시간 초과 → `AXVisibleRows`

**증상**: 항목이 수백 개인 목록을 읽다가 한도 초과로 멈췄다. 표가 보고한 행 전부를 `AXChildren` · `AXRows`로
가져오면, 앱이 화면 밖 빈 셀을 하나하나 만들어 준다.

**대응**: 표의 `AXVisibleRows`(지금 보이는 몇 행)만 읽고, 전체 수는
`AXUIElementGetAttributeValueCount(table, "AXRows", &count)`로 따로 센다. 결과에 둘을 나눠 적는다
(`items`는 보이는 것, `reportedRowCount`는 앱이 보고한 수).
화면 밖 항목이 필요하면 앱의 검색으로 좁혀서 보이게 만든다.

## 4. 노드마다 속성을 따로 읽으면 느리다 → `AXUIElementCopyMultipleAttributeValues`

**증상**: 긴 목록 여러 개를 병렬로 읽으면 한도 초과. AX 속성 읽기 하나가 앱과의 프로세스 간 왕복 하나라,
노드마다 역할 · 제목 · 설명 · 자식을 따로 읽으면 왕복이 네 배가 된다.

**대응**: [AXUIElementCopyMultipleAttributeValues](https://developer.apple.com/documentation/applicationservices/1462051-axuielementcopymultipleattribute)로
한 노드의 속성을 한 번에 읽는다.

```swift
let names = ["AXRole", "AXTitle", "AXDescription", "AXHelp", "AXChildren"]
var copied: CFArray?
AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &copied)
// 실패한 속성은 배열 안에 AXValue(.axError)로 들어온다. 하나씩 꺼내 구분한다.
```

- 실패한 속성은 결과 배열 안에 `AXValue` 형식의 오류로 섞여 온다. `attributeUnsupported` · `noValue`는 "없음"으로,
  꼭 필요한 속성(본문 값)의 오류는 실패로 처리한다.
- 어떤 앱은 **비어 있는 `AXDescription`에도 `kAXErrorFailure`를 준다**. 선택적 속성의 실패는 세어서
  `optionalAttributeFailures`로 따로 보고하고, 본문 읽기 실패와 섞지 않는다.

## 5. 스크롤 동작이 있다고 나오는데 안 된다

**증상**: 스크롤 영역이 `AXScrollUpByPage`를 지원한다고 내놓는데, 부르면 오류.

**대응**: 세로 스크롤바(`AXVerticalScrollBar`)의 `AXValue`가 바꿀 수 있으면 `AXMinValue`로 설정(맨 위로)을 먼저 쓴다.
안 되면 스크롤바의 이전 페이지 부분(`AXDecrementPage`)에 `AXPress`, 그다음이 `AXScrollUpByPage`.
행 수 변화로 효과를 확인하고, 변화가 없어도 "기록의 끝"이라고 하지 않는다 (앱이 아직 안 불러왔을 수 있다).

## 6. 목록 항목 열기는 메뉴로

목록 셀에 `AXPress`가 없거나 선택만 될 때: 셀에 `AXShowMenu` → 뜬 `AXMenu`의 항목을 **`AXIdentifier`**(예: `open:` 같은 셀렉터 이름)와
제목으로 찾아 `AXPress`. 메뉴가 이미 열려 있으면 사용자가 연 것이니 건드리지 않고 멈춘다.

## 7. 그 밖에

- **레이블은 언어마다 다르다**: `["저장", "Save"]`처럼 둘 다 받는다. 가능하면 `AXIdentifier`로 찾는다.
- **앱 검색은 생각보다 넓게 맞는다**: 제목 검색이 다른 필드(참여자 · 본문)에도 맞을 수 있다. 결과를 "이름 부분 일치"로 해석하지 않고,
  열 때는 정확한 이름이 하나인지 다시 본다.
- **창을 바꾼 직후 창 목록이 잠깐 비었다**: 보조 창이 생겼다 사라지는 순간. "창 없음"의 증거로 쓰지 말고 다시 확인한다.
- **최소화 · 뒤에 있는 창도 읽히는 앱이 있다**. 그러면 읽기에 창을 앞으로 올릴 필요가 없다. 앱마다 확인한다.
- **화면이 바뀌는 중에 번호를 재사용하지 않는다**: 시험 중에 새 항목이 들어와 목록 순서가 바뀔 수 있다.
- **같은 AX 데이터끼리는 교차 검증이 아니다**: 덤프 · 다른 AX 도구와 헬퍼가 같다고 맞는 게 아니다. 스크린샷으로 화면과 비교한다.
- **읽은 범위를 넘겨 말하지 않는다**: 보이는 행 · 불러온 행만 읽는다. 사진 · 첨부 · 작성자는 AX에 글자로 안 나올 수 있다.
