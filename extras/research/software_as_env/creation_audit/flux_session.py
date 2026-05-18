"""Interactive session driver for flux_env via use.computer.

Mirrors the shape of macos_session.py (safari_env) and notion_session.py.
Each subcommand is a single small operation against a persistent sandbox.
State lives in /tmp/flux_session_state.json.

Boot:   python3 flux_session.py boot
Op:     python3 flux_session.py screenshot OUT.png
        python3 flux_session.py click X Y [--right] [--double] [--from1280]
        python3 flux_session.py move X Y [--from1280]
        python3 flux_session.py type "text"
        python3 flux_session.py key chord
        python3 flux_session.py exec "command"
        python3 flux_session.py readfile REMOTE LOCAL
Finalize: python3 flux_session.py finalize --out-dir <dir>
Destroy:  python3 flux_session.py destroy
"""

import argparse
import json
import os
import shlex
import sys
import time
from pathlib import Path

REPO = Path("/Users/pranjal/Developer/gym-anything2")
STATE = Path("/tmp/flux_session_state.json")

ENV_DIR = REPO / "benchmarks" / "cua_world-macos" / "environments" / "flux_env"
DEFAULT_TASK_ID = "launch_flux"

try:
    from dotenv import load_dotenv
    load_dotenv(REPO / ".env")
except ImportError:
    pass

# The .env file uses USE_COMPUTER (not USE_COMPUTER_API_KEY); both shapes are
# accepted here so the SDK finds the credential under either name.
_API = os.environ.get("USE_COMPUTER_API_KEY") or os.environ.get("USE_COMPUTER") \
    or "mk_live_0f9e6bf848019e79941b475bdcee5aafd762ba3a9c4b8bfa"
os.environ["USE_COMPUTER_API_KEY"] = _API
os.environ.setdefault("USE_COMPUTER_BASE_URL", "https://api.dev.use.computer")


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
    sb.exec_ssh(f"mkdir -p {shlex.quote(remote)}", timeout=10)
    sb.upload_dir(str(local), remote)
    sb.exec_ssh(f"find {shlex.quote(remote)} -name '*.sh' -exec chmod +x {{}} +", timeout=30)


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_boot(args):
    """Provision sandbox, upload workspace, run env install/setup/pre_task hooks."""
    from use_computer import Computer
    task_id = args.task_id or DEFAULT_TASK_ID
    log(f"create sandbox (task={task_id})")
    cc = Computer(base_url=os.environ["USE_COMPUTER_BASE_URL"])
    sb = cc.create(type="macos")
    sid = sb.sandbox_id
    log(f"  sandbox_id={sid} host={getattr(sb, 'host', '?')}")

    log("mkdir /Users/lume/workspace + upload mounts")
    sb.exec_ssh("mkdir -p /Users/lume/workspace", timeout=10)
    upload_dir(sb, ENV_DIR / "scripts", "/Users/lume/workspace/scripts")
    upload_dir(sb, ENV_DIR / "tasks", "/Users/lume/workspace/tasks")

    log("run install_flux.sh (pre_start hook)")
    t0 = time.time()
    r = sb.exec_ssh(
        "bash -lc '/Users/lume/workspace/scripts/install_flux.sh > /Users/lume/env_setup_pre_start.log 2>&1; echo done'",
        timeout=180)
    log(f"  install rc={r.return_code} ({time.time()-t0:.1f}s) tail={r.stdout[-200:].strip()!r}")
    if r.return_code != 0:
        log_out = sb.exec_ssh("cat /Users/lume/env_setup_pre_start.log", timeout=10).stdout
        print(log_out)
        sys.exit(f"install_flux.sh failed (rc={r.return_code})")

    log("run setup_flux.sh (post_start hook)")
    t0 = time.time()
    r = sb.exec_ssh(
        "bash -lc '/Users/lume/workspace/scripts/setup_flux.sh > /Users/lume/env_setup_post_start.log 2>&1; echo done'",
        timeout=60)
    log(f"  setup rc={r.return_code} ({time.time()-t0:.1f}s) tail={r.stdout[-200:].strip()!r}")
    if r.return_code != 0:
        log_out = sb.exec_ssh("cat /Users/lume/env_setup_post_start.log", timeout=10).stdout
        print(log_out)
        sys.exit(f"setup_flux.sh failed (rc={r.return_code})")

    log(f"run pre_task hook (tasks/{task_id}/setup_task.sh)")
    t0 = time.time()
    r = sb.exec_ssh(
        f"bash -lc '/Users/lume/workspace/tasks/{task_id}/setup_task.sh > /Users/lume/task_pre_task.log 2>&1; echo done'",
        timeout=90)
    log(f"  pre_task rc={r.return_code} ({time.time()-t0:.1f}s) tail={r.stdout[-200:].strip()!r}")
    if r.return_code != 0:
        log_out = sb.exec_ssh("cat /Users/lume/task_pre_task.log", timeout=10).stdout
        print(log_out)
        sys.exit(f"setup_task.sh failed (rc={r.return_code})")

    di = sb.display.get_info()
    log(f"display: {di.width}x{di.height} scale={di.scale}")

    state = {
        "sandbox_id": sid,
        "env_dir": str(ENV_DIR),
        "task_id": task_id,
        "display": [di.width or 1920, di.height or 1080],
        "booted_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    save_state(state)
    log(f"state saved → {STATE}")
    log("session is live")


def cmd_screenshot(args):
    sb, s, cc = get_sandbox()
    out = Path(args.out)
    png = sb.screenshot.take_full_screen()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"saved {len(png)} bytes -> {out}")


def _scale_xy(x, y, from1280, display):
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
        # Use hotkey() rather than press(modifiers=...) — per the
        # 12_macos_environments.md gotcha, press() silently drops modifiers
        # in base-macos. hotkey() honors them.
        sb.keyboard.hotkey(chord)
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
    """Run post_task hook (if declared) then call verifier.py.

    Persists into out-dir: final.png, all hook logs, the export script's
    result JSON (if produced), the agent's output file (if a known
    location is declared in task.json metadata), and the verifier result.
    """
    sb, s, cc = get_sandbox()
    task_id = s["task_id"]
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    task_json_path = ENV_DIR / "tasks" / task_id / "task.json"
    task_info = json.loads(task_json_path.read_text())
    hooks = task_info.get("hooks", {})

    # Final-state screenshot BEFORE post_task (post_task may quit the app).
    try:
        png = sb.screenshot.take_full_screen()
        (out_dir / "before_finalize.png").write_bytes(png)
        log(f"saved before_finalize.png ({len(png)} bytes)")
    except Exception as exc:
        log(f"  before_finalize.png skipped: {exc}")

    # Run post_task hook if declared.
    post_task_path = hooks.get("post_task")
    if post_task_path:
        log(f"running post_task hook ({post_task_path})")
        r = sb.exec_ssh(
            f"bash -lc '{post_task_path} > /Users/lume/task_post_task.log 2>&1; echo done'",
            timeout=int(hooks.get("post_task_timeout", 120)))
        log(f"  post_task rc={r.return_code}")
        try:
            sb.download_file("/Users/lume/task_post_task.log", str(out_dir / "task_post_task.log"))
        except Exception:
            pass
        # Pull the export result JSON if the task wrote one.
        export_remote = f"/tmp/{task_id}_result.json"
        try:
            sb.download_file(export_remote, str(out_dir / "export_result_json.json"))
            log(f"  saved export_result_json.json from {export_remote}")
        except Exception as exc:
            log(f"  export json fetch skipped: {exc}")

    # Post-finalize screenshot (different from before-finalize because the
    # post_task hook often quits the app).
    try:
        png = sb.screenshot.take_full_screen()
        (out_dir / "final.png").write_bytes(png)
        log(f"saved final.png ({len(png)} bytes)")
    except Exception as exc:
        log(f"  final.png skipped: {exc}")

    # Pull the hook logs that were written during boot.
    for name in ("env_setup_pre_start.log", "env_setup_post_start.log",
                 "task_pre_task.log"):
        try:
            sb.download_file(f"/Users/lume/{name}", str(out_dir / name))
        except Exception:
            pass

    # Load and call the verifier.
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

    def exec_capture(cmd):
        return sb.exec_ssh(cmd, timeout=60).stdout

    def copy_from_env(remote, local):
        sb.download_file(remote, local)

    env_info = {"exec_capture": exec_capture, "copy_from_env": copy_from_env}

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


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="subcommand", required=True)

    s = sp.add_parser("boot"); s.add_argument("--task-id", default=None)
    s = sp.add_parser("screenshot"); s.add_argument("out")
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
        "boot": cmd_boot, "screenshot": cmd_screenshot,
        "click": cmd_click, "move": cmd_move, "type": cmd_type, "key": cmd_key,
        "exec": cmd_exec, "readfile": cmd_readfile,
        "finalize": cmd_finalize, "destroy": cmd_destroy, "status": cmd_status,
    }[args.subcommand](args)


if __name__ == "__main__":
    main()
