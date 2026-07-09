"""Interactive session driver for safari_env via use.computer + visual grounding.

Each subcommand is a single small operation against a persistent sandbox.
The sandbox stays alive across invocations because use.computer's 2-minute
idle reaper resets on any API call, and we make calls frequently.

State lives in /tmp/session_state.json:
  {"sandbox_id": "...", "env_dir": "...", "task_id": "...",
   "display": [w, h], "task_start_unix": ...}

Boot:   python3 session.py boot
Op:     python3 session.py screenshot OUT.png
        python3 session.py ground "question" SCREENSHOT.png
        python3 session.py click X Y [--right] [--double] [--from1280]
        python3 session.py type "text"
        python3 session.py key chord
        python3 session.py move X Y [--from1280]
        python3 session.py exec "command"
        python3 session.py readfile REMOTE LOCAL
Finalize: python3 session.py finalize
Destroy:  python3 session.py destroy
"""

import argparse
import json
import os
import shlex
import shutil
import sys
import time
from pathlib import Path

REPO = Path("/Users/pranjal/Developer/gym-anything2")
STATE = Path("/tmp/session_state.json")

ENV_DIR = REPO / "benchmarks" / "cua_world-macos" / "environments" / "safari_env"
TASK_ID = "devtools_security_header_audit"

# Load env keys (use.computer + Gemini)
try:
    from dotenv import load_dotenv
    load_dotenv(REPO / ".env")
except ImportError:
    pass
os.environ.setdefault("USE_COMPUTER_API_KEY",
                      "mk_live_0f9e6bf848019e79941b475bdcee5aafd762ba3a9c4b8bfa")
os.environ.setdefault("USE_COMPUTER_BASE_URL", "https://api.dev.use.computer")
os.environ.setdefault("SCREENSHOT_QUERY_PROVIDER", "gemini")


def load_state():
    if not STATE.exists():
        sys.exit("No session state — run `boot` first")
    return json.loads(STATE.read_text())


def save_state(s):
    STATE.write_text(json.dumps(s, indent=2, default=str))


def get_sandbox():
    from use_computer import Computer
    s = load_state()
    cc = Computer(base_url=os.environ["USE_COMPUTER_BASE_URL"])
    sb = cc.get(s["sandbox_id"])
    return sb, s, cc


def upload_dir(sb, local: Path, remote: str):
    """Same shape as the runner does it: mkdir, then upload_dir."""
    sb.exec_ssh(f"mkdir -p {shlex.quote(remote)}", timeout=10)
    sb.upload_dir(str(local), remote)
    sb.exec_ssh(f"find {shlex.quote(remote)} -name '*.sh' -exec chmod +x {{}} +", timeout=30)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_boot(args):
    """Provision sandbox, upload workspace, run env's install/setup/pre_task hooks."""
    from use_computer import Computer
    log("create sandbox")
    cc = Computer(base_url=os.environ["USE_COMPUTER_BASE_URL"])
    sb = cc.create(type="macos")
    sid = sb.sandbox_id
    log(f"  sandbox_id={sid} host={getattr(sb, 'host', '?')}")

    log("mkdir /Users/lume/workspace + upload mounts")
    sb.exec_ssh("mkdir -p /Users/lume/workspace", timeout=10)
    upload_dir(sb, ENV_DIR / "scripts", "/Users/lume/workspace/scripts")
    upload_dir(sb, ENV_DIR / "tasks", "/Users/lume/workspace/tasks")

    log("run install_safari.sh (pre_start hook)")
    r = sb.exec_ssh(
        "bash -lc '/Users/lume/workspace/scripts/install_safari.sh > /Users/lume/env_setup_pre_start.log 2>&1; echo done'",
        timeout=120)
    print("install rc:", r.return_code, r.stdout[-200:])

    log("run setup_safari.sh (post_start hook)")
    r = sb.exec_ssh(
        "bash -lc '/Users/lume/workspace/scripts/setup_safari.sh > /Users/lume/env_setup_post_start.log 2>&1; echo done'",
        timeout=120)
    print("setup rc:", r.return_code, r.stdout[-200:])

    log("run pre_task hook (launches Safari)")
    r = sb.exec_ssh(
        f"bash -lc '/Users/lume/workspace/tasks/{TASK_ID}/setup_task.sh > /Users/lume/task_pre_task.log 2>&1; echo done'",
        timeout=120)
    print("pre_task rc:", r.return_code, r.stdout[-300:])

    # Get the display resolution from the sandbox itself
    di = sb.display.get_info()
    log(f"display: {di.width}x{di.height} scale={di.scale}")

    # Read the task_start_timestamp written by setup_task.sh so finalize can reuse it
    ts_out = sb.exec_ssh("cat /tmp/task_start_timestamp", timeout=5).stdout.strip()

    state = {
        "sandbox_id": sid,
        "env_dir": str(ENV_DIR),
        "task_id": TASK_ID,
        "display": [di.width, di.height],
        "task_start_unix": ts_out,
        "booted_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    save_state(state)
    log(f"state saved → {STATE}")
    log("session is live — sandbox stays alive as long as you keep poking it (2-min idle reaper)")


def cmd_screenshot(args):
    sb, s, cc = get_sandbox()
    out = Path(args.out)
    png = sb.screenshot.take_full_screen()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"saved {len(png)} bytes -> {out}")


def cmd_ground(args):
    """Run visual_grounding on a screenshot."""
    sys.path.insert(0, str(REPO / "extras/research/software_as_env/creation_audit/mcp"))
    from screenshot_query_mcp import visual_grounding
    print(visual_grounding(args.question, args.screenshot))


def _scale_xy(x, y, from1280, display):
    """Convert grounding-space (1280x720) to display-space if --from1280 used."""
    if not from1280:
        return int(x), int(y)
    dw, dh = display
    return int(x * dw / 1280), int(y * dh / 720)


def cmd_click(args):
    sb, s, cc = get_sandbox()
    x, y = _scale_xy(args.x, args.y, args.from1280, s["display"])
    button = "right" if args.right else "left"
    if args.double:
        sb.mouse.click(x, y, button=button, double=True)
    else:
        sb.mouse.click(x, y, button=button)
    print(f"clicked {button} at ({x}, {y}) [display={s['display']}]")


def cmd_move(args):
    sb, s, cc = get_sandbox()
    x, y = _scale_xy(args.x, args.y, args.from1280, s["display"])
    sb.mouse.move(x, y)
    print(f"moved to ({x}, {y})")


def cmd_type(args):
    sb, s, cc = get_sandbox()
    sb.keyboard.type(args.text)
    print(f"typed {len(args.text)} chars: {args.text[:50]!r}…")


def cmd_key(args):
    sb, s, cc = get_sandbox()
    chord = args.chord
    parts = [p.strip() for p in chord.split("+")]
    mods = {"cmd", "command", "ctrl", "control", "shift", "alt", "option", "fn"}
    modifiers = [p for p in parts if p.lower() in mods]
    keys = [p for p in parts if p.lower() not in mods]
    if not keys:
        sb.keyboard.hotkey(chord)
    elif len(keys) == 1 and not modifiers:
        sb.keyboard.press(keys[0])
    else:
        sb.keyboard.press(keys[-1], modifiers=modifiers or None)
    print(f"sent key chord {chord!r} (mods={modifiers} key={keys})")


def cmd_exec(args):
    sb, s, cc = get_sandbox()
    r = sb.exec_ssh(args.cmd, timeout=args.timeout)
    print(f"exec rc={r.return_code}")
    print(r.stdout)


def cmd_readfile(args):
    sb, s, cc = get_sandbox()
    Path(args.local).parent.mkdir(parents=True, exist_ok=True)
    sb.download_file(args.remote, args.local)
    print(f"downloaded {args.remote} -> {args.local} ({Path(args.local).stat().st_size} bytes)")


def cmd_finalize(args):
    """Run post_task hook then call verifier.py manually. Saves verifier result."""
    sb, s, cc = get_sandbox()
    task_id = s["task_id"]
    # Run post_task hook
    log("running post_task hook (export_result.sh)")
    sb.exec_ssh(
        f"bash -lc '/Users/lume/workspace/tasks/{task_id}/export_result.sh > /Users/lume/task_post_task.log 2>&1; echo done'",
        timeout=120)

    # Save what export produced (the result.json) + the agent's report.json
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        sb.download_file(f"/tmp/{task_id}_result.json", str(out_dir / "export_result_json.json"))
        log("saved export_result_json.json")
    except Exception as exc:
        log(f"  export json fetch failed: {exc}")
    try:
        sb.download_file("/Users/lume/Documents/security_audit_report.json",
                         str(out_dir / "agent_report.json"))
        log("saved agent_report.json")
    except Exception as exc:
        log(f"  agent_report.json fetch failed: {exc}")
    # Save logs
    for name in ("env_setup_pre_start.log", "env_setup_post_start.log",
                 "task_pre_task.log", "task_post_task.log"):
        try:
            sb.download_file(f"/Users/lume/{name}", str(out_dir / name))
        except Exception:
            pass

    # Load and call the verifier
    import importlib.util
    verifier_path = ENV_DIR / "tasks" / task_id / "verifier.py"
    spec = importlib.util.spec_from_file_location("verifier", verifier_path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    verify_fn = None
    for name in dir(mod):
        if name.startswith("verify_"):
            verify_fn = getattr(mod, name); break
    if verify_fn is None:
        sys.exit("no verify_* function found")

    # Build env_info: copy_from_env wraps sandbox.download_file
    def copy_from_env(remote, local):
        sb.download_file(remote, local)
    def exec_capture(cmd):
        return sb.exec_ssh(cmd, timeout=120).stdout
    env_info = {"copy_from_env": copy_from_env, "exec_capture": exec_capture}
    task_info = json.loads((ENV_DIR / "tasks" / task_id / "task.json").read_text())

    log("calling verifier")
    result = verify_fn({}, env_info, task_info)
    (out_dir / "verifier_result.json").write_text(json.dumps(result, indent=2, default=str))
    print(json.dumps(result, indent=2, default=str))


def cmd_destroy(args):
    sb, s, cc = get_sandbox()
    log("destroying sandbox")
    try:
        sb.close()
    except Exception as exc:
        log(f"  close failed: {exc}")
    cc.close()
    STATE.unlink(missing_ok=True)
    log("done — session state cleared")


def cmd_status(args):
    if not STATE.exists():
        print("(no session)")
        return
    s = load_state()
    print(json.dumps(s, indent=2))
    sb, _, _ = get_sandbox()
    try:
        di = sb.display.get_info()
        print(f"sandbox alive, display {di.width}x{di.height}")
    except Exception as exc:
        print(f"sandbox unreachable: {exc}")


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="subcommand", required=True)

    sp.add_parser("boot")
    s = sp.add_parser("screenshot"); s.add_argument("out")
    s = sp.add_parser("ground"); s.add_argument("question"); s.add_argument("screenshot")
    s = sp.add_parser("click"); s.add_argument("x", type=float); s.add_argument("y", type=float)
    s.add_argument("--right", action="store_true"); s.add_argument("--double", action="store_true")
    s.add_argument("--from1280", action="store_true")
    s = sp.add_parser("move"); s.add_argument("x", type=float); s.add_argument("y", type=float)
    s.add_argument("--from1280", action="store_true")
    s = sp.add_parser("type"); s.add_argument("text")
    s = sp.add_parser("key"); s.add_argument("chord")
    s = sp.add_parser("exec"); s.add_argument("cmd"); s.add_argument("--timeout", type=int, default=60)
    s = sp.add_parser("readfile"); s.add_argument("remote"); s.add_argument("local")
    s = sp.add_parser("finalize"); s.add_argument("--out-dir", required=True)
    sp.add_parser("destroy")
    sp.add_parser("status")

    args = p.parse_args()
    {
        "boot": cmd_boot, "screenshot": cmd_screenshot, "ground": cmd_ground,
        "click": cmd_click, "move": cmd_move, "type": cmd_type, "key": cmd_key,
        "exec": cmd_exec, "readfile": cmd_readfile, "finalize": cmd_finalize,
        "destroy": cmd_destroy, "status": cmd_status,
    }[args.subcommand](args)


if __name__ == "__main__":
    main()
