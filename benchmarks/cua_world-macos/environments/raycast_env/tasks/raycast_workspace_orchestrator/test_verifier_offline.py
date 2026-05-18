"""Offline unit tests for verify_workspace_orchestrator."""

import importlib.util
import json
import os
import tempfile

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

GOOD_SCRIPT = '''#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Workspace Switcher
# @raycast.mode silent
# @raycast.icon 🏠
# @raycast.packageName Workspaces
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title":"Focus","value":"focus"},{"title":"Meeting","value":"meeting"}] }

case "$1" in
  "focus")
    osascript -e 'tell application "Safari" to activate'
    sleep 0.4
    open -g "raycast://extensions/raycast/window-management/left-half"
    sleep 0.3
    osascript -e 'tell application "Notes" to activate'
    sleep 0.4
    open -g "raycast://extensions/raycast/window-management/right-half"
    osascript -e 'set volume output volume 20'
    echo "Focus mode activated"
    ;;
  "meeting")
    osascript -e 'tell application "Safari" to activate'
    sleep 0.4
    open -g "raycast://extensions/raycast/window-management/top-half"
    sleep 0.3
    osascript -e 'tell application "TextEdit" to activate'
    sleep 0.4
    open -g "raycast://extensions/raycast/window-management/bottom-half"
    osascript -e 'set volume output volume 70'
    echo "Meeting mode activated"
    ;;
esac
'''


def _result(content, exists=True, is_new=True, executable=True):
    return {
        "task_start": NOW,
        "script_path": "/Users/lume/Documents/Raycast/Script Commands/Workspace/workspace.sh",
        "script_exists": exists,
        "script_size_bytes": len(content),
        "script_is_new": is_new,
        "script_is_executable": executable,
        "script_content": content,
    }


def test_missing_result_file():
    r = mod.verify_workspace_orchestrator([], _make_env_missing(), {})
    assert r["passed"] is False
    assert r["score"] == 0
    print("PASS test_missing_result_file")


def test_no_script():
    r = mod.verify_workspace_orchestrator([], _make_env(_result("", exists=False, is_new=False, executable=False)), {})
    assert r["passed"] is False
    assert r["score"] == 0
    print("PASS test_no_script")


def test_stale_script():
    r = mod.verify_workspace_orchestrator([], _make_env(_result(GOOD_SCRIPT, is_new=False)), {})
    assert r["passed"] is False
    assert r["score"] == 0, f"Expected 0 (stale), got {r['score']}"
    print(f"PASS test_stale_script (score={r['score']})")


def test_header_only_stub():
    stub = '''#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Stub
# @raycast.mode silent
echo "noop"
'''
    r = mod.verify_workspace_orchestrator([], _make_env(_result(stub)), {})
    # C1=15, C2=10, C3=0, C4=0, C5=0, C6=0 -> 25
    assert r["passed"] is False
    assert r["score"] == 25, f"Expected 25, got {r['score']}"
    print(f"PASS test_header_only_stub (score={r['score']})")


def test_no_deeplink_uses_applescript_only():
    """Agent uses AppleScript for window positioning instead of Raycast deeplinks.
    Should still get partial credit on C4/C5 but C6 fails."""
    script = '''#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Workspace
# @raycast.mode silent
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title":"Focus","value":"focus"},{"title":"Meeting","value":"meeting"}] }

case "$1" in
  "focus")
    osascript -e 'tell application "Safari" to activate'
    osascript -e 'tell application "System Events" to set position of front window of process "Safari" to {0,0}'  # left-half
    osascript -e 'tell application "Notes" to activate'
    osascript -e 'tell application "System Events" to set position of front window of process "Notes" to {800,0}'  # right-half
    osascript -e 'set volume output volume 20'
    ;;
  "meeting")
    osascript -e 'tell application "Safari" to activate'
    osascript -e 'tell application "System Events" to set bounds of front window of process "Safari" to {0,0,1600,400}'  # top-half
    osascript -e 'tell application "TextEdit" to activate'
    osascript -e 'tell application "System Events" to set bounds of front window of process "TextEdit" to {0,400,1600,800}'  # bottom-half
    osascript -e 'set volume output volume 70'
    ;;
esac
'''
    r = mod.verify_workspace_orchestrator([], _make_env(_result(script)), {})
    # C1=15, C2=10, C3=15, C4=25, C5=25, C6=0 -> 90 (still passes — uses comments to mention left/right/top/bottom half)
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_no_deeplink_uses_applescript_only (score={r['score']})")


def test_focus_branch_only():
    """Has Focus branch but Meeting branch is empty stub."""
    script = '''#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Workspace
# @raycast.mode silent
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title":"Focus","value":"focus"},{"title":"Meeting","value":"meeting"}] }

case "$1" in
  "focus")
    osascript -e 'tell application "Safari" to activate'
    open "raycast://extensions/raycast/window-management/left-half"
    osascript -e 'tell application "Notes" to activate'
    open "raycast://extensions/raycast/window-management/right-half"
    osascript -e 'set volume output volume 20'
    ;;
  "meeting")
    echo "todo"
    ;;
esac
'''
    r = mod.verify_workspace_orchestrator([], _make_env(_result(script)), {})
    # C1=15, C2=10, C3=15, C4=25, C5=0 (no Safari/TextEdit/top/bottom/70), C6=10 -> 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_focus_branch_only (score={r['score']})")


def test_all_correct():
    r = mod.verify_workspace_orchestrator([], _make_env(_result(GOOD_SCRIPT)), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_not_executable():
    r = mod.verify_workspace_orchestrator([], _make_env(_result(GOOD_SCRIPT, executable=False)), {})
    # C1=15, C2=0 (not executable), C3=15, C4=25, C5=25, C6=10 -> 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    print(f"PASS test_not_executable (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_no_script()
    test_stale_script()
    test_header_only_stub()
    test_no_deeplink_uses_applescript_only()
    test_focus_branch_only()
    test_all_correct()
    test_not_executable()
    print("\nAll Task 1 offline tests passed.")
