"""Verify startup cannot overwrite a title in a disposable tmux server."""
from pathlib import Path
import os
import shlex
import subprocess
import sys
import tempfile
import time

executable = str(Path(sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/quicktui").resolve())
with tempfile.TemporaryDirectory(prefix="quicktui-tmux-", dir="/tmp") as directory:
    socket = str(Path(directory) / "socket")
    environment = {key: value for key, value in os.environ.items() if key != "TMUX"}

    def tmux(*arguments):
        return subprocess.check_output(["tmux", "-f", "/dev/null", "-S", socket, *arguments], env=environment, text=True).strip()

    try:
        tmux("new-session", "-d", "-s", "probe", "-x", "80", "-y", "33", "bash --noprofile --norc")
        for passthrough in ["off", "on"]:
            tmux("set-option", "-w", "-t", "probe", "allow-passthrough", passthrough)
            tmux("select-pane", "-t", "probe", "-T", "quicktui-title-sentinel")
            tmux("send-keys", "-t", "probe", "-l", shlex.quote(executable))
            tmux("send-keys", "-t", "probe", "Enter")
            deadline = time.monotonic() + 8
            while "block fallback" not in tmux("capture-pane", "-p", "-t", "probe"):
                assert time.monotonic() < deadline, "Example failed to reach graphics fallback"
                time.sleep(0.05)
            title = tmux("display-message", "-p", "-t", "probe", "#{pane_title}")
            assert title == "quicktui-title-sentinel", f"Probe corrupted title: {title!r}"
            tmux("send-keys", "-t", "probe", "q")
            deadline = time.monotonic() + 8
            while tmux("display-message", "-p", "-t", "probe", "#{pane_current_command}") != "bash":
                assert time.monotonic() < deadline
                time.sleep(0.05)
            print(f"PASS tmux pane title preserved with allow-passthrough={passthrough}")
        # A detached server can still retain placeholder text. Inject only the
        # graphics reply; no outer terminal or graphics support is assumed here.
        tmux("select-pane", "-t", "probe", "-T", "quicktui-title-sentinel")
        tmux("send-keys", "-t", "probe", "-l", shlex.quote(executable))
        tmux("send-keys", "-t", "probe", "Enter")
        deadline = time.monotonic() + 8
        while "Count: 0" not in tmux("capture-pane", "-p", "-t", "probe"):
            assert time.monotonic() < deadline
            time.sleep(0.05)
        tmux("send-keys", "-t", "probe", "-l", "\x1b_Gi=31337;OK\x1b\\")
        def wait_picture():
            deadline = time.monotonic() + 8
            while True:
                captured = tmux("capture-pane", "-p", "-t", "probe")
                if "\U0010eeee" in captured:
                    return captured
                assert time.monotonic() < deadline, "Picture placeholders missing from tmux grid"
                time.sleep(0.05)
        first = wait_picture()
        tmux("send-keys", "-t", "probe", "Space")
        deadline = time.monotonic() + 8
        while "Count: 1" not in tmux("capture-pane", "-p", "-t", "probe"):
            assert time.monotonic() < deadline
            time.sleep(0.05)
        assert wait_picture().count("\U0010eeee") == first.count("\U0010eeee")
        tmux("resize-window", "-t", "probe", "-x", "90", "-y", "35")
        deadline = time.monotonic() + 8
        while "90 × 35" not in tmux("capture-pane", "-p", "-t", "probe"):
            assert time.monotonic() < deadline
            time.sleep(0.05)
        assert wait_picture().count("\U0010eeee") > first.count("\U0010eeee")
        title = tmux("display-message", "-p", "-t", "probe", "#{pane_title}")
        assert title == "quicktui-title-sentinel", repr(title)
        tmux("send-keys", "-t", "probe", "q")
        print("PASS tmux retains image placeholders across counter updates and resize")
    finally:
        subprocess.run(["tmux", "-S", socket, "kill-server"], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
