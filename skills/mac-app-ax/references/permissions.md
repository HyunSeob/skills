# 손쉬운 사용 권한

AX API로 다른 앱을 읽거나 조작하려면, **헬퍼를 실행하는 프로세스**가 손쉬운 사용 권한을 가져야 한다.

1. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용.
2. 헬퍼를 띄우는 앱을 켠다: 터미널(Terminal · iTerm · Ghostty 등)이나 에이전트 앱(Claude · Codex 앱 등).
   MCP 서버는 그 서버를 띄운 앱의 권한을 따른다.
3. 목록에 없으면 `+`로 추가한다. 권한을 바꾼 뒤에는 그 앱을 다시 실행해야 적용되는 경우가 많다.

헬퍼에서 확인:

```swift
guard AXIsProcessTrusted() else { throw Failure.blocked("accessibility_permission_required") }
```

설정 창을 띄워 권한을 요청하려면(처음 한 번):

```swift
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
_ = AXIsProcessTrustedWithOptions(options)
```

주의:

- 권한은 "이 프로세스가 화면의 모든 앱을 읽고 조작할 수 있다"는 뜻이다. 쓰지 않을 때는 꺼 두라고 사용자에게 알려도 된다.
- 손쉬운 사용 권한은 화면 녹화 권한과 다르다. AX 헬퍼는 화면 녹화 권한이 필요 없다.
- 앱을 다시 서명하거나 위치를 옮기면(새로 컴파일한 바이너리 포함) 권한이 풀린 것처럼 보일 수 있다.
  헬퍼 바이너리 자체가 아니라 그것을 띄우는 터미널 · 에이전트 앱에 권한을 주면 이 문제가 적다.
