"""녹화용 Ghostty 창(window.sh로 띄움) 안의 터미널 프로그램을 tmux로 조작하면서 그 창만 녹화한다.

사용: python3 <스킬 폴더>/scripts/record.py <take.json> [--name take1]

take.json:
{
  "workdir": "~/demo-project",                 # 프로그램을 실행할 폴더
  "command": "env ... claude --model haiku",   # 녹화할 프로그램 (끝나면 zsh -f로 남는다)
  "ready": "shift\\+tab",                      # 이 글자가 화면에 보이면 시작 준비 완료 (정규식)
  "busy": "esc to interrupt",                  # 이 글자가 보이는 동안은 작업 중 (정규식)
  "watch": {"COMPACT": "Compacting conversation", "GAUGE": "(\\d+)% until auto-compact"},
  "out": "recording/takes",                    # take.json 기준 상대 경로
  "steps": [
    {"type": "보낼 메시지"},                   # 입력창을 비우고 사람 속도로 타이핑한 뒤 Enter
    {"wait_idle": true},                       # busy 글자가 사라지고 4초 조용해질 때까지 대기
    {"pause": 3},
    {"keys": ["Escape"]}                       # tmux send-keys 키 이름 그대로
  ]
}

결과(out 폴더): <name>.mov (창 녹화, 커서 없음, 30fps), <name>.log (타임코드 붙은 진행 기록),
<name>.final.txt (끝난 뒤 화면 전체 텍스트)
"""
import argparse
import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).parent
SESSION = "rec"
TITLE = "REC-TERM"
WINCAP = HERE / "bin" / "wincap"

log_f = None
t0 = None


def log(msg):
    line = f"[{time.time() - t0:8.1f}s] {msg}" if t0 else f"[  setup  ] {msg}"
    print(line, flush=True)
    if log_f:
        log_f.write(line + "\n")
        log_f.flush()


def tmux(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True).stdout


def screen(history=False):
    return tmux("capture-pane", "-p", "-t", SESSION, *(["-S", "-3000"] if history else []))


def ensure_wincap():
    if WINCAP.exists() and WINCAP.stat().st_mtime >= (HERE / "wincap.swift").stat().st_mtime:
        return
    WINCAP.parent.mkdir(exist_ok=True)
    log("building wincap (first run)")
    subprocess.run(["swiftc", "-O", str(HERE / "wincap.swift"), "-o", str(WINCAP)], check=True)


def type_text(text, cps=28):
    tmux("send-keys", "-t", SESSION, "C-u")  # 입력창에 남은 글자 지우기
    time.sleep(0.3)
    for ch in text:
        tmux("send-keys", "-t", SESSION, "-l", ch)
        time.sleep(1 / cps)
    time.sleep(0.6)
    tmux("send-keys", "-t", SESSION, "Enter")
    log(f"SENT: {text}")


class Watcher:
    """화면에서 지정한 글자가 나타나고 사라지는 순간을 기록한다."""

    def __init__(self, patterns):
        self.patterns = {k: re.compile(v, re.I) for k, v in patterns.items()}
        self.state = {}

    def __call__(self, s):
        for name, rx in self.patterns.items():
            m = rx.search(s)
            val = (m.group(1) if m and m.groups() else bool(m))
            if val != self.state.get(name):
                if m and not m.groups():
                    log(f"{name} START")
                elif not m and self.state.get(name) is True:
                    log(f"{name} END")
                elif m:
                    log(f"{name} {val}")
                self.state[name] = val


def wait_idle(busy, watch, timeout=2400, settle=4.0):
    time.sleep(2.5)
    start, idle_since = time.time(), None
    while time.time() - start < timeout:
        s = screen()
        watch(s)
        if busy.search(s):
            idle_since = None
        else:
            idle_since = idle_since or time.time()
            if time.time() - idle_since >= settle:
                log("IDLE")
                return
        time.sleep(0.5)
    log("TIMEOUT waiting idle")


def start_program(cfg):
    workdir = str(Path(cfg["workdir"]).expanduser())
    tmux("respawn-pane", "-k", "-t", SESSION, "-c", workdir, f"{cfg['command']}; zsh -f")
    tmux("clear-history", "-t", SESSION)
    ready = re.compile(cfg.get("ready", "."))
    for _ in range(80):
        time.sleep(0.5)
        if ready.search(screen()):
            break
    else:
        sys.exit("프로그램이 준비되지 않았다:\n" + screen())
    time.sleep(2)
    log("program ready")


def bring_to_front():
    for pid in subprocess.run(["pgrep", "-f", "window-padding-balance"], capture_output=True, text=True).stdout.split():
        subprocess.run(["swift", "-e", f"import AppKit; _ = NSRunningApplication(processIdentifier: {pid})?.activate(options: [])"])
    time.sleep(1.5)


def main():
    global log_f, t0
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("take", help="take.json")
    ap.add_argument("--name", default="take")
    a = ap.parse_args()
    cfg_path = Path(a.take).resolve()
    cfg = json.loads(cfg_path.read_text())
    out = (cfg_path.parent / cfg.get("out", "takes")).resolve()
    out.mkdir(parents=True, exist_ok=True)
    if subprocess.run(["tmux", "has-session", "-t", SESSION], capture_output=True).returncode != 0:
        sys.exit(f"녹화용 창이 없다: 먼저 {HERE / 'window.sh'} 를 실행할 것")

    ensure_wincap()
    log_f = open(out / f"{a.name}.log", "w")
    busy = re.compile(cfg.get("busy", "$^"), re.I)
    watch = Watcher(cfg.get("watch", {}))
    start_program(cfg)
    bring_to_front()
    mov = out / f"{a.name}.mov"
    rec = subprocess.Popen([str(WINCAP), TITLE, str(mov)], stdout=subprocess.PIPE, text=True)
    first, second = rec.stdout.readline().strip(), rec.stdout.readline().strip()
    if second != "recording":
        sys.exit(f"녹화 시작 실패 (화면 녹화 권한? 창 제목?): {first} {second}")
    t0 = time.time()
    log(f"RECORDING {first} -> {mov.name}")
    time.sleep(3)
    try:
        for step in cfg["steps"]:
            if "type" in step:
                type_text(step["type"])
            elif "wait_idle" in step:
                wait_idle(busy, watch)
            elif "pause" in step:
                time.sleep(step["pause"])
            elif "keys" in step:
                tmux("send-keys", "-t", SESSION, *step["keys"])
                log(f"KEYS {step['keys']}")
        (out / f"{a.name}.final.txt").write_text(screen(history=True))
    finally:
        rec.send_signal(signal.SIGINT)
        rec.wait(timeout=60)
        log("STOPPED")


if __name__ == "__main__":
    main()
