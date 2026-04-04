import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "venetoclax_induction"
RESULT_PATH = "/sdcard/{}_result.json".format(TASK_NAME)


def verify_venetoclax_cyp3a4_induction_risk_assessment(traj, env_info, task_info):
    """
    Verifier for venetoclax_cyp3a4_induction_risk_assessment.

    The agent must screen warfarin, fluconazole, and carbamazepine against venetoclax.
    The task requires navigating to the Interaction Details page for venetoclax +
    carbamazepine, which represents the CYP3A4/CYP2C8 enzyme-induction mechanism
    (reduces venetoclax AUC, risking sub-therapeutic drug levels and treatment failure).

    Note: The task description explicitly specifies carbamazepine as the 'enzyme-induction
    mechanism of concern', so the agent must correctly identify and navigate to that
    specific interaction regardless of the assigned severity rating in the app.

    Scoring (100 pts total, pass >= 70):
      - Gate 1: Venetoclax visible on screen                 (0 if absent)
      - Gate 2: Carbamazepine visible (not wrong co-med)     (0 or 5 if absent)
      - Criterion 1: Correct drug pair visible               +20 pts
      - Criterion 2: Any severity text present               +20 pts
      - Criterion 3: Interaction Details page reached        +35 pts
      - Criterion 4: Induction/CYP/AUC mechanism text        +25 pts
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

    venetoclax_found = bool(result.get("venetoclax_found", False))
    carbamazepine_found = bool(result.get("carbamazepine_found", False))
    warfarin_found = bool(result.get("warfarin_found", False))
    fluconazole_found = bool(result.get("fluconazole_found", False))
    severity_red = bool(result.get("severity_do_not_coadminister", False))
    details_page = bool(result.get("on_interaction_details_page", False))
    mechanism_found = bool(result.get("mechanism_text_found", False))

    # ── GATE 1: Venetoclax must be on screen ──────────────────────────────
    if not venetoclax_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: 'Venetoclax' not visible on screen. "
                "Agent navigated to the wrong cancer drug or did not complete the task."
            ),
        }

    # ── GATE 2: Carbamazepine must be on screen (identity gate) ───────────
    if not carbamazepine_found:
        wrong_comedication = warfarin_found or fluconazole_found
        if wrong_comedication:
            return {
                "passed": False,
                "score": 5,
                "feedback": (
                    "GATE FAIL: Agent navigated to the Warfarin or Fluconazole interaction "
                    "rather than Carbamazepine. The task asks for the enzyme-induction "
                    "mechanism of concern: carbamazepine induces CYP3A4/CYP2C8, "
                    "reducing venetoclax plasma levels and risking treatment failure. "
                    "Navigate to the Interaction Details screen for venetoclax + carbamazepine."
                ),
            }
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: Carbamazepine not visible on screen. "
                "Agent has not navigated to the venetoclax + carbamazepine interaction."
            ),
        }

    score = 0
    feedback = []

    # ── Criterion 1: Correct drug pair visible ────────────────────────────
    score += 20
    feedback.append(
        "PASS: Venetoclax + Carbamazepine drug pair visible on screen (+20)"
    )

    # ── Criterion 2: Severity text visible ────────────────────────────────
    # Note: any severity text indicates the agent is on a results/details screen
    if severity_red:
        score += 20
        feedback.append(
            "PASS: 'Do Not Coadminister' severity indicator present (+20)"
        )
    else:
        # Partial credit: agent may be on details page without severity banner visible
        # (the severity banner may be scrolled off screen on details page)
        feedback.append(
            "INFO: 'Do Not Coadminister' text not detected — may be scrolled off screen "
            "on Interaction Details page, or interaction severity is not red."
        )

    # ── Criterion 3: Interaction Details page reached ──────────────────────
    if details_page:
        score += 35
        feedback.append(
            "PASS: Interaction Details page reached — full clinical mechanism "
            "and pharmacokinetic information visible (+35)"
        )
    else:
        feedback.append(
            "FAIL: Not on Interaction Details page. "
            "Agent may have stopped at the Results screen. "
            "Tap the arrow/chevron icon on the result card to open Interaction Details."
        )

    # ── Criterion 4: Induction/CYP/AUC mechanism text ─────────────────────
    if mechanism_found:
        score += 25
        feedback.append(
            "PASS: CYP enzyme induction / AUC / exposure mechanism text visible — "
            "confirms the pharmacokinetic interaction details are displayed (+25)"
        )
    else:
        feedback.append(
            "FAIL: CYP induction / AUC mechanism text not detected. "
            "Interaction Details page may not be fully rendered, or the agent may not "
            "have scrolled to the mechanism description section."
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "drug_pair_visible": 20,
            "severity_indicator": 20 if severity_red else 0,
            "interaction_details_page": 35 if details_page else 0,
            "mechanism_text": 25 if mechanism_found else 0,
        },
    }
