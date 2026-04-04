import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "olaparib_antiepileptic"
RESULT_PATH = "/sdcard/{}_result.json".format(TASK_NAME)


def verify_olaparib_antiepileptic_interaction_consultation(traj, env_info, task_info):
    """
    Verifier for olaparib_antiepileptic_interaction_consultation.

    The agent must screen carbamazepine, warfarin, and acenocoumarol against olaparib,
    then navigate to the Interaction Details page for olaparib + carbamazepine
    (the antiepileptic being evaluated). Carbamazepine is a strong CYP3A4 inducer
    that substantially reduces olaparib AUC, which is clinically significant for
    PARP inhibitor maintenance therapy in ovarian cancer.

    The task description explicitly names carbamazepine as the drug whose interaction
    should be viewed, so the identity gate checks for carbamazepine on screen.

    Scoring (100 pts total, pass >= 70):
      - Gate 1: Olaparib visible on screen                  (0 if absent)
      - Gate 2: Carbamazepine visible (not wrong co-med)    (0 or 5 if absent)
      - Criterion 1: Correct drug pair visible              +20 pts
      - Criterion 2: Any severity text visible              +20 pts
      - Criterion 3: Interaction Details page reached       +35 pts
      - Criterion 4: CYP induction/AUC/exposure text        +25 pts
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

    olaparib_found = bool(result.get("olaparib_found", False))
    carbamazepine_found = bool(result.get("carbamazepine_found", False))
    warfarin_found = bool(result.get("warfarin_found", False))
    acenocoumarol_found = bool(result.get("acenocoumarol_found", False))
    severity_red = bool(result.get("severity_do_not_coadminister", False))
    details_page = bool(result.get("on_interaction_details_page", False))
    mechanism_found = bool(result.get("mechanism_text_found", False))

    # ── GATE 1: Olaparib must be on screen ────────────────────────────────
    if not olaparib_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: 'Olaparib' not visible on screen. "
                "Agent navigated to the wrong cancer drug or did not complete the task."
            ),
        }

    # ── GATE 2: Carbamazepine must be on screen (identity gate) ───────────
    if not carbamazepine_found:
        wrong_comedication = warfarin_found or acenocoumarol_found
        if wrong_comedication:
            return {
                "passed": False,
                "score": 5,
                "feedback": (
                    "GATE FAIL: Agent is showing the Warfarin or Acenocoumarol "
                    "interaction rather than Carbamazepine. The task explicitly asks "
                    "for the Interaction Details screen for olaparib + carbamazepine "
                    "(the antiepileptic drug being considered for initiation). "
                    "Navigate to the correct drug pair."
                ),
            }
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: Carbamazepine not visible on screen. "
                "Agent has not navigated to the olaparib + carbamazepine interaction screen."
            ),
        }

    score = 0
    feedback = []

    # ── Criterion 1: Correct drug pair visible ────────────────────────────
    score += 20
    feedback.append(
        "PASS: Olaparib + Carbamazepine drug pair visible on screen (+20)"
    )

    # ── Criterion 2: Severity text visible ────────────────────────────────
    if severity_red:
        score += 20
        feedback.append(
            "PASS: 'Do Not Coadminister' severity indicator visible (+20)"
        )
    else:
        feedback.append(
            "INFO: 'Do Not Coadminister' text not detected — may be scrolled off screen "
            "on Interaction Details page, or the severity rating in the app differs "
            "from the expected 'Do Not Coadminister'."
        )

    # ── Criterion 3: Interaction Details page reached ──────────────────────
    if details_page:
        score += 35
        feedback.append(
            "PASS: Interaction Details page reached — full pharmacokinetic and "
            "clinical details for olaparib + carbamazepine are visible (+35)"
        )
    else:
        feedback.append(
            "FAIL: Not on Interaction Details page. "
            "Agent may have stopped at the Results screen. "
            "Tap the arrow/chevron icon on the result card to open Interaction Details."
        )

    # ── Criterion 4: CYP induction / AUC / mechanism text ─────────────────
    if mechanism_found:
        score += 25
        feedback.append(
            "PASS: CYP enzyme induction / AUC / plasma exposure mechanism text visible — "
            "confirms the pharmacokinetic interaction details are fully displayed (+25)"
        )
    else:
        feedback.append(
            "FAIL: CYP induction / AUC mechanism text not detected. "
            "Interaction Details page may not be fully rendered or scrolled to "
            "the mechanism description section."
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
