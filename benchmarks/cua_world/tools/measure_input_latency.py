#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import statistics
import time
from pathlib import Path
from typing import Any, Callable

from PIL import Image, ImageDraw

from gym_anything import from_config


ActionFactory = Callable[[], dict[str, Any]]


def _percentile(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = (len(ordered) - 1) * percentile
    lower = int(index)
    upper = min(lower + 1, len(ordered) - 1)
    if lower == upper:
        return ordered[lower]
    weight = index - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def _summary(values: list[float]) -> dict[str, float]:
    if not values:
        return {}
    return {
        "count": len(values),
        "min_ms": min(values),
        "p50_ms": statistics.median(values),
        "p95_ms": _percentile(values, 0.95),
        "max_ms": max(values),
        "mean_ms": statistics.fmean(values),
    }


def _save_image(image, path: Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return str(path)


def _make_contact_sheet(items: list[tuple[str, str]], output_path: Path) -> str:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    thumbs = []
    for title, path in items:
        image = Image.open(path).convert("RGB")
        image.thumbnail((760, 430))
        canvas = Image.new("RGB", (780, 470), "white")
        draw = ImageDraw.Draw(canvas)
        draw.text((8, 8), title, fill="black")
        canvas.paste(image, (8, 34))
        thumbs.append(canvas)

    columns = 2
    rows = (len(thumbs) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * 780, rows * 470), "white")
    for index, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((index % columns) * 780, (index // columns) * 470))
    sheet.save(output_path)
    return str(output_path)


def _ssh(runner, cmd: str, timeout: int = 10) -> tuple[int, str, str]:
    result = runner._ssh_command(cmd, capture=True, timeout=timeout, use_pty=False)
    stdout = result.stdout.decode() if isinstance(result.stdout, bytes) else result.stdout
    stderr = result.stderr.decode() if isinstance(result.stderr, bytes) else result.stderr
    return result.returncode, stdout.strip(), stderr.strip()


def _inject_action_timed(runner, action: dict[str, Any]) -> float:
    start = time.perf_counter_ns()
    runner.inject_action(action)
    return (time.perf_counter_ns() - start) / 1_000_000.0


def _action_factories() -> dict[str, ActionFactory]:
    return {
        "move": lambda: {"mouse": {"move": [700, 420]}},
        "left_click": lambda: {"mouse": {"left_click": [700, 420]}},
        "right_click": lambda: {"mouse": {"right_click": [700, 420]}},
        "middle_click": lambda: {"mouse": {"middle_click": [700, 420]}},
        "double_click": lambda: {"mouse": {"double_click": [700, 420]}},
        "triple_click": lambda: {"mouse": {"triple_click": [700, 420]}},
        "drag": lambda: {"mouse": {"left_click_drag": [[760, 540], [1060, 540]]}},
        "scroll_down": lambda: {"mouse": {"move": [960, 540], "scroll": 3}},
        "scroll_up": lambda: {"mouse": {"move": [960, 540], "scroll": -3}},
        "hotkey": lambda: {"keyboard": {"keys": ["ctrl", "alt", "shift", "f24"]}},
        "text": lambda: {"keyboard": {"text": "FastInput42!"}},
    }


def _time_runner_inject(env, action_factory: ActionFactory) -> float:
    start = time.perf_counter_ns()
    env._runner.inject_action(action_factory())
    return (time.perf_counter_ns() - start) / 1_000_000.0


def _time_env_step(env, action_factory: ActionFactory) -> float:
    start = time.perf_counter_ns()
    env.step([action_factory()], wait_between_actions=0.0)
    return (time.perf_counter_ns() - start) / 1_000_000.0


def _benchmark_actions(env, action_names: list[str], samples: int, warmup: int) -> dict[str, Any]:
    factories = _action_factories()
    results: dict[str, Any] = {}
    for name in action_names:
        factory = factories[name]
        for _ in range(warmup):
            _time_runner_inject(env, factory)
            _time_env_step(env, factory)
        inject_samples = [_time_runner_inject(env, factory) for _ in range(samples)]
        step_samples = [_time_env_step(env, factory) for _ in range(samples)]
        results[name] = {
            "runner_inject_action": _summary(inject_samples),
            "env_step": _summary(step_samples),
        }
    return results


def _verify_xinput_events(env) -> dict[str, Any]:
    runner = env._runner
    log_path = "/tmp/gym_anything_fast_input_xinput.log"
    _ssh(
        runner,
        (
            f"rm -f {log_path}; "
            f"DISPLAY=:1 timeout 3s stdbuf -o0 xinput test-xi2 --root > {log_path} 2>&1 &"
        ),
    )
    time.sleep(0.3)
    actions = [
        {"mouse": {"move": [620, 410]}},
        {"mouse": {"left_click": [620, 410]}},
        {"mouse": {"right_click": [620, 410]}},
        {"mouse": {"middle_click": [620, 410]}},
        {"mouse": {"double_click": [620, 410]}},
        {"mouse": {"triple_click": [620, 410]}},
        {"mouse": {"left_click_drag": [[620, 410], [780, 520]]}},
        {"mouse": {"scroll": 2}},
        {"keyboard": {"text": "Ab9!"}},
        {"keyboard": {"keys": ["ctrl", "a"]}},
    ]
    for action in actions:
        runner.inject_action(action)
    time.sleep(3.1)
    _, log, _ = _ssh(runner, f"cat {log_path}", timeout=10)
    return {
        "motion_events": log.count("Motion"),
        "button_press_events": log.count("ButtonPress"),
        "button_release_events": log.count("ButtonRelease"),
        "key_press_events": log.count("KeyPress"),
        "key_release_events": log.count("KeyRelease"),
        "raw_log_path": log_path,
        "passed": all(
            [
                "Motion" in log,
                "ButtonPress" in log,
                "ButtonRelease" in log,
                "KeyPress" in log,
                "KeyRelease" in log,
            ]
        ),
    }


def _verify_pointer_position(env) -> dict[str, Any]:
    runner = env._runner
    _, before, _ = _ssh(runner, "DISPLAY=:1 xdotool getmouselocation --shell")
    target = [740, 460]
    start = time.perf_counter_ns()
    runner.inject_action({"mouse": {"move": target}})
    dispatch_ms = (time.perf_counter_ns() - start) / 1_000_000.0
    _, after, _ = _ssh(runner, "DISPLAY=:1 xdotool getmouselocation --shell")
    return {
        "target": target,
        "dispatch_ms": dispatch_ms,
        "before": before,
        "after": after,
        "passed": f"X={target[0]}" in after and f"Y={target[1]}" in after,
    }


def _dismiss_google_earth_dialogs(runner) -> None:
    _ssh(
        runner,
        (
            "DISPLAY=:1 bash -lc '"
            "for pattern in \"Start-up Tips\" \"Google Earth - New Folder\" \"New Folder\"; do "
            "for w in $(xdotool search --name \"$pattern\" 2>/dev/null); do "
            "xdotool windowclose $w 2>/dev/null || true; "
            "done; "
            "done; "
            "xdotool key Escape 2>/dev/null || true'"
        ),
        timeout=5,
    )


def _collect_input_device_contract(env) -> dict[str, Any]:
    runner = env._runner
    _, xinput_list, _ = _ssh(runner, "DISPLAY=:1 xinput list --short", timeout=5)
    _, proc_devices, _ = _ssh(runner, "cat /proc/bus/input/devices", timeout=5)
    combined = f"{xinput_list}\n{proc_devices}".lower()
    return {
        "contract": "fast_io QMP input should enter the guest through standard virtual HID devices",
        "xinput_list": xinput_list,
        "proc_bus_input_devices": proc_devices,
        "has_usb_keyboard": "usb keyboard" in combined,
        "has_usb_tablet": "usb tablet" in combined,
        "passed": "usb keyboard" in combined and "usb tablet" in combined,
    }


def _verify_google_earth_search_semantic(env, evidence_dir: Path) -> dict[str, Any]:
    runner = env._runner
    _dismiss_google_earth_dialogs(runner)
    _, window_id, _ = _ssh(
        runner,
        (
            "DISPLAY=:1 bash -lc "
            "'xdotool search --onlyvisible --class google-earth-pro | tail -n 1 || "
            "xdotool search --onlyvisible --name \"Google Earth\" | tail -n 1'"
        ),
        timeout=5,
    )
    if window_id:
        _ssh(runner, f"DISPLAY=:1 xdotool windowactivate {window_id}", timeout=5)

    search_point = [45, 31]
    query = "giza-fast-input"
    before_path = _save_image(env.capture_screenshot_image(), evidence_dir / "google_earth_search_before.png")
    click_dispatch_ms = _inject_action_timed(runner, {"mouse": {"left_click": search_point}})
    clear_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"keys": ["ctrl", "a"]}})
    backspace_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"keys": ["backspace"]}})
    text_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"text": query}})
    after_text_path = _save_image(env.capture_screenshot_image(), evidence_dir / "google_earth_search_after_text.png")
    select_all_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"keys": ["ctrl", "a"]}})
    copy_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"keys": ["ctrl", "c"]}})
    _, clipboard, _ = _ssh(
        runner,
        (
            "DISPLAY=:1 bash -lc '"
            "if command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -o; "
            "elif command -v xsel >/dev/null 2>&1; then xsel -b -o; "
            "else python3 - <<\"PY\"\n"
            "try:\n"
            "    import tkinter as tk\n"
            "    root = tk.Tk()\n"
            "    root.withdraw()\n"
            "    print(root.clipboard_get(), end=\"\")\n"
            "    root.destroy()\n"
            "except Exception:\n"
            "    pass\n"
            "PY\n"
            "fi'"
        ),
        timeout=5,
    )
    after_copy_path = _save_image(env.capture_screenshot_image(), evidence_dir / "google_earth_search_after_copy.png")
    return {
        "evidence_type": "semantic clipboard readback plus screenshots; no pixel-delta pass/fail",
        "search_point": search_point,
        "typed_query": query,
        "clipboard_after_ctrl_a_ctrl_c": clipboard,
        "click_dispatch_ms": click_dispatch_ms,
        "clear_ctrl_a_dispatch_ms": clear_dispatch_ms,
        "backspace_dispatch_ms": backspace_dispatch_ms,
        "text_dispatch_ms": text_dispatch_ms,
        "select_all_dispatch_ms": select_all_dispatch_ms,
        "copy_dispatch_ms": copy_dispatch_ms,
        "before": before_path,
        "after_text": after_text_path,
        "after_copy": after_copy_path,
        "passed": clipboard == query,
    }


def _verify_google_earth_visuals(env, evidence_dir: Path) -> dict[str, Any]:
    runner = env._runner
    _dismiss_google_earth_dialogs(runner)
    time.sleep(0.2)
    _, window_id, _ = _ssh(
        runner,
        (
            "DISPLAY=:1 bash -lc "
            "'xdotool search --onlyvisible --class google-earth-pro | tail -n 1 || "
            "xdotool search --onlyvisible --name \"Google Earth\" | tail -n 1'"
        ),
        timeout=5,
    )
    if window_id:
        _ssh(runner, f"DISPLAY=:1 xdotool windowactivate {window_id}", timeout=5)
    runner.inject_action({"mouse": {"left_click": [850, 558]}})
    time.sleep(0.2)
    runner.inject_action({"keyboard": {"keys": ["esc"]}})
    time.sleep(0.2)
    before = env.capture_screenshot_image()
    scroll_dispatch_ms = _inject_action_timed(runner, {"mouse": {"move": [960, 540], "scroll": -20}})
    time.sleep(0.5)
    after_scroll = env.capture_screenshot_image()
    drag_dispatch_ms = _inject_action_timed(runner, {"mouse": {"left_click_drag": [[960, 540], [1160, 540]]}})
    time.sleep(0.5)
    after_drag = env.capture_screenshot_image()
    before_double_click = env.capture_screenshot_image()
    double_click_dispatch_ms = _inject_action_timed(runner, {"mouse": {"double_click": [960, 540]}})
    time.sleep(0.5)
    after_double_click = env.capture_screenshot_image()
    before_path = _save_image(before, evidence_dir / "google_earth_before.png")
    after_scroll_path = _save_image(after_scroll, evidence_dir / "google_earth_after_scroll_zoom.png")
    after_drag_path = _save_image(after_drag, evidence_dir / "google_earth_after_drag_rotate.png")
    before_double_click_path = _save_image(before_double_click, evidence_dir / "google_earth_before_double_click.png")
    after_double_click_path = _save_image(after_double_click, evidence_dir / "google_earth_after_double_click_zoom.png")
    contact_sheet = _make_contact_sheet(
        [
            ("Google Earth before input", before_path),
            ("After QMP wheel-up scroll: zoom evidence", after_scroll_path),
            ("After QMP drag: globe/camera moved", after_drag_path),
            ("Before QMP double click", before_double_click_path),
            ("After QMP double click: zoom evidence", after_double_click_path),
        ],
        evidence_dir / "google_earth_contact_sheet.png",
    )
    return {
        "evidence_type": "human-review screenshots; no pixel-delta pass/fail",
        "scroll_dispatch_ms": scroll_dispatch_ms,
        "drag_dispatch_ms": drag_dispatch_ms,
        "double_click_dispatch_ms": double_click_dispatch_ms,
        "before": before_path,
        "after_scroll_zoom": after_scroll_path,
        "after_drag_rotate": after_drag_path,
        "before_double_click": before_double_click_path,
        "after_double_click_zoom": after_double_click_path,
        "contact_sheet": contact_sheet,
    }


def _wait_for_gedit_window(runner, timeout_s: float = 12.0) -> str:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        _, window_id, _ = _ssh(
            runner,
            "DISPLAY=:1 xdotool search --onlyvisible --class gedit | tail -n 1",
            timeout=5,
        )
        if window_id:
            window_id = window_id.strip().splitlines()[-1]
            _ssh(
                runner,
                (
                    f"DISPLAY=:1 xdotool windowactivate --sync {window_id} "
                    f"windowfocus --sync {window_id} "
                    f"windowmove {window_id} 145 145 windowsize {window_id} 1050 710"
                ),
                timeout=5,
            )
            time.sleep(4.0)
            _ssh(runner, f"DISPLAY=:1 xdotool windowactivate --sync {window_id} windowfocus --sync {window_id}", timeout=5)
            return window_id
        time.sleep(0.1)
    raise RuntimeError("gedit window did not appear")


def _open_gedit_case(runner, guest_path: str, content: str) -> str:
    _ssh(runner, "DISPLAY=:1 pkill -f 'gedit' || true", timeout=5)
    time.sleep(0.5)
    _ssh(runner, f"cat > {guest_path} <<'EOF'\n{content}EOF\n", timeout=5)
    _ssh(runner, f"DISPLAY=:1 nohup gedit {guest_path} >/tmp/gym_anything_gedit.log 2>&1 &", timeout=5)
    return _wait_for_gedit_window(runner)


def _read_guest_file(runner, guest_path: str) -> str:
    return _ssh(runner, f"cat {guest_path}", timeout=5)[1]


def _save_and_read_until(runner, guest_path: str, expected: str) -> tuple[float, str]:
    save_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"keys": ["ctrl", "s"]}})
    content = ""
    for _ in range(80):
        content = _read_guest_file(runner, guest_path)
        if content == expected:
            break
        time.sleep(0.05)
    return save_dispatch_ms, content


def _verify_gedit_semantic_input(env, evidence_dir: Path) -> dict[str, Any]:
    runner = env._runner
    guest_path = "/tmp/gym_anything_fast_input_semantic.txt"
    base_content = "click-anchor\ndouble beta gamma\ndrag select target\ntriple line target\nright menu target\n"
    cases = [
        (
            "left_click_caret_line1_end",
            "left click places caret at line 1 end, then text is inserted there",
            {"mouse": {"left_click": [312, 224]}},
            {"keyboard": {"text": "-LEFTCLICK"}},
            "click-anchor-LEFTCLICK\ndouble beta gamma\ndrag select target\ntriple line target\nright menu target",
            "left_click_dispatch_ms",
        ),
        (
            "double_click_selects_word_beta",
            "double click selects beta, then text replaces only that word",
            {"mouse": {"double_click": [282, 242]}},
            {"keyboard": {"text": "BETA"}},
            "click-anchor\ndouble BETA gamma\ndrag select target\ntriple line target\nright menu target",
            "double_click_dispatch_ms",
        ),
        (
            "drag_selects_word_select",
            "drag selects word select, then text replaces only that selection",
            {"mouse": {"left_click_drag": [[244, 260], [294, 260]]}},
            {"keyboard": {"text": "DRAGGED"}},
            "click-anchor\ndouble beta gamma\ndrag DRAGGED target\ntriple line target\nright menu target",
            "drag_dispatch_ms",
        ),
        (
            "triple_click_selects_line",
            "triple click selects line 4, then text replaces the line",
            {"mouse": {"triple_click": [255, 278]}},
            {"keyboard": {"text": "TRIPLE_REPLACED"}},
            "click-anchor\ndouble beta gamma\ndrag select target\nTRIPLE_REPLACED\nright menu target",
            "triple_click_dispatch_ms",
        ),
    ]
    results: dict[str, Any] = {
        "guest_path": guest_path,
        "base_content": base_content,
        "coordinates": {
            "text_left_x": 194,
            "line_y": {"line1": 224, "line2": 242, "line3": 260, "line4": 278, "line5": 296},
        },
        "cases": {},
    }
    contact_items: list[tuple[str, str]] = []

    _dismiss_google_earth_dialogs(runner)

    for key, label, mouse_action, text_action, expected, timing_key in cases:
        _open_gedit_case(runner, guest_path, base_content)
        before_path = _save_image(env.capture_screenshot_image(), evidence_dir / f"gedit_{key}_before.png")
        mouse_dispatch_ms = _inject_action_timed(runner, mouse_action)
        _, pointer_after, _ = _ssh(runner, "DISPLAY=:1 xdotool getmouselocation --shell", timeout=5)
        time.sleep(0.1)
        text_dispatch_ms = _inject_action_timed(runner, text_action)
        save_dispatch_ms, content = _save_and_read_until(runner, guest_path, expected)
        after_path = _save_image(env.capture_screenshot_image(), evidence_dir / f"gedit_{key}_after.png")
        results["cases"][key] = {
            timing_key: mouse_dispatch_ms,
            "text_dispatch_ms": text_dispatch_ms,
            "save_dispatch_ms": save_dispatch_ms,
            "pointer_after_mouse_action": pointer_after,
            "expected_content": expected,
            "content_after_save": content,
            "passed": content == expected,
            "before": before_path,
            "after": after_path,
        }
        contact_items.extend([(f"{label}: before", before_path), (f"{label}: after", after_path)])

    keyboard_expected = "HOTKEY_REPLACED"
    _open_gedit_case(runner, guest_path, "")
    keyboard_before_path = _save_image(env.capture_screenshot_image(), evidence_dir / "gedit_keyboard_before.png")
    click_dispatch_ms = _inject_action_timed(runner, {"mouse": {"left_click": [194, 224]}})
    text_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"text": "FastInput42!"}})
    select_all_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"keys": ["ctrl", "a"]}})
    replace_dispatch_ms = _inject_action_timed(runner, {"keyboard": {"text": keyboard_expected}})
    save_dispatch_ms, content = _save_and_read_until(runner, guest_path, keyboard_expected)
    keyboard_after_path = _save_image(env.capture_screenshot_image(), evidence_dir / "gedit_keyboard_after.png")
    results["cases"]["keyboard_text_and_ctrl_a"] = {
        "click_dispatch_ms": click_dispatch_ms,
        "text_dispatch_ms": text_dispatch_ms,
        "ctrl_a_dispatch_ms": select_all_dispatch_ms,
        "replacement_text_dispatch_ms": replace_dispatch_ms,
        "save_dispatch_ms": save_dispatch_ms,
        "expected_content": keyboard_expected,
        "content_after_save": content,
        "passed": content == keyboard_expected,
        "before": keyboard_before_path,
        "after": keyboard_after_path,
    }
    contact_items.extend(
        [
            ("keyboard text + Ctrl+A: before", keyboard_before_path),
            ("keyboard text + Ctrl+A: saved replacement", keyboard_after_path),
        ]
    )

    _open_gedit_case(runner, guest_path, base_content)
    right_before_path = _save_image(env.capture_screenshot_image(), evidence_dir / "gedit_right_click_before.png")
    right_click_dispatch_ms = _inject_action_timed(runner, {"mouse": {"right_click": [300, 296]}})
    _, pointer_after, _ = _ssh(runner, "DISPLAY=:1 xdotool getmouselocation --shell", timeout=5)
    time.sleep(0.5)
    right_after_path = _save_image(env.capture_screenshot_image(), evidence_dir / "gedit_right_click_after.png")
    results["cases"]["right_click_context_menu"] = {
        "evidence_type": "human-review screenshot; context menu should be visibly open",
        "right_click_dispatch_ms": right_click_dispatch_ms,
        "pointer_after_mouse_action": pointer_after,
        "before": right_before_path,
        "after": right_after_path,
    }
    contact_items.extend(
        [
            ("right click: before", right_before_path),
            ("right click: context menu after QMP right click", right_after_path),
        ]
    )
    checked_cases = [key for key, *_ in cases] + ["keyboard_text_and_ctrl_a"]
    results["semantic_checks_passed"] = all(results["cases"][key]["passed"] for key in checked_cases)
    results["contact_sheet"] = _make_contact_sheet(contact_items, evidence_dir / "gedit_semantic_contact_sheet.png")
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark and verify fast QEMU input latency.")
    parser.add_argument("--env-dir", default="benchmarks/cua_world/environments/google_earth_env")
    parser.add_argument("--task", default="take_screenshot")
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--warmup", type=int, default=3)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument(
        "--actions",
        default="move,left_click,right_click,middle_click,double_click,triple_click,drag,scroll_down,hotkey,text",
    )
    parser.add_argument("--use-cache", action="store_true")
    parser.add_argument("--cache-level", default="post_task")
    parser.add_argument("--use-savevm", action="store_true")
    parser.add_argument("--output-json")
    parser.add_argument("--evidence-dir")
    args = parser.parse_args()

    action_names = [name.strip() for name in args.actions.split(",") if name.strip()]
    evidence_dir = Path(args.evidence_dir or Path(args.env_dir) / "artifacts" / "fast_input_evidence")
    output_json = Path(args.output_json or evidence_dir / "fast_input_latency.json")

    env = from_config(args.env_dir, task_id=args.task, fast_io=True)
    results: dict[str, Any] = {
        "env_dir": args.env_dir,
        "task": args.task,
        "samples": args.samples,
        "warmup": args.warmup,
        "backend": os.environ.get("GYM_ANYTHING_QEMU_FAST_IO_BACKEND", "qmp"),
        "actions": action_names,
        "timer_boundaries": {
            "runner_inject_action": (
                "starts immediately before env._runner.inject_action(action), ends after it returns; "
                "this includes QMP socket flush/ack but is not an app-consumed boundary"
            ),
            "env_step": (
                "starts immediately before env.step([action], wait_between_actions=0.0), "
                "ends after obs is returned"
            ),
        },
        "evidence_note": (
            "Semantic gedit file-content checks and contact-sheet screenshots are used to prove app-level "
            "effects; pixel deltas are not used as pass/fail evidence."
        ),
    }
    try:
        reset_start = time.perf_counter_ns()
        env.reset(
            seed=args.seed,
            use_cache=args.use_cache,
            cache_level=args.cache_level,
            use_savevm=args.use_savevm,
        )
        env.set_episode_limits(max_steps=None, timeout_sec=None)
        results["reset_ms"] = (time.perf_counter_ns() - reset_start) / 1_000_000.0
        _dismiss_google_earth_dialogs(env._runner)
        results["evidence"] = {
            "input_device_contract": _collect_input_device_contract(env),
            "pointer_position": _verify_pointer_position(env),
            "google_earth_search_semantic": _verify_google_earth_search_semantic(env, evidence_dir),
            "google_earth_visuals": _verify_google_earth_visuals(env, evidence_dir),
            "gedit_semantic_input": _verify_gedit_semantic_input(env, evidence_dir),
            "xinput_events": _verify_xinput_events(env),
        }
        results["latency"] = _benchmark_actions(env, action_names, args.samples, args.warmup)
    finally:
        env._finalized = True
        env.close()

    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
