"""Verifier for save_notion_window_screenshot (notion_env / macOS).

Scoring (100 points, pass at 75):
- 10 pts  C1  A .png file was created (or modified) under ~/Desktop or
              ~/Documents during this task — i.e. fresh (mtime > task_start).
-  5 pts  C2  That file starts with the PNG magic bytes
              89 50 4E 47 0D 0A 1A 0A.
-  5 pts  C3  File size ≥ 30 KB AND ≤ 8 MB (sanity-check for a real screen
              capture, not an empty placeholder and not a huge non-screen
              asset).
- 20 pts  C4  macOS extended attribute
              `com.apple.metadata:kMDItemIsScreenCapture` is set to True,
              i.e. the file was produced by macOS's screencapture utility
              (CLI, Cmd+Shift+3/4/5 chord, or the Screenshot.app toolbar).
              This defeats the "copy any random PNG" gaming path.
- 30 pts  C5  `com.apple.metadata:kMDItemScreenCaptureType` xattr equals
              "window" — i.e. the capture was specifically a window-mode
              screencap (not the full-display capture you get from `-x`).
- 30 pts  C6  PNG dimensions plausibly depict an application window —
              width ≥ 400 AND height ≥ 300 AND aspect ratio ≤ 5:1.
              This rejects the menu-bar gaming path (1920×24, aspect 80:1)
              and other tiny system-chrome captures (tooltips, dock items,
              status-bar overlays) that macOS technically reports as
              "Notion-owned window" when the app is frontmost.

Pass: 75/100. The do-nothing trajectory (no file created) scores 0 — no
env-state baseline credit. The maximum score for ANY scenario that does
not earn C6 (= small/non-window-shaped capture, including the menu bar)
is 70 — strictly below the 75 pass threshold. Likewise, the maximum
score for any scenario without C5 (display/region capture) is 70. Only
a fresh window-mode screencap of a properly-window-sized region passes.

Partial-credit safety (Anti-Pattern 4): all criteria are binary (0 or
full). Max-without-C5 = 10+5+5+20+0+30 = 70 < 75. Max-without-C6 =
10+5+5+20+30+0 = 70 < 75. Either gate alone is decisive.

Strategy enumeration (full table in README.md):
- Do-nothing                                        :  0                            →  fail
- `touch ~/Desktop/foo.png` (empty fresh)           : 10                            →  fail
- `cp <somefile.png> ~/Documents/x.png`             : 10 + 5 + 5      + 30* = 50    →  fail
- Menu-bar capture (1920x24, sc_type='window')      : 10 + 5 + 5 + 20 + 30 + 0 = 70 →  fail (C6 fails)
- `screencapture -x ~/Desktop/full.png`             : 10 + 5 + 5 + 20      + 30 = 70 →  fail (C5 fails)
- `screencapture -w ~/Desktop/w.png` (window body)  : 10 + 5 + 5 + 20 + 30 + 30 = 100→  PASS

(*) C6 may or may not fire on a copied PNG, depending on dimensions —
either way the total is below 75 because C4 and C5 are zero.

Read pattern: copy_from_env(/tmp/save_notion_window_screenshot_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List, Optional, Tuple


logger = logging.getLogger(__name__)

# Default thresholds — overridable via task_info["metadata"] so a new task
# variant doesn't require editing this file. (See task.json's metadata block.)
DEFAULT_PASS_THRESHOLD = 75
DEFAULT_MAX_FILE_BYTES = 8 * 1024 * 1024     # 8 MB
DEFAULT_MIN_FILE_BYTES = 30 * 1024           # 30 KB
DEFAULT_MIN_WIDTH = 400
DEFAULT_MIN_HEIGHT = 300
DEFAULT_MAX_ASPECT_RATIO = 5.0
DEFAULT_REQUIRED_CAPTURE_TYPE = "window"
REMOTE_RESULT = "/tmp/save_notion_window_screenshot_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "file_fresh": 0,
        "png_magic": 0,
        "size_ok": 0,
        "is_screencapture": 0,
        "capture_type_window": 0,
        "dimensions_windowlike": 0,
    }


def _dimensions_pass(
    dims: Optional[List[int]], min_w: int, min_h: int, max_aspect: float
) -> Tuple[bool, str]:
    """Return (passes, human-readable reason)."""
    if not dims or len(dims) != 2:
        return False, "dimensions missing or malformed"
    w, h = int(dims[0]), int(dims[1])
    if w < min_w or h < min_h:
        return False, f"dimensions {w}x{h} below minimum {min_w}x{min_h}"
    if h == 0:
        return False, "height zero"
    aspect = max(w / h, h / w)
    if aspect > max_aspect:
        return False, f"aspect ratio {aspect:.1f}:1 exceeds {max_aspect}:1 limit"
    return True, f"dimensions {w}x{h} (aspect {aspect:.2f}:1) within window range"


def verify_save_notion_window_screenshot(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj
    md = (task_info or {}).get("metadata") or {}
    pass_threshold = int(md.get("pass_threshold", DEFAULT_PASS_THRESHOLD))
    min_bytes = int(md.get("min_file_bytes", DEFAULT_MIN_FILE_BYTES))
    max_bytes = int(md.get("max_file_bytes", DEFAULT_MAX_FILE_BYTES))
    min_w = int(md.get("min_width", DEFAULT_MIN_WIDTH))
    min_h = int(md.get("min_height", DEFAULT_MIN_HEIGHT))
    max_aspect = float(md.get("max_aspect_ratio", DEFAULT_MAX_ASPECT_RATIO))
    required_type = md.get("required_capture_type", DEFAULT_REQUIRED_CAPTURE_TYPE)

    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {
            "score": 0, "passed": False,
            "feedback": "env_info missing copy_from_env",
            "subscores": _empty_subscores(),
        }

    # Read the export script's result JSON from the sandbox.
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {
                "score": 0, "passed": False,
                "feedback": f"Could not retrieve result file from sandbox: {exc}",
                "subscores": _empty_subscores(),
            }
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {
                "score": 0, "passed": False,
                "feedback": f"Export produced unparseable JSON: {exc}",
                "subscores": _empty_subscores(),
            }
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    chosen = data.get("chosen") or {}
    candidates_inspected: List[Dict[str, Any]] = data.get("candidates_inspected") or []

    subscores = _empty_subscores()
    feedback: List[str] = []

    # ---- Gate: no candidate at all → 0. ----
    if not chosen:
        return {
            "score": 0, "passed": False,
            "feedback": (
                f"FAILED (0/100): no .png candidate found in search dirs "
                f"({len(candidates_inspected)} candidate(s) inspected). "
                f"Use macOS screencapture (window mode) and save to ~/Desktop or ~/Documents."
            ),
            "subscores": subscores,
        }

    fresh = bool(chosen.get("fresh", False))
    size = int(chosen.get("size") or 0)
    is_png = bool(chosen.get("is_png_magic", False))
    is_sc = bool(chosen.get("is_screencapture", False))
    sc_type = chosen.get("screencapture_type")
    dims = chosen.get("dimensions")
    path = chosen.get("path", "<unknown>")

    # ---- C1: fresh file in search dirs (10 pts) ----
    if fresh:
        subscores["file_fresh"] = 10
        feedback.append(f"Fresh .png at {path} (+10)")
    else:
        feedback.append(
            f"Most recent candidate {path} is NOT fresh "
            f"(mtime predates task_start) (+0)"
        )

    # ---- C2: PNG magic bytes (5 pts) ----
    if is_png:
        subscores["png_magic"] = 5
        feedback.append("Valid PNG magic bytes (+5)")
    else:
        feedback.append("File does not have PNG magic bytes (+0)")

    # ---- C3: size in [min_bytes, max_bytes] (5 pts) ----
    if min_bytes <= size <= max_bytes:
        subscores["size_ok"] = 5
        feedback.append(f"Size {size} bytes within sane window (+5)")
    elif size > 0:
        feedback.append(
            f"Size {size} bytes outside [{min_bytes}, {max_bytes}] (+0)"
        )
    else:
        feedback.append("Size 0 / unknown (+0)")

    # ---- C4: kMDItemIsScreenCapture xattr (20 pts), gated on fresh ----
    if fresh and is_sc:
        subscores["is_screencapture"] = 20
        feedback.append(
            "kMDItemIsScreenCapture xattr present (+20) — file produced "
            "by macOS screencapture utility"
        )
    elif is_sc:
        feedback.append(
            "kMDItemIsScreenCapture xattr present but file is stale (+0)"
        )
    else:
        feedback.append("kMDItemIsScreenCapture xattr missing (+0)")

    # ---- C5: kMDItemScreenCaptureType == required_type (30 pts) ----
    if fresh and is_sc and sc_type == required_type:
        subscores["capture_type_window"] = 30
        feedback.append(
            f"kMDItemScreenCaptureType={required_type} — {required_type}-mode capture (+30)"
        )
    elif fresh and is_sc and sc_type:
        feedback.append(
            f"kMDItemScreenCaptureType={sc_type!r} (not {required_type!r}) — "
            f"did the agent capture the full display or a region? (+0)"
        )
    elif sc_type:
        feedback.append(
            f"kMDItemScreenCaptureType={sc_type!r} but file is stale "
            f"or not flagged as screencapture (+0)"
        )
    else:
        feedback.append(
            "kMDItemScreenCaptureType not set (no screencap or window flag) (+0)"
        )

    # ---- C6: dimensions look like an application window (30 pts) ----
    # Rejects the menu-bar gaming path: macOS reports a 1920x24 menu-bar
    # screencap as kMDItemScreenCaptureType="window" because the menu bar
    # IS a window owned by the frontmost app. The actual Notion login
    # window is ~1432x972; any non-degenerate application window will be
    # at least 400x300 with aspect ratio < 5:1. Gated on fresh to keep the
    # criterion meaningful (a stale matching-dims file gets no credit).
    if fresh:
        dims_ok, dims_reason = _dimensions_pass(dims, min_w, min_h, max_aspect)
        if dims_ok:
            subscores["dimensions_windowlike"] = 30
            feedback.append(f"Dimensions plausibly an app window: {dims_reason} (+30)")
        else:
            feedback.append(
                f"Dimensions reject — {dims_reason}. "
                f"Likely a menu-bar / tooltip / dock-item capture, not an "
                f"actual application window. (+0)"
            )
    else:
        feedback.append("Dimensions check skipped (file is stale) (+0)")

    total = sum(subscores.values())
    passed = total >= pass_threshold
    headline = (
        f"PASSED ({total}/100): window-mode screenshot of the Notion "
        f"application window captured by macOS screencapture utility."
        if passed
        else f"FAILED ({total}/100): pass threshold {pass_threshold}."
    )
    feedback.insert(0, headline)
    return {
        "score": total,
        "passed": passed,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
