"""Verifier for raycast_quicklink_tab_reuse.

Scoring (100 pts, pass >= 70):
  C1 — Quicklinks export file exists, new, contains >=1 quicklink           15 pts
  C2 — A 'Recipe Search' quicklink exists with duckduckgo.com URL +         25 pts
        named-argument placeholders ({argument name="ingredient"} +
        {argument name="servings"})
  C3 — Exactly ONE Safari tab open (no duplicate created when Quicklink     30 pts
        was invoked — this is the side-effect test)
  C4 — That Safari tab's URL contains 'tofu' AND 'servings=4'/'4+servings'  20 pts
        (the Quicklink was actually invoked with the correct args)
  C5 — Raycast WAL changed (proof Raycast was used)                         10 pts
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_export_exists":     15,
    "C2_quicklink_correct": 25,
    "C3_single_tab":        30,
    "C4_tab_url_correct":   20,
    "C5_raycast_touched":   10,
}

NAMED_ARG_RE = lambda name: re.compile(
    rf'\{{\s*argument[^}}]*name\s*=\s*["\']{re.escape(name)}["\'][^}}]*\}}',
    re.IGNORECASE,
)


def verify_quicklink_tab_reuse(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_quicklink_tab_reuse_result.json"
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

    export_exists = result.get("export_file_exists", False)
    export_new    = result.get("export_file_is_new", False)
    quicklinks    = result.get("quicklinks", []) or []
    tab_urls      = result.get("safari_tab_urls", []) or []
    tab_count     = result.get("safari_tab_count", 0)
    wal_changed   = result.get("raycast_wal_changed_after_setup", False)

    # C1 — export exists
    if export_exists and export_new and len(quicklinks) >= 1:
        score += CRITERION_POINTS["C1_export_exists"]
        subscores["C1"] = CRITERION_POINTS["C1_export_exists"]
        feedback.append(f"C1 PASS: quicklinks export with {len(quicklinks)} entries")
    else:
        subscores["C1"] = 0
        feedback.append("C1 FAIL: my_quicklinks.json missing/stale/empty")

    # C2 — Recipe Search quicklink with correct placeholders
    recipe = None
    for q in quicklinks:
        if "recipe search" in (q.get("name") or "").lower() or "duckduckgo" in (q.get("link") or "").lower():
            recipe = q
            break
    if recipe:
        link = recipe.get("link", "")
        has_ingr = bool(NAMED_ARG_RE("ingredient").search(link))
        has_serv = bool(NAMED_ARG_RE("servings").search(link))
        has_dg   = "duckduckgo.com" in link.lower()
        if has_ingr and has_serv and has_dg:
            score += CRITERION_POINTS["C2_quicklink_correct"]
            subscores["C2"] = CRITERION_POINTS["C2_quicklink_correct"]
            feedback.append("C2 PASS: Recipe Search quicklink with named-arg placeholders")
        else:
            subscores["C2"] = 0
            feedback.append(
                f"C2 FAIL: quicklink missing required pieces "
                f"(ingredient={has_ingr}, servings={has_serv}, duckduckgo={has_dg})"
            )
    else:
        subscores["C2"] = 0
        feedback.append("C2 FAIL: no Recipe Search / duckduckgo quicklink found")

    # C3 — exactly one Safari tab
    if tab_count == 1:
        score += CRITERION_POINTS["C3_single_tab"]
        subscores["C3"] = CRITERION_POINTS["C3_single_tab"]
        feedback.append(f"C3 PASS: exactly 1 Safari tab open (tab reuse worked)")
    else:
        subscores["C3"] = 0
        feedback.append(f"C3 FAIL: {tab_count} Safari tabs (expected 1) — duplicate created")

    # C4 — tab URL has tofu + 4 servings
    correct_url_tab = None
    for url in tab_urls:
        u = url.lower()
        if "tofu" in u and ("servings=4" in u or "4+servings" in u or "4-servings" in u or "/4/" in u):
            correct_url_tab = url
            break
    if correct_url_tab:
        score += CRITERION_POINTS["C4_tab_url_correct"]
        subscores["C4"] = CRITERION_POINTS["C4_tab_url_correct"]
        feedback.append(f"C4 PASS: tab URL has tofu + 4 servings ({correct_url_tab[:60]})")
    else:
        subscores["C4"] = 0
        feedback.append(f"C4 FAIL: no Safari tab with both 'tofu' and '4 servings' (tabs: {tab_urls})")

    # C5 — Raycast WAL changed
    if wal_changed:
        score += CRITERION_POINTS["C5_raycast_touched"]
        subscores["C5"] = CRITERION_POINTS["C5_raycast_touched"]
        feedback.append("C5 PASS: Raycast WAL changed")
    else:
        subscores["C5"] = 0
        feedback.append("C5 FAIL: Raycast WAL unchanged")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
