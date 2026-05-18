"""Verifier for raycast_snippet_placeholders_live.

Tests both (a) that the snippets are configured with the right placeholder
syntax (via the snippets export) AND (b) that the live expansion actually
worked (via the resulting TextEdit file).

Scoring (100 pts, pass >= 70):
  C1 — snippets_live.raycastsnippets exists, new, valid JSON,
       contains >= 3 snippets                                          15 pts
  C2 — !iso snippet text contains {date...} placeholder token          10 pts
  C3 — !sig snippet text contains {cursor} placeholder token           10 pts
  C4 — !rev snippet text contains {clipboard} placeholder token        10 pts
  C5 — snippet_test.txt exists and is new                              15 pts
  C6 — snippet_test.txt contains today's date in YYYY-MM-DD             15 pts
        (taken from setup-recorded VM-local today)
  C7 — snippet_test.txt contains 'Best,' and 'Claude'                  10 pts
        (proof of !sig expansion)
  C8 — snippet_test.txt contains 'Reviewing:' and 'PR #42'             15 pts
        (proof of !rev expansion with clipboard substitution)

Do-nothing: nothing written -> 0.
Stored snippets only (no live expansion) -> max 45.
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_snip_file_valid":   15,
    "C2_iso_placeholder":   10,
    "C3_cursor_placeholder":10,
    "C4_clip_placeholder":  10,
    "C5_exp_file_exists":   15,
    "C6_today_date":        15,
    "C7_sig_expansion":     10,
    "C8_rev_expansion":     15,
}

ISO_DATE_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b")


def _find_snippet_by_keyword(snippets, keyword):
    target = keyword.strip().lower()
    for s in snippets:
        if (s.get("keyword") or "").strip().lower() == target:
            return s
    return None


def _has_placeholder(text, token):
    """Check that text contains {token...} placeholder (case-insensitive)."""
    pattern = re.compile(rf"\{{\s*{re.escape(token)}[^}}]*\}}", re.IGNORECASE)
    return bool(pattern.search(text))


def verify_snippet_placeholders_live(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_snippet_placeholders_live_result.json"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()

    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
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

    snip_exists = result.get("snip_file_exists", False)
    snip_is_new = result.get("snip_file_is_new", False)
    snip_valid  = result.get("snip_valid_json", False)
    snippets    = result.get("snippets", []) or []
    today       = result.get("today_iso", "") or ""

    # C1 — snippets file valid with >= 3 snippets
    if snip_exists and snip_is_new and snip_valid and len(snippets) >= 3:
        score += CRITERION_POINTS["C1_snip_file_valid"]
        subscores["C1"] = CRITERION_POINTS["C1_snip_file_valid"]
        feedback.append(f"C1 PASS: snippets export valid with {len(snippets)} snippet(s)")
    else:
        subscores["C1"] = 0
        if not snip_exists:
            feedback.append("C1 FAIL: snippets_live.raycastsnippets not found")
        elif not snip_is_new:
            feedback.append("C1 FAIL: snippets export is stale")
        elif not snip_valid:
            feedback.append("C1 FAIL: snippets export is not valid JSON")
        else:
            feedback.append(f"C1 FAIL: only {len(snippets)} snippets (need >= 3)")

    # C2, C3, C4 — placeholder syntax in each snippet
    iso_snip = _find_snippet_by_keyword(snippets, "!iso")
    sig_snip = _find_snippet_by_keyword(snippets, "!sig")
    rev_snip = _find_snippet_by_keyword(snippets, "!rev")

    if iso_snip and _has_placeholder(iso_snip["text"], "date"):
        score += CRITERION_POINTS["C2_iso_placeholder"]
        subscores["C2"] = CRITERION_POINTS["C2_iso_placeholder"]
        feedback.append("C2 PASS: !iso has {date...} placeholder")
    else:
        subscores["C2"] = 0
        feedback.append("C2 FAIL: !iso snippet missing or has no {date...} placeholder")

    if sig_snip and _has_placeholder(sig_snip["text"], "cursor"):
        score += CRITERION_POINTS["C3_cursor_placeholder"]
        subscores["C3"] = CRITERION_POINTS["C3_cursor_placeholder"]
        feedback.append("C3 PASS: !sig has {cursor} placeholder")
    else:
        subscores["C3"] = 0
        feedback.append("C3 FAIL: !sig snippet missing or has no {cursor} placeholder")

    if rev_snip and _has_placeholder(rev_snip["text"], "clipboard"):
        score += CRITERION_POINTS["C4_clip_placeholder"]
        subscores["C4"] = CRITERION_POINTS["C4_clip_placeholder"]
        feedback.append("C4 PASS: !rev has {clipboard} placeholder")
    else:
        subscores["C4"] = 0
        feedback.append("C4 FAIL: !rev snippet missing or has no {clipboard} placeholder")

    # C5 — expansion file exists
    exp_exists  = result.get("exp_file_exists", False)
    exp_is_new  = result.get("exp_file_is_new", False)
    exp_content = result.get("exp_content", "") or ""

    if exp_exists and exp_is_new:
        score += CRITERION_POINTS["C5_exp_file_exists"]
        subscores["C5"] = CRITERION_POINTS["C5_exp_file_exists"]
        feedback.append(f"C5 PASS: snippet_test.txt exists ({result.get('exp_file_size_bytes',0)} bytes)")
    else:
        subscores["C5"] = 0
        if not exp_exists:
            feedback.append("C5 FAIL: snippet_test.txt not found")
        else:
            feedback.append("C5 FAIL: snippet_test.txt is stale")

    # Gate further expansion checks on the file existing
    if exp_exists and exp_is_new:
        # C6 — today's date present (use VM-recorded today, fall back to any YYYY-MM-DD)
        date_match = False
        if today and today in exp_content:
            date_match = True
            feedback.append(f"C6 PASS: today's date '{today}' found in expansion file")
        elif ISO_DATE_RE.search(exp_content):
            # Some flexibility — any ISO date counts (date could have ticked over midnight)
            date_match = True
            feedback.append("C6 PASS: an ISO date (YYYY-MM-DD) found in expansion file")
        if date_match:
            score += CRITERION_POINTS["C6_today_date"]
            subscores["C6"] = CRITERION_POINTS["C6_today_date"]
        else:
            subscores["C6"] = 0
            feedback.append("C6 FAIL: no ISO date in expansion file (!iso did not expand)")

        # C7 — !sig expansion
        if "Best," in exp_content and "Claude" in exp_content:
            score += CRITERION_POINTS["C7_sig_expansion"]
            subscores["C7"] = CRITERION_POINTS["C7_sig_expansion"]
            feedback.append("C7 PASS: !sig expansion found ('Best,' and 'Claude' present)")
        else:
            subscores["C7"] = 0
            feedback.append("C7 FAIL: !sig expansion missing ('Best,' or 'Claude' not in file)")

        # C8 — !rev expansion with PR #42
        if "Reviewing:" in exp_content and "PR #42" in exp_content:
            score += CRITERION_POINTS["C8_rev_expansion"]
            subscores["C8"] = CRITERION_POINTS["C8_rev_expansion"]
            feedback.append("C8 PASS: !rev expansion with clipboard 'PR #42' found")
        else:
            subscores["C8"] = 0
            feedback.append("C8 FAIL: !rev expansion missing ('Reviewing:' or 'PR #42' not in file)")
    else:
        for key in ["C6", "C7", "C8"]:
            subscores[key] = 0
            feedback.append(f"{key} SKIP: expansion file not available")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "snippet_count": len(snippets),
    }
