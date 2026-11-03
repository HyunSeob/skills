#!/bin/zsh -f
# 썸네일 JPG/PNG들을 시청자가 실제로 보는 크기 · 모습으로 미리 본다.
#
#   preview_checks.sh <출력 폴더> <썸네일> [썸네일 ...]
#
#   small-preview.png  휴대폰 목록 크기(가로 320px)로 나란히. 문구와 초점이 여기서 읽혀야 한다.
#   tv-preview.png     TV 홈 화면처럼 아래 절반을 가린 모습(가로 480px)으로 나란히.
#                      위 절반만으로 무슨 영상인지, 왜 궁금한지가 보여야 한다.
set -e
OUT=${1:?출력 폴더}; shift
(( $# )) || { echo "썸네일 없음"; exit 1; }
mkdir -p $OUT
n=$#
ins=(); for j in "$@"; do ins+=(-i $j); done
small=""; tv=""
for i in {0..$((n-1))}; do
  small+="[$i]scale=320:-2,pad=iw+8:ih:0:0:white[s$i];"
  # 아래 절반을 거의 불투명하게 덮는다 (TV 목록에서 아래 절반이 잘리거나 정보 판에 가려지는 모습)
  tv+="[$i]scale=480:270,drawbox=x=0:y=ih/2:w=iw:h=ih/2:color=black@0.9:t=fill,pad=iw+8:ih:0:0:white[t$i];"
done
for i in {0..$((n-1))}; do small+="[s$i]"; tv+="[t$i]"; done
if (( n == 1 )); then small+="null"; tv+="null"; else small+="hstack=$n"; tv+="hstack=$n"; fi
ffmpeg -v error -y $ins -filter_complex "$small" -frames:v 1 ${OUT:A}/small-preview.png
ffmpeg -v error -y $ins -filter_complex "$tv" -frames:v 1 ${OUT:A}/tv-preview.png
echo "small-preview.png tv-preview.png -> ${OUT:A}"
