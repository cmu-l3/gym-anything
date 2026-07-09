"""Verifier for raycast_quicklinks_dynamic.

Scoring (100 pts, pass >= 70):
  C1 — Export file exists at expected path and is new                  15 pts
  C2 — Valid JSON with >= 4 quicklinks                                 15 pts
  C3 — YouTube quicklink: youtube.com URL + a placeholder
       ({Query} or {argument...})                                      15 pts
  C4 — GitHub quicklink: github.com URL + two args, one named
       'keywords' (or generic Query), one named 'language' with
       default 'python'                                                 20 pts
  C5 — Translate quicklink: translate.google.com URL +
       a {clipboard} placeholder + an argument named 'target'
       with default 'es'                                                20 pts
  C6 — Maps quicklink: google.com/maps URL + Pittsburgh origin
       + a destination placeholder ({Query} or {argument})              15 pts
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_file_exists_new":     15,
    "C2_valid_json_4":        15,
    "C3_youtube":             15,
    "C4_github":              20,
    "C5_translate":           20,
    "C6_maps":                15,
}

# Placeholder presence (Query or any argument)
GENERIC_PLACEHOLDER_RE = re.compile(r"\{(?:Query|query|argument[^}]*)\}", re.IGNORECASE)
CLIPBOARD_PLACEHOLDER_RE = re.compile(r"\{clipboard[^}]*\}", re.IGNORECASE)


def _find_link_by_domain(links, domain):
    for ql in links:
        url = ql.get("link", "").lower()
        if domain.lower() in url:
            return ql
    return None


def _has_named_arg(url, name, default=None):
    """Check that the URL contains a placeholder of the form
       {argument name="<name>" ...} optionally with default="<default>".
    Accepts either order of attributes."""
    name_pat = re.compile(
        rf'\{{\s*argument[^}}]*name\s*=\s*["\']{re.escape(name)}["\'][^}}]*\}}',
        re.IGNORECASE,
    )
    m = name_pat.search(url)
    if not m:
        return False
    if default is None:
        return True
    inner = m.group(0)
    return re.search(
        rf'default\s*=\s*["\']{re.escape(default)}["\']',
        inner,
        re.IGNORECASE,
    ) is not None


def verify_quicklinks_dynamic(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_quicklinks_dynamic_result.json"
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

    file_is_new = result.get("export_file_is_new", False)
    valid_json  = result.get("valid_json", False)
    quicklinks  = result.get("quicklinks", [])
    count       = result.get("quicklink_count", 0)

    # C1
    if result.get("export_file_exists") and file_is_new:
        score += CRITERION_POINTS["C1_file_exists_new"]
        subscores["C1"] = CRITERION_POINTS["C1_file_exists_new"]
        feedback.append(f"C1 PASS: export exists ({result.get('export_file_size_bytes',0)} bytes)")
    else:
        subscores["C1"] = 0
        if not result.get("export_file_exists"):
            feedback.append("C1 FAIL: my_quicklinks.json not found on Desktop")
        else:
            feedback.append("C1 FAIL: export predates task start (stale)")

    # Gate: if file isn't new, content checks are skipped
    if not file_is_new:
        for key in ["C2", "C3", "C4", "C5", "C6"]:
            subscores[key] = 0
            feedback.append(f"{key} SKIP: export file not present or stale")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback),
            "subscores": subscores,
        }

    # C2
    if valid_json and count >= 4:
        score += CRITERION_POINTS["C2_valid_json_4"]
        subscores["C2"] = CRITERION_POINTS["C2_valid_json_4"]
        feedback.append(f"C2 PASS: valid JSON with {count} quicklinks")
    else:
        subscores["C2"] = 0
        if not valid_json:
            feedback.append(f"C2 FAIL: invalid JSON ({result.get('json_error', '')})")
        else:
            feedback.append(f"C2 FAIL: only {count} quicklinks (need >= 4)")

    # C3 — YouTube
    yt = _find_link_by_domain(quicklinks, "youtube.com")
    if yt and GENERIC_PLACEHOLDER_RE.search(yt["link"]):
        score += CRITERION_POINTS["C3_youtube"]
        subscores["C3"] = CRITERION_POINTS["C3_youtube"]
        feedback.append(f"C3 PASS: YouTube quicklink with placeholder ({yt['link'][:60]})")
    else:
        subscores["C3"] = 0
        feedback.append(f"C3 FAIL: no YouTube quicklink with placeholder")

    # C4 — GitHub
    gh = _find_link_by_domain(quicklinks, "github.com")
    if gh:
        url = gh["link"]
        # Accept either named 'keywords' OR a generic Query placeholder for keywords
        has_keywords = (_has_named_arg(url, "keywords")
                        or _has_named_arg(url, "q")
                        or "{Query}" in url or "{query}" in url)
        has_lang_default = _has_named_arg(url, "language", default="python") or \
                           _has_named_arg(url, "l", default="python")
        if has_keywords and has_lang_default:
            score += CRITERION_POINTS["C4_github"]
            subscores["C4"] = CRITERION_POINTS["C4_github"]
            feedback.append(f"C4 PASS: GitHub quicklink with keywords + language=python default")
        else:
            subscores["C4"] = 0
            feedback.append(
                f"C4 FAIL: GitHub quicklink missing required placeholders "
                f"(keywords={has_keywords}, lang_default_python={has_lang_default})"
            )
    else:
        subscores["C4"] = 0
        feedback.append("C4 FAIL: no GitHub quicklink found")

    # C5 — Translate
    tr = _find_link_by_domain(quicklinks, "translate.google.com")
    if tr:
        url = tr["link"]
        has_clip = bool(CLIPBOARD_PLACEHOLDER_RE.search(url))
        has_target_es = _has_named_arg(url, "target", default="es") or \
                        _has_named_arg(url, "tl", default="es")
        if has_clip and has_target_es:
            score += CRITERION_POINTS["C5_translate"]
            subscores["C5"] = CRITERION_POINTS["C5_translate"]
            feedback.append("C5 PASS: Translate quicklink with clipboard + target=es default")
        else:
            subscores["C5"] = 0
            feedback.append(
                f"C5 FAIL: Translate quicklink missing required placeholders "
                f"(clipboard={has_clip}, target_es={has_target_es})"
            )
    else:
        subscores["C5"] = 0
        feedback.append("C5 FAIL: no Translate quicklink found")

    # C6 — Maps
    mp = _find_link_by_domain(quicklinks, "google.com/maps")
    if mp:
        url = mp["link"]
        has_pittsburgh = "pittsburgh" in url.lower()
        has_placeholder = bool(GENERIC_PLACEHOLDER_RE.search(url))
        if has_pittsburgh and has_placeholder:
            score += CRITERION_POINTS["C6_maps"]
            subscores["C6"] = CRITERION_POINTS["C6_maps"]
            feedback.append("C6 PASS: Maps quicklink with Pittsburgh origin + destination placeholder")
        else:
            subscores["C6"] = 0
            feedback.append(
                f"C6 FAIL: Maps quicklink missing required pieces "
                f"(pittsburgh={has_pittsburgh}, placeholder={has_placeholder})"
            )
    else:
        subscores["C6"] = 0
        feedback.append("C6 FAIL: no Maps quicklink found")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "quicklink_count": count,
    }
