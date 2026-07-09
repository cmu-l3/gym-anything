"""Verifier for raycast_workspace_orchestrator.

Scoring (100 pts, pass >= 70):
  C1 — Script file exists at expected path and is new                     15 pts
  C2 — Script has valid Raycast headers (schemaVersion, title, mode)
       AND is executable                                                  10 pts
  C3 — Script has @raycast.argument1 with type=dropdown AND data contains
       both Focus and Meeting (titles or values)                          15 pts
  C4 — Focus branch contains: Safari + Notes + left-half + right-half
       + volume 20 set                                                    25 pts
  C5 — Meeting branch contains: Safari + TextEdit + top-half + bottom-half
       + volume 70 set                                                    25 pts
  C6 — Script uses at least one
       raycast://extensions/raycast/window-management/ deeplink
       (proves Raycast-native chaining vs pure AppleScript)               10 pts

Do-nothing: C1 fails (no script) -> score = 0.
Wrong-target: script in wrong location -> C1 fails -> score = 0.
Header-only stub: C2 may pass but C3-C6 fail -> max 25 pts.
"""

import json
import logging
import os
import re
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_file_exists_new":      15,
    "C2_headers_executable":   10,
    "C3_dropdown_arg":         15,
    "C4_focus_branch":         25,
    "C5_meeting_branch":       25,
    "C6_window_mgmt_deeplink": 10,
}

WM_DEEPLINK_PREFIX = "raycast://extensions/raycast/window-management/"

# Volume regex matches osascript 'set volume output volume N' or 'set volume N'
VOLUME_RE = lambda n: re.compile(
    rf"set\s+volume(?:\s+output\s+volume)?\s+{n}\b", re.IGNORECASE
)

# Window-mgmt position can be reached via deeplink OR AppleScript window resize.
# We accept either (regex matches the position name appearing in the relevant
# segment of script).
POSITION_PATTERNS = {
    "left-half":   re.compile(r"left[-_ ]?half|leftHalf",   re.IGNORECASE),
    "right-half":  re.compile(r"right[-_ ]?half|rightHalf", re.IGNORECASE),
    "top-half":    re.compile(r"top[-_ ]?half|topHalf",     re.IGNORECASE),
    "bottom-half": re.compile(r"bottom[-_ ]?half|bottomHalf", re.IGNORECASE),
}


def _find_branch_start(content: str, name: str) -> int:
    """Locate the start position of the branch for the given mode name.

    Skips the @raycast.argument1 JSON metadata (which also contains
    "focus" / "meeting") by matching only control-flow constructs:
      - bash case branch:  "name")  'name')  name)
      - bash if/elif:      == "name"   = "name"
    """
    case_pat = re.compile(
        rf'["\']?{re.escape(name)}["\']?\s*\)', re.IGNORECASE
    )
    if_pat = re.compile(
        rf'==?\s*["\']{re.escape(name)}["\']', re.IGNORECASE
    )
    m = case_pat.search(content) or if_pat.search(content)
    return m.start() if m else -1


def _split_branches(content: str):
    """Split content into Focus and Meeting branch segments (case/if aware)."""
    focus_idx   = _find_branch_start(content, "focus")
    meeting_idx = _find_branch_start(content, "meeting")
    if focus_idx < 0 or meeting_idx < 0:
        return "", ""
    if focus_idx < meeting_idx:
        return content[focus_idx:meeting_idx], content[meeting_idx:]
    return content[focus_idx:], content[meeting_idx:focus_idx]


def _check_branch(branch_text: str, primary_app: str, primary_pos: str,
                  secondary_app: str, secondary_pos: str, volume: int):
    """Return (matched_count, details)."""
    checks = {
        f"primary_app_{primary_app}":       primary_app.lower() in branch_text.lower(),
        f"secondary_app_{secondary_app}":   secondary_app.lower() in branch_text.lower(),
        f"primary_pos_{primary_pos}":       bool(POSITION_PATTERNS[primary_pos].search(branch_text)),
        f"secondary_pos_{secondary_pos}":   bool(POSITION_PATTERNS[secondary_pos].search(branch_text)),
        f"volume_{volume}":                 bool(VOLUME_RE(volume).search(branch_text)),
    }
    return sum(checks.values()), checks


def verify_workspace_orchestrator(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_workspace_orchestrator_result.json"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()

    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    subscores = {}

    # C1 — Script exists and is new
    exists = result.get("script_exists", False)
    is_new = result.get("script_is_new", False)
    if exists and is_new:
        score += CRITERION_POINTS["C1_file_exists_new"]
        subscores["C1"] = CRITERION_POINTS["C1_file_exists_new"]
        feedback.append(f"C1 PASS: script exists at expected path ({result.get('script_size_bytes',0)} bytes)")
    else:
        subscores["C1"] = 0
        if not exists:
            feedback.append("C1 FAIL: workspace.sh not found at expected path")
        else:
            feedback.append("C1 FAIL: workspace.sh exists but predates task start (stale file)")

    # Gate: no script -> everything else is N/A
    if not (exists and is_new):
        for key in ["C2", "C3", "C4", "C5", "C6"]:
            subscores[key] = 0
            feedback.append(f"{key} SKIP: script not present")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback),
            "subscores": subscores,
        }

    content = result.get("script_content", "")
    executable = result.get("script_is_executable", False)

    # C2 — Headers + executable
    has_schema = re.search(r"@raycast\.schemaVersion\s+1", content) is not None
    has_title  = re.search(r"@raycast\.title\s+\S+",       content) is not None
    has_mode   = re.search(r"@raycast\.mode\s+\S+",        content) is not None
    if has_schema and has_title and has_mode and executable:
        score += CRITERION_POINTS["C2_headers_executable"]
        subscores["C2"] = CRITERION_POINTS["C2_headers_executable"]
        feedback.append("C2 PASS: valid Raycast headers and script is executable")
    else:
        subscores["C2"] = 0
        missing = []
        if not has_schema: missing.append("@raycast.schemaVersion 1")
        if not has_title:  missing.append("@raycast.title")
        if not has_mode:   missing.append("@raycast.mode")
        if not executable: missing.append("executable bit")
        feedback.append(f"C2 FAIL: missing {', '.join(missing)}")

    # C3 — dropdown argument with Focus + Meeting options
    arg1_line = re.search(r"@raycast\.argument1\s+(.+?)$", content, re.MULTILINE)
    arg1 = None
    if arg1_line:
        arg1_raw = arg1_line.group(1).strip()
        # Extract balanced top-level {...} (regex can't count nesting)
        if arg1_raw.startswith("{"):
            depth = 0
            end_idx = -1
            for i, c in enumerate(arg1_raw):
                if c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        end_idx = i + 1
                        break
            if end_idx > 0:
                try:
                    arg1 = json.loads(arg1_raw[:end_idx])
                except json.JSONDecodeError:
                    arg1 = None
    if arg1 is not None:
        is_dropdown = isinstance(arg1, dict) and arg1.get("type") == "dropdown"
        data = (arg1 or {}).get("data") or []
        titles_lower = [str(d.get("title", "")).lower() for d in data if isinstance(d, dict)]
        values_lower = [str(d.get("value", "")).lower() for d in data if isinstance(d, dict)]
        has_focus   = "focus"   in titles_lower or "focus"   in values_lower
        has_meeting = "meeting" in titles_lower or "meeting" in values_lower
        if is_dropdown and has_focus and has_meeting:
            score += CRITERION_POINTS["C3_dropdown_arg"]
            subscores["C3"] = CRITERION_POINTS["C3_dropdown_arg"]
            feedback.append("C3 PASS: dropdown argument with Focus and Meeting options")
        else:
            subscores["C3"] = 0
            feedback.append(
                f"C3 FAIL: dropdown={is_dropdown}, focus_in_data={has_focus}, "
                f"meeting_in_data={has_meeting}"
            )
    else:
        subscores["C3"] = 0
        feedback.append("C3 FAIL: no @raycast.argument1 metadata found")

    # Split branches
    focus_branch, meeting_branch = _split_branches(content)

    # C4 — Focus branch
    if focus_branch:
        matched, details = _check_branch(
            focus_branch, "Safari", "left-half", "Notes", "right-half", 20
        )
        if matched == 5:
            score += CRITERION_POINTS["C4_focus_branch"]
            subscores["C4"] = CRITERION_POINTS["C4_focus_branch"]
            feedback.append("C4 PASS: Focus branch has all 5 required elements")
        else:
            # Partial credit
            pts = (CRITERION_POINTS["C4_focus_branch"] // 5) * matched
            score += pts
            subscores["C4"] = pts
            missing = [k for k, v in details.items() if not v]
            feedback.append(f"C4 PARTIAL ({matched}/5): missing {missing}")
    else:
        subscores["C4"] = 0
        feedback.append("C4 FAIL: could not locate Focus branch in script")

    # C5 — Meeting branch
    if meeting_branch:
        matched, details = _check_branch(
            meeting_branch, "Safari", "top-half", "TextEdit", "bottom-half", 70
        )
        if matched == 5:
            score += CRITERION_POINTS["C5_meeting_branch"]
            subscores["C5"] = CRITERION_POINTS["C5_meeting_branch"]
            feedback.append("C5 PASS: Meeting branch has all 5 required elements")
        else:
            pts = (CRITERION_POINTS["C5_meeting_branch"] // 5) * matched
            score += pts
            subscores["C5"] = pts
            missing = [k for k, v in details.items() if not v]
            feedback.append(f"C5 PARTIAL ({matched}/5): missing {missing}")
    else:
        subscores["C5"] = 0
        feedback.append("C5 FAIL: could not locate Meeting branch in script")

    # C6 — Window-management deeplink used
    if WM_DEEPLINK_PREFIX in content:
        score += CRITERION_POINTS["C6_window_mgmt_deeplink"]
        subscores["C6"] = CRITERION_POINTS["C6_window_mgmt_deeplink"]
        feedback.append("C6 PASS: script uses Raycast window-management deeplink(s)")
    else:
        subscores["C6"] = 0
        feedback.append(f"C6 FAIL: no '{WM_DEEPLINK_PREFIX}...' deeplink in script")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
