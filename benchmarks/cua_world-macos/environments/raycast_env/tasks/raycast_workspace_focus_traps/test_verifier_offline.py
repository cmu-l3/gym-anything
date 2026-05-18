"""Offline unit tests for verify_workspace_focus_traps."""

import importlib.util
import json
import os

_spec = importlib.util.spec_from_file_location(
    "verifier",
    os.path.join(os.path.dirname(__file__), "verifier.py"),
)
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)


def _make_env(result_data):
    def copy_from_env(src, dst):
        with open(dst, "w") as f:
            json.dump(result_data, f)
    return {"copy_from_env": copy_from_env}


def _make_env_missing():
    def copy_from_env(src, dst):
        raise FileNotFoundError(src)
    return {"copy_from_env": copy_from_env}


NOW = 1748300000
SCREEN = [0, 0, 1920, 1080]
# Initial frame for lease-old.pdf (set during setup, before agent action)
LEASE_OLD_INITIAL = [400, 200, 800, 600]


def _wins(*tuples):
    """Build window dicts from (title, x, y, w, h, minimized) tuples."""
    return [
        {"title": t[0], "x": t[1], "y": t[2], "w": t[3], "h": t[4],
         "minimized": (t[5] if len(t) > 5 else False)}
        for t in tuples
    ]


CORRECT_STATE = {
    "task_start":             NOW,
    "frontmost_app":          "Safari",
    "screen_bounds":          SCREEN,
    "lease_old_initial_frame": LEASE_OLD_INITIAL,
    "safari_windows":         _wins(("Safari", 0, 25, 960, 1055)),
    "preview_windows":        _wins(
        ("lease-renewal.pdf", 960, 25, 960, 1055),       # right half
        ("lease-old.pdf",     400, 200, 800, 600),       # untouched
    ),
    "notes_windows":          _wins(("Notes", 960, 540, 960, 540)),  # BR quarter
    "mail_windows":           _wins(("Inbox", 100, 100, 800, 600, True)),  # minimized
    "finder_windows":         _wins(("Home", 50, 50, 700, 500)),
    "raycast_windows":        _wins(("Raycast AI Chat", 760, 340, 400, 400)),
    "finder_visible_current_space": False,  # moved to next Space
}


def test_missing_result_file():
    r = mod.verify_workspace_focus_traps([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_all_correct():
    r = mod.verify_workspace_focus_traps([], _make_env(CORRECT_STATE), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_do_nothing():
    """Agent did nothing — everything at default (no specific positions, no front Safari)."""
    state = dict(CORRECT_STATE)
    state["frontmost_app"] = "Finder"
    state["safari_windows"] = _wins(("Safari", 400, 100, 800, 600))    # not left half
    state["preview_windows"] = _wins(
        ("lease-renewal.pdf", 500, 200, 700, 500),  # not right half
        ("lease-old.pdf",     400, 200, 800, 600),  # still at initial
    )
    state["notes_windows"] = _wins(("Notes", 100, 100, 600, 400))      # not BR quarter
    state["mail_windows"] = _wins(("Inbox", 100, 100, 800, 600, False)) # not minimized
    state["finder_visible_current_space"] = True
    r = mod.verify_workspace_focus_traps([], _make_env(state), {})
    # C1=0, C2=0, C3=0, C4=20 (untouched), C5=0, C6=0, C7=10, C8=0 -> 30
    assert r["score"] == 30, f"Expected 30, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_do_nothing (score={r['score']})")


def test_agent_moved_wrong_preview():
    """Agent positioned lease-OLD on right half (wrong PDF) and touched lease-old."""
    state = dict(CORRECT_STATE)
    state["preview_windows"] = _wins(
        ("lease-renewal.pdf", 400, 200, 800, 600),        # not right half
        ("lease-old.pdf",     960, 25, 960, 1055),        # moved! and on right half
    )
    r = mod.verify_workspace_focus_traps([], _make_env(state), {})
    # C3 fails (renewal not on right half), C4 fails (old moved)
    # Score: 10+15+0+0+10+10+10+10 = 65
    assert r["score"] == 65, f"Expected 65, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_agent_moved_wrong_preview (score={r['score']})")


def test_lease_old_untouched_other_failures():
    """Only the focus-trap part right — agent did nothing else correctly."""
    state = dict(CORRECT_STATE)
    state["frontmost_app"] = "Preview"
    state["safari_windows"] = _wins(("Safari", 400, 100, 800, 600))
    state["preview_windows"] = _wins(
        ("lease-renewal.pdf", 600, 300, 600, 500),
        ("lease-old.pdf",     400, 200, 800, 600),  # untouched
    )
    state["notes_windows"] = _wins(("Notes", 100, 100, 600, 400))
    state["mail_windows"] = _wins(("Inbox", 100, 100, 800, 600, False))
    state["finder_visible_current_space"] = True
    r = mod.verify_workspace_focus_traps([], _make_env(state), {})
    # Only C4 + C7 pass: 0+0+0+20+0+0+10+0 = 30
    assert r["score"] == 30, f"Expected 30, got {r['score']}"
    print(f"PASS test_lease_old_untouched_other_failures (score={r['score']})")


def test_partial_safari_only():
    state = dict(CORRECT_STATE)
    state["preview_windows"] = _wins(
        ("lease-renewal.pdf", 100, 100, 800, 600),  # not right half
        ("lease-old.pdf",     400, 200, 800, 600),  # untouched
    )
    state["notes_windows"] = _wins(("Notes", 100, 100, 600, 400))
    state["mail_windows"] = _wins(("Inbox", 100, 100, 800, 600, False))
    state["finder_visible_current_space"] = True
    r = mod.verify_workspace_focus_traps([], _make_env(state), {})
    # C1=10, C2=15, C3=0, C4=20, C5=0, C6=0, C7=10, C8=0 -> 55
    assert r["score"] == 55, f"Expected 55, got {r['score']}"
    print(f"PASS test_partial_safari_only (score={r['score']})")


def test_raycast_not_open():
    state = dict(CORRECT_STATE)
    state["raycast_windows"] = []
    r = mod.verify_workspace_focus_traps([], _make_env(state), {})
    # C7 fails: 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_raycast_not_open (score={r['score']})")


def test_mail_not_minimized():
    state = dict(CORRECT_STATE)
    state["mail_windows"] = _wins(("Inbox", 100, 100, 800, 600, False))
    r = mod.verify_workspace_focus_traps([], _make_env(state), {})
    # C6 fails: 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    print(f"PASS test_mail_not_minimized (score={r['score']})")


def test_finder_still_visible():
    state = dict(CORRECT_STATE)
    state["finder_visible_current_space"] = True
    r = mod.verify_workspace_focus_traps([], _make_env(state), {})
    # C8 fails: 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    print(f"PASS test_finder_still_visible (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_all_correct()
    test_do_nothing()
    test_agent_moved_wrong_preview()
    test_lease_old_untouched_other_failures()
    test_partial_safari_only()
    test_raycast_not_open()
    test_mail_not_minimized()
    test_finder_still_visible()
    print("\nAll #7 offline tests passed.")
