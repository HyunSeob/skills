#!/usr/bin/env python3
"""YouTube · Google 자동완성으로 사람들이 실제로 치는 검색어를 모은다.

    python3 suggest.py 캠핑의자 "무선 청소기" 에어프라이어
    python3 suggest.py 캠핑의자 --suffixes "" 추천 비교 --out keywords.md

검색어마다 "검색어 + 꼬리말"(기본: 그대로, 추천, 방법, 뜻, 비교, 후기)을 넣어
YouTube(ds=yt)와 Google 웹 자동완성을 받아 표로 보여준다. 무료, 키 없음.
자동완성에 안 뜨는 표현은 검색량이 거의 없다는 뜻이다. 결과의 해석(다른 뜻과 섞이는지,
의도가 다른지)은 사람이 본다.
"""
import argparse, json, sys, time, urllib.parse, urllib.request

def suggest(q, yt, hl="ko", gl="kr"):
    params = {"client": "firefox", "hl": hl, "gl": gl, "q": q}
    if yt:
        params["ds"] = "yt"
    url = "https://suggestqueries.google.com/complete/search?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(4):  # the endpoint times out now and then; retry instead of losing the whole run
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read().decode("utf-8", "replace"))[1]
        except (OSError, TimeoutError) as e:
            if attempt == 3:
                print(f"! {q}: {e}", file=sys.stderr)
                return []
            time.sleep(2 * (attempt + 1))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("seeds", nargs="+")
    ap.add_argument("--suffixes", nargs="*", default=["", "추천", "방법", "뜻", "비교", "후기"])
    ap.add_argument("--out", help="결과를 마크다운으로도 저장")
    ap.add_argument("--hl", default="ko", help="언어 (기본 ko)")
    ap.add_argument("--gl", default="kr", help="국가 (기본 kr)")
    a = ap.parse_args()
    lines = []
    for seed in a.seeds:
        lines.append(f"## {seed}\n\n| 입력 | YouTube | Google |\n|---|---|---|")
        for suf in a.suffixes:
            q = f"{seed} {suf}".strip() if suf and not suf.startswith(("이란", "란")) else seed + suf
            yt, web = suggest(q, True, a.hl, a.gl), suggest(q, False, a.hl, a.gl)
            lines.append(f"| {q} | {' · '.join(yt[:8]) or '(없음)'} | {' · '.join(web[:8]) or '(없음)'} |")
            time.sleep(0.3)
        lines.append("")
    text = "\n".join(lines)
    print(text)
    if a.out:
        open(a.out, "w").write(text + "\n")

if __name__ == "__main__":
    sys.exit(main())
