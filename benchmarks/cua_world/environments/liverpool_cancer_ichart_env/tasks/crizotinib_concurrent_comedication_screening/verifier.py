import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "crizotinib_concurrent"
RESULT_PATH = "/sdcard/{}_result.json".format(TASK_NAME)


def verify_crizotinib_concurrent_comedication_screening(traj, env_info, task_info):
    """
    Verifier for crizotinib_concurrent_comedication_screening.

    The agent must perform a SINGLE combined interaction query: select crizotinib as
    the cancer drug, then select BOTH acenocoumarol AND fluconazole simultaneously
    as co-medications. The Results screen must show interaction results for both
    co-medication pairings simultaneously (multi-select feature).

    This is verified by checking that all three drug names (crizotinib, acenocoumarol,
    fluconazole) appear on the same screen at the same time — which can only happen
    on a multi-result Results screen using the simultaneous co-medication selection.

    A wrong-target scenario (e.g., agent does two separate single-pair queries and
    ends on the last one) would only show two drug names at most, not all three.

    Scoring (100 pts total, pass >= 75):
      - Gate 1: Crizotinib visible on screen                (0 if absent)
      - Gate 2: At least one co-medication visible          (0 if neither found)
      - Criterion 1: Crizotinib visible                     +20 pts
      - Criterion 2: Acenocoumarol visible                  +20 pts
      - Criterion 3: Fluconazole visible                    +20 pts
      - Criterion 4: Both co-medications visible (multi-select confirmed) +20 pts bonus
      - Criterion 5: At least one severity result visible   +20 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "ERROR: copy_from_env not available in env_info. "
                "Check framework runner key names for Android AVD environment."
            ),
        }

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
    except Exception as e:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No result file found — agent likely did not complete the task "
                "or export_result.sh failed: {}".format(e)
            ),
        }

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to parse result JSON: {}".format(e),
        }
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

    crizotinib_found = bool(result.get("crizotinib_found", False))
    acenocoumarol_found = bool(result.get("acenocoumarol_found", False))
    fluconazole_found = bool(result.get("fluconazole_found", False))
    any_severity = bool(result.get("any_severity_found", False))
    severity_count = int(result.get("severity_result_count", 0))

    # ── GATE 1: Crizotinib must be on screen ──────────────────────────────
    if not crizotinib_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: 'Crizotinib' not visible on screen. "
                "Agent navigated to the wrong cancer drug or did not complete the task."
            ),
        }

    # ── GATE 2: At least one co-medication must be visible ─────────────────
    if not acenocoumarol_found and not fluconazole_found:
        return {
            "passed": False,
            "score": 5,
            "feedback": (
                "GATE FAIL: Neither Acenocoumarol nor Fluconazole visible on screen. "
                "Agent has Crizotinib selected but has not submitted a co-medication query. "
                "Select both Acenocoumarol and Fluconazole simultaneously and view results."
            ),
        }

    score = 0
    feedback = []

    # ── Criterion 1: Crizotinib visible ───────────────────────────────────
    score += 20
    feedback.append("PASS: Crizotinib visible on screen (+20)")

    # ── Criterion 2: Acenocoumarol visible ────────────────────────────────
    if acenocoumarol_found:
        score += 20
        feedback.append("PASS: Acenocoumarol visible on screen — first co-medication present (+20)")
    else:
        feedback.append(
            "FAIL: Acenocoumarol not visible. "
            "Agent may not have selected acenocoumarol as one of the co-medications."
        )

    # ── Criterion 3: Fluconazole visible ──────────────────────────────────
    if fluconazole_found:
        score += 20
        feedback.append("PASS: Fluconazole visible on screen — second co-medication present (+20)")
    else:
        feedback.append(
            "FAIL: Fluconazole not visible. "
            "Agent may not have selected fluconazole as one of the co-medications, "
            "or performed two separate single-pair queries instead of a combined query."
        )

    # ── Criterion 4: Both co-medications on screen simultaneously ─────────
    # This is the key signal confirming the multi-select feature was used
    if acenocoumarol_found and fluconazole_found:
        score += 20
        feedback.append(
            "PASS: Both co-medications visible on screen simultaneously — "
            "confirms the multi-select co-medication query feature was used correctly (+20)"
        )
    else:
        feedback.append(
            "FAIL: Not both co-medications visible simultaneously. "
            "Agent may have performed separate single-combination queries "
            "instead of using the multi-select feature."
        )

    # ── Criterion 5: Severity results visible ─────────────────────────────
    if any_severity:
        score += 20
        if severity_count >= 2:
            feedback.append(
                "PASS: Multiple interaction result severity banners visible — "
                "both drug pair results are shown on the Results screen (+20)"
            )
        else:
            feedback.append(
                "PASS: At least one interaction result severity banner visible (+20)"
            )
    else:
        feedback.append(
            "FAIL: No severity result text detected on screen. "
            "Agent may not have tapped Next to reach the Results screen, "
            "or is on a screen that does not show interaction results."
        )

    passed = score >= 75
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "crizotinib_visible": 20,
            "acenocoumarol_visible": 20 if acenocoumarol_found else 0,
            "fluconazole_visible": 20 if fluconazole_found else 0,
            "both_comedications_simultaneously": 20 if (acenocoumarol_found and fluconazole_found) else 0,
            "severity_results_visible": 20 if any_severity else 0,
        },
    }
