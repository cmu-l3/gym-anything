"""Verifier for raycast_clipboard_pipeline.

Scoring (100 pts, pass >= 70):
  C1 — clipboard_test.txt exists and is new                   15 pts
  C2 — File content contains 'alpha'                          12 pts
  C3 — File content contains 'beta'                           12 pts
  C4 — File content contains 'gamma'                          12 pts
  C5 — All three appear in original order                      9 pts
       (index of 'alpha' < 'beta' < 'gamma' in the text)
  C6 — snippets.raycastsnippets exists, is new, valid JSON,
       contains at least 1 snippet                            15 pts
  C7 — A snippet with keyword '!greek' exists AND its text
       is exactly 'beta' (case-insensitive, trimmed)          25 pts

Note: 'beta' appears in the text file twice ideally
(once as the pasted clipboard item, once if the agent typed it).
We only require its presence + ordering.
"""

import json
import os
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_clip_file_exists":   15,
    "C2_alpha":              12,
    "C3_beta":               12,
    "C4_gamma":              12,
    "C5_order":               9,
    "C6_snip_file_valid":    15,
    "C7_snippet_greek_beta": 25,
}


def verify_clipboard_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_clipboard_pipeline_result.json"
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

    clip_exists = result.get("clip_file_exists", False)
    clip_is_new = result.get("clip_file_is_new", False)
    clip_content = result.get("clip_content", "") or ""

    # C1
    if clip_exists and clip_is_new:
        score += CRITERION_POINTS["C1_clip_file_exists"]
        subscores["C1"] = CRITERION_POINTS["C1_clip_file_exists"]
        feedback.append(f"C1 PASS: clipboard_test.txt exists ({result.get('clip_file_size_bytes',0)} bytes)")
    else:
        subscores["C1"] = 0
        if not clip_exists:
            feedback.append("C1 FAIL: clipboard_test.txt not found on Desktop")
        else:
            feedback.append("C1 FAIL: clipboard_test.txt is stale (predates task start)")

    if clip_exists and clip_is_new:
        content_lower = clip_content.lower()
        # C2, C3, C4 — presence of each token
        for crit_key, label, token in [
            ("C2_alpha", "C2", "alpha"),
            ("C3_beta",  "C3", "beta"),
            ("C4_gamma", "C4", "gamma"),
        ]:
            if token in content_lower:
                pts = CRITERION_POINTS[crit_key]
                score += pts
                subscores[label] = pts
                feedback.append(f"{label} PASS: '{token}' present")
            else:
                subscores[label] = 0
                feedback.append(f"{label} FAIL: '{token}' not in file")

        # C5 — original order
        idx_alpha = content_lower.find("alpha")
        idx_beta  = content_lower.find("beta")
        idx_gamma = content_lower.find("gamma")
        if 0 <= idx_alpha < idx_beta < idx_gamma:
            score += CRITERION_POINTS["C5_order"]
            subscores["C5"] = CRITERION_POINTS["C5_order"]
            feedback.append("C5 PASS: alpha/beta/gamma appear in original order")
        else:
            subscores["C5"] = 0
            feedback.append(
                f"C5 FAIL: order violated (alpha={idx_alpha}, beta={idx_beta}, gamma={idx_gamma})"
            )
    else:
        for key in ["C2", "C3", "C4", "C5"]:
            subscores[key] = 0
            feedback.append(f"{key} SKIP: clipboard output not available")

    # C6 — snippets file
    snip_exists  = result.get("snip_file_exists", False)
    snip_is_new  = result.get("snip_file_is_new", False)
    snip_valid   = result.get("snip_valid_json", False)
    snippets     = result.get("snippets", [])

    if snip_exists and snip_is_new and snip_valid and len(snippets) >= 1:
        score += CRITERION_POINTS["C6_snip_file_valid"]
        subscores["C6"] = CRITERION_POINTS["C6_snip_file_valid"]
        feedback.append(f"C6 PASS: snippets export valid with {len(snippets)} snippet(s)")
    else:
        subscores["C6"] = 0
        if not snip_exists:
            feedback.append("C6 FAIL: snippets.raycastsnippets not found")
        elif not snip_is_new:
            feedback.append("C6 FAIL: snippets export is stale")
        elif not snip_valid:
            feedback.append("C6 FAIL: snippets export is not valid JSON")
        else:
            feedback.append("C6 FAIL: snippets export contains 0 snippets")

    # C7 — keyword '!greek' with text 'beta'
    found = False
    if snippets:
        for s in snippets:
            kw = (s.get("keyword") or "").strip().lower()
            tx = (s.get("text") or "").strip().lower()
            if kw == "!greek" and tx == "beta":
                found = True
                break
    if found:
        score += CRITERION_POINTS["C7_snippet_greek_beta"]
        subscores["C7"] = CRITERION_POINTS["C7_snippet_greek_beta"]
        feedback.append("C7 PASS: snippet '!greek' with text 'beta' present")
    else:
        subscores["C7"] = 0
        if snippets:
            feedback.append("C7 FAIL: no snippet with keyword '!greek' and text 'beta'")
        else:
            feedback.append("C7 FAIL: no snippets to check")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "snippet_count": len(snippets),
    }
