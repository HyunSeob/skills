#!/bin/zsh -f
# 녹화용 Ghostty 창을 띄운다: tmux 세션 'rec'에 붙고, 창 제목은 REC-TERM, 크기·위치를 맞춘다.
#
#   window.sh                      # 기본: 1460x821pt (16:9), 주 화면 가운데
#   window.sh 100 80 1460 821      # x y w h (전체 화면 좌표, pt, 주 화면 왼쪽 위가 0,0)
#   window.sh close                # 녹화용 Ghostty와 tmux 세션 정리
#
# 주의 (2026-10-08에 겪은 것들)
# - Ghostty에 `-e tmux attach -t rec`로 넘기면 빈 tmux 창이 하나 더 생긴다 → --command=<스크립트> 로 넘긴다
# - 창 위치·크기 조절은 System Events라서 이 스크립트를 실행하는 앱(터미널 · 에이전트 앱)에 손쉬운 사용 권한이 필요하다
# - 녹화 중 이 창이 가려지면 Ghostty가 화면을 다시 그리지 않아 영상이 멈춘다
set -e
TMUX_BIN=${TMUX_BIN:-$(command -v tmux || echo /opt/homebrew/bin/tmux)}
SESSION=rec
MARK=window-padding-balance   # 녹화용 Ghostty 인스턴스를 찾는 표시 (pgrep)
HERE=${0:A:h}

if [[ "$1" == close ]]; then
  pkill -f "$MARK" || true
  $TMUX_BIN kill-session -t $SESSION 2>/dev/null || true
  exit 0
fi
W=${3:-1460} H=${4:-821}
if [[ -z "$1" ]]; then
  # 주 화면 크기(pt)에서 가운데 자리를 구한다
  SCREEN=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f = $.NSScreen.screens.objectAtIndex(0).frame; Math.round(f.size.width) + " " + Math.round(f.size.height)')
  SW=${SCREEN%% *} SH=${SCREEN##* }
  X=$(( (SW - W) / 2 )) Y=$(( (SH - H) / 2 ))
  (( X < 0 )) && X=0; (( Y < 0 )) && Y=0
else
  X=$1 Y=${2:?y}
fi

[[ -x $TMUX_BIN ]] || { echo "tmux 없음: brew install tmux"; exit 1; }
if ! $TMUX_BIN has-session -t $SESSION 2>/dev/null; then
  $TMUX_BIN new-session -d -s $SESSION -x 126 -y 31 "zsh -f"
fi
$TMUX_BIN set -t $SESSION status off
$TMUX_BIN set -g set-titles on
$TMUX_BIN set -g set-titles-string "REC-TERM"
$TMUX_BIN set -g focus-events on

# 창이 tmux에 붙어 있어야 살아 있는 것. 창 없이 프로세스만 남은 인스턴스는 정리하고 새로 띄운다
if ! $TMUX_BIN list-clients -t $SESSION 2>/dev/null | grep -q .; then
  pkill -f "$MARK" || true
  sleep 0.5
  ATTACH=$HERE/.attach.sh
  printf '#!/bin/zsh -f\nexec %s attach -t %s\n' $TMUX_BIN $SESSION > $ATTACH
  chmod +x $ATTACH
  open -na Ghostty --args --font-size=18 --window-width=118 --window-height=29 \
    --window-padding-x=36 --window-padding-y=28 --window-padding-balance=true \
    --macos-titlebar-style=hidden --confirm-close-surface=false --window-save-state=never \
    --command=$ATTACH
  for i in {1..40}; do $TMUX_BIN list-clients -t $SESSION 2>/dev/null | grep -q . && break; sleep 0.25; done
fi
PID=$(pgrep -f "$MARK" | head -1)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to tell window 1 to set {position, size} to {{$X, $Y}, {$W, $H}}"
echo "REC-TERM window: pid $PID at $X,$Y ${W}x$H"
