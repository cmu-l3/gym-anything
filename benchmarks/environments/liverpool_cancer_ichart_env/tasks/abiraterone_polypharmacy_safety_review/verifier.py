import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "abiraterone_polypharmacy"
RESULT_PATH = "/sdcard/{}_result.json".format(TASK_NAME)


def verify_abiraterone_polypharmacy_safety_review(traj, env_info, task_info):
    """
    Verifier for abiraterone_polypharmacy_safety_review.

    The agent must screen three co-medications (ketoconazole, warfarin, acenocoumarol)
    against abiraterone, identify ketoconazole as the most severely rated combination
    (both inhibit the CYP17A1 / androgen synthesis pathway), and navigate to the
    Interaction Details page for abiraterone + ketoconazole.

    Scoring (100 pts total, pass >= 70):
      - Gate 1: Abiraterone visible on screen               (0 if absent)
      - Gate 2: Ketoconazole visible (not wrong co-med)     (0 or 5 if absent)
      - Criterion 1: Correct drug pair visible              +20 pts
      - Criterion 2: 'Do Not Coadminister' severity text    +25 pts
      - Criterion 3: Interaction Details page reached       +35 pts
      - Criterion 4: Mechanism text (CYP17/androgen/CYP3A4) +20 pts
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

    abiraterone_found = bool(result.get("abiraterone_found", False))
    ketoconazole_found = bool(result.get("ketoconazole_found", False))
    warfarin_found = bool(result.get("warfarin_found", False))
    acenocoumarol_found = bool(result.get("acenocoumarol_found", False))
    severity_red = bool(result.get("severity_do_not_coadminister", False))
    details_page = bool(result.get("on_interaction_details_page", False))
    mechanism_found = bool(result.get("mechanism_text_found", False))

    # ── GATE 1: Abiraterone must be on screen ─────────────────────────────
    if not abiraterone_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: 'Abiraterone' not visible on screen. "
                "Agent navigated to the wrong cancer drug or did not complete the task."
            ),
        }

    # ── GATE 2: Ketoconazole must be on screen (identity gate) ────────────
    if not ketoconazole_found:
        wrong_comedication = warfarin_found or acenocoumarol_found
        if wrong_comedication:
            return {
                "passed": False,
                "score": 5,
                "feedback": (
                    "GATE FAIL: Agent is showing the Warfarin or Acenocoumarol interaction "
                    "rather than Ketoconazole. Abiraterone + Ketoconazole is the most "
                    "severely rated combination because both drugs inhibit CYP17A1, "
                    "the key enzyme in androgen synthesis. The agent must navigate to "
                    "the Interaction Details screen for abiraterone + ketoconazole."
                ),
            }
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: Ketoconazole not visible on screen. "
                "Agent has not navigated to the correct drug pair interaction screen."
            ),
        }

    score = 0
    feedback = []

    # ── Criterion 1: Correct drug pair visible ────────────────────────────
    score += 20
    feedback.append(
        "PASS: Abiraterone + Ketoconazole drug pair visible on screen (+20)"
    )

    # ── Criterion 2: 'Do Not Coadminister' severity ───────────────────────
    if severity_red:
        score += 25
        feedback.append(
            "PASS: 'Do Not Coadminister' severity indicator visible — "
            "confirms the most severe interaction was correctly identified (+25)"
        )
    else:
        feedback.append(
            "FAIL: 'Do Not Coadminister' text not found. "
            "Agent may not be on the results or details screen for abiraterone + ketoconazole."
        )

    # ── Criterion 3: Interaction Details page reached ──────────────────────
    if details_page:
        score += 35
        feedback.append(
            "PASS: Interaction Details page reached — full clinical information visible (+35)"
        )
    else:
        feedback.append(
            "FAIL: Not on Interaction Details page. "
            "Agent may have stopped at the Results screen. "
            "Tap the arrow/chevron icon on the result card to open Interaction Details."
        )

    # ── Criterion 4: Mechanism/pathway text ───────────────────────────────
    if mechanism_found:
        score += 20
        feedback.append(
            "PASS: Pharmacological mechanism text visible "
            "(CYP17A1/androgen pathway or CYP3A4 reference) (+20)"
        )
    else:
        feedback.append(
            "INFO: Mechanism keyword text not detected on screen. "
            "Interaction Details page may not be fully rendered or scrolled."
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "drug_pair_visible": 20,
            "severity_indicator": 25 if severity_red else 0,
            "interaction_details_page": 35 if details_page else 0,
            "mechanism_text": 20 if mechanism_found else 0,
        },
    }
