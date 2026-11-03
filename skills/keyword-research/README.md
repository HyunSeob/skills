# keyword-research

유튜브 영상 제목 · 설명란을 정하기 전에 **사람들이 실제로 치는 검색어**를 확인하는 스킬입니다.

YouTube와 Google 자동완성을 검색어마다 한 번에 받아 표로 만들고(무료, API 키 없음),
그 표를 어떻게 읽는지(다른 뜻에 뺏긴 단어, 의도가 다른 검색어, 아직 색인 안 된 새 이름)와
업로드 뒤 실제 유입 검색어를 확인하는 법까지 담았습니다.

## 쓰는 법

```
"keyword-research 스킬로 '무선 청소기 비교' 영상 제목 후보를 확인해 줘"
```

직접 돌릴 때 (Python 3만 있으면 됩니다):

```bash
python3 scripts/suggest.py 캠핑의자 "무선 청소기"
python3 scripts/suggest.py 쿠키 --suffixes "" 뜻 원리 --out keywords.md
python3 scripts/suggest.py "air fryer" --hl en --gl us
```

## 들어 있는 것

```
SKILL.md             읽는 법 · 손으로 확인할 곳 · 업로드 뒤 확인
scripts/suggest.py   YouTube · Google 자동완성 표 만들기
```

자동완성은 검색량 숫자가 아니라 "이 말을 치는 사람이 꽤 있다"는 신호입니다. 정확한 양은 Studio 리서치 탭과 Google Trends로 봅니다.
