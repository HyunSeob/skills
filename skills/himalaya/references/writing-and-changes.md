# 초안·발송·서버 변경

Himalaya v2.2.1에서 검증한 예제다. 다른 버전에서는 하위 명령의 `--help`로 옵션과 변경 효과를 확인한다. 변수는 실제 선택·조회 결과로 채우며, 예제 주소는 실행 전에 요청의 수신자로 바꾼다. 아래 명령을 일괄 실행하지 말고 요청된 동작만 선택한다.

## 실행 범위

| 동작 | 실제 효과 |
| --- | --- |
| `message compose/reply/forward` 기본 | RFC 5322 메시지를 stdout에 출력 |
| 위 명령의 `--json` 기본 | 디코딩된 작성 필드를 출력하며 최종 발송 시 붙는 서명은 빠짐 |
| 위 명령의 `--save <mailbox>` | 서버 또는 해당 백엔드 메일함에 사본 추가 |
| 위 명령의 `--send` | 발송 |
| `message send` | 입력 메시지를 발송 |
| `message add` | 입력 메시지를 메일함에 추가; `--send`가 있으면 발송도 수행 |
| `message read --seen`, `flag ...` | 읽음 등 메시지 상태 변경 |
| `message move/copy/delete` | 서버 또는 해당 백엔드 메시지 변경 |

사용자가 초안을 원하면 대화에서 검토 가능한 내용을 제시하거나 요청된 로컬 `.eml` 파일을 만든다. 서버 임시보관함 저장과 실제 발송은 각각의 요청 범위에 있을 때 수행한다. 새 승인이 필요하다면 먼저 수신자·제목·본문·첨부를 검토 가능한 상태로 완성하고 필요한 부분만 묻는다. 명확한 발송 지시를 이미 받았다면 같은 승인을 다시 요구하지 않는다.

## 새 메일 초안

본문은 도구로 UTF-8 파일에 쓴다. 사용자 텍스트를 셸 문자열에 보간하지 않는다. 임시 파일이 필요하면 비공개 임시 디렉터리와 제한된 파일 권한을 사용한다. 사용자가 요청한 산출물은 보존하고 작업용 임시 파일만 정리한다.

```bash
himalaya -a "$account" message compose \
  --to 'recipient@example.invalid' \
  --subject '메일 제목' \
  --body-file "$body_file" > "$draft_file"
```

- 여러 수신자는 `--to`를 반복하거나 쉼표로 구분한다. `--cc`, `--bcc`는 별도 플래그다. 주소·제목 값에 개행을 삽입하지 않는다.
- 첨부는 `--attach "$attachment_file"`을 반복한다. 파일의 실제 존재 여부와 요청된 파일인지를 확인한다.
- 발신자는 계정의 `email`과 `display-name`을 사용한다. `--from`은 요청된 발신 신원이 확인된 경우에만 사용한다. 발신 헤더가 빠진 초안을 발송하지 않는다.
- 본문 입력은 `--body`, `--body-file`, stdin 중 하나를 사용한다. 자동 실행에서는 `--body-file`을 선호한다.
- 기본 서명과 `--signature`/`--signature-file`이 반영될 수 있다. 최종 검토는 JSON 작성 필드만 보지 말고 생성한 `.eml`을 MIME 파서로 읽어 수신자·본문·첨부·서명을 확인한다.
- `--send`와 `--save`가 없는 compose는 발송·서버 저장을 하지 않지만, 계정에는 지원 백엔드가 하나 이상 설정되어 있어야 한다.

## 답장·전달

원본을 먼저 확인하고 같은 계정·메일함·메시지 ID로 작성한다.

```bash
himalaya -a "$account" message reply -m "$mailbox" "$id" \
  --body-file "$body_file" > "$draft_file"
himalaya -a "$account" message forward -m "$mailbox" "$id" \
  --to 'recipient@example.invalid' --body-file "$body_file" > "$draft_file"
```

`reply`는 `In-Reply-To`, `References`, `Re:` 제목과 `Reply-To`/`From` 수신자를 구성한다. `forward`는 `Fwd:` 제목·References·인용 본문을 구성한다. 답장을 새 `compose`로 대체해 스레드 연결을 잃지 않는다.

v2.2.1의 `reply`에는 `--all`이 없다. 전체 답장이 요청되면 원본 To/Cc와 발신 계정 주소를 확인하고 자신·중복 주소를 제외한 실제 수신자를 `--to`/`--cc`로 명시한다. 원본 첨부가 자동 포함된다고 가정하지 말고 최종 MIME을 확인한다. 필요한 첨부는 내려받아 `--attach`로 명시한다.

인용 방식은 `--posting-style top|bottom|none`이다. 원문을 직접 배치했다면 `none`을 선택해 중복 인용을 피한다.

## 발송과 서버 초안 저장

먼저 `account list`의 백엔드를 확인한다. IMAP만 설정된 계정은 조회·서버 초안 저장과 발송 능력이 다르다. 발송 경로는 설치 버전의 `message send --help`와 선택한 백엔드 도움말로 확인한다. SMTP·JMAP 등의 발송 경로가 없다면 완성한 초안을 보존하고 부족한 설정을 보고한다. 이 때문에 계정·인증 구성을 임의로 변경하지 않는다.

발송이 요청되었고 계정·수신자·내용이 확정된 경우, 검토한 파일을 그대로 보낸다.

```bash
himalaya -a "$account" --json message send -- "$draft_file"
```

`message.send.save-copy` 설정에 따라 보낸 메일 사본이 저장될 수 있다. `--save "$sent_mailbox"`는 사본 위치를 지정하고, `--no-save`는 설정된 사본 저장을 생략한다. 사본 저장 오류가 발송 후 발생할 수 있으므로, 비정상 종료만 보고 자동으로 재발송하지 않는다. 어떤 단계까지 성공했는지 확인한다.

서버 임시보관함 저장이 요청되면 `mailbox list`에서 확인한 메일함을 사용한다. `--`는 가변 길이 `--flag` 인수와 메시지 파일 경로를 구분한다.

```bash
himalaya -a "$account" --json message add \
  -m "$drafts_mailbox" --flag draft -- "$draft_file"
```

## 플래그·이동·삭제

변경 전에 최신 목록이나 원문에서 계정·메일함·대상 ID를 확인한다. 여러 건이면 대상 범위가 요청과 일치하는지 확인하고 실행한다.

```bash
himalaya -a "$account" --json flag add -m "$mailbox" --flag seen "$id"
himalaya -a "$account" --json flag remove -m "$mailbox" --flag seen "$id"
himalaya -a "$account" --json flag add -m "$mailbox" --flag flagged "$id"
himalaya -a "$account" --json message move --from "$mailbox" --to "$destination" "$id"
himalaya -a "$account" --json message copy --from "$mailbox" --to "$destination" "$id"
himalaya -a "$account" --json message delete -m "$mailbox" "$id"
```

- `flag add/remove`는 지정한 플래그만 바꾼다. `flag set`은 기존 플래그를 전부 교체하므로, 전체 교체를 요청한 경우에만 사용한다.
- move/copy는 같은 계정 안의 작업이다. 이 명령의 `-f`는 `--from`이므로 다른 명령의 `-m`과 혼동하지 않는다.
- delete는 일반 메일함에서 휴지통으로 보내지만, 이미 휴지통인 메시지는 영구 삭제할 수 있다. 휴지통의 역할·실제 메일함과 사용자의 삭제 범위를 확인한다. 일반 정리 요청을 영구 삭제나 expunge로 확대하지 않는다.
- 성공 후 필요한 최소한의 재조회로 상태·도착 메일함을 확인한다. 부분 실패나 대기 상태를 전체 완료로 보고하지 않는다.
