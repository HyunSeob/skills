# thumbnail-checks

어느 채널에나 통하는 **유튜브 썸네일 확인 목록**과, 썸네일을 시청자가 실제로 보는 크기로 미리 보는 도구입니다.

- TV 목록처럼 아래 절반을 가렸을 때도 통하는지
- 휴대폰 목록 크기(가로 320px)에서 글자가 읽히는지
- 시안 전에 레퍼런스 10개와 "왜 눌리는지" 모으기
- 요약 대신 궁금증, 대상 하나와 깨끗한 배경
- YouTube Studio 테스트 및 비교로 문구 A/B 테스트

## 쓰는 법

```
"thumbnail-checks 스킬로 이 썸네일 시안 세 개를 확인해 줘"
```

직접 돌릴 때 (ffmpeg 필요):

```bash
scripts/preview_checks.sh previews a.jpg b.jpg c.jpg
# previews/small-preview.png  휴대폰 목록 크기로 나란히
# previews/tv-preview.png     아래 절반을 가린 TV 목록 모습으로 나란히
```

채널마다 정한 글꼴 · 색 · 배치 규칙이 있다면, 그 규칙과 이 확인 목록을 같이 쓰면 됩니다.

## 들어 있는 것

```
SKILL.md                    원칙 6가지와 확인 방법
scripts/preview_checks.sh   휴대폰 · TV 미리보기 이미지 만들기
```
