import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "ibrutinib_contraindication"
RESULT_PATH = "/sdcard/{}_result.json".format(TASK_NAME)


def verify_ibrutinib_comedication_contraindication_screen(traj, env_info, task_info):
    """
    Verifier for ibrutinib_comedication_contraindication_screen.

    The agent must screen three co-medications (acenocoumarol, fluconazole, ketoconazole)
    against ibrutinib, identify ketoconazole as the most severely rated ('Do Not
    Coadminister'), and navigate to the Interaction Details page for ibrutinib + ketoconazole.

    Scoring (100 pts total, pass >= 70):
      - Gate 1: Ibrutinib visible on screen                  (0 if absent)
      - Gate 2: Ketoconazole visible (not wrong co-med)      (0 or 5 if absent)
      - Criterion 1: Correct drug pair on screen             +20 pts
      - Criterion 2: 'Do Not Coadminister' severity text     +25 pts
      - Criterion 3: Interaction Details page reached        +35 pts
      - Criterion 4: CYP3A4 mechanism text present           +20 pts
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

    ibrutinib_found = bool(result.get("ibrutinib_found", False))
    ketoconazole_found = bool(result.get("ketoconazole_found", False))
    fluconazole_found = bool(result.get("fluconazole_found", False))
    acenocoumarol_found = bool(result.get("acenocoumarol_found", False))
    severity_red = bool(result.get("severity_do_not_coadminister", False))
    details_page = bool(result.get("on_interaction_details_page", False))
    mechanism_found = bool(result.get("mechanism_cyp3a4_found", False))

    # ── GATE 1: Ibrutinib must be on screen ───────────────────────────────
    if not ibrutinib_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: 'Ibrutinib' not visible on screen. "
                "Agent navigated to the wrong cancer drug or did not complete the task."
            ),
        }

    # ── GATE 2: Ketoconazole must be on screen (not a wrong co-medication) ─
    if not ketoconazole_found:
        wrong_comedication = fluconazole_found or acenocoumarol_found
        if wrong_comedication:
            return {
                "passed": False,
                "score": 5,
                "feedback": (
                    "GATE FAIL: Agent is showing a different co-medication interaction "
                    "(Fluconazole or Acenocoumarol) rather than Ketoconazole. "
                    "Ketoconazole has the 'Do Not Coadminister' rating with ibrutinib "
                    "due to strong CYP3A4 inhibition. The agent must identify the most "
                    "severe interaction and navigate to its Interaction Details screen."
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
    feedback.append("PASS: Ibrutinib + Ketoconazole drug pair visible on screen (+20)")

    # ── Criterion 2: 'Do Not Coadminister' severity indicator ─────────────
    if severity_red:
        score += 25
        feedback.append(
            "PASS: 'Do Not Coadminister' severity indicator present — "
            "confirms the agent identified the highest-severity interaction (+25)"
        )
    else:
        feedback.append(
            "FAIL: 'Do Not Coadminister' text not found. "
            "Agent may not have reached the results or details screen for ibrutinib + ketoconazole."
        )

    # ── Criterion 3: Interaction Details page reached ──────────────────────
    if details_page:
        score += 35
        feedback.append(
            "PASS: Interaction Details page reached — full clinical information "
            "including quality of evidence and mechanism is visible (+35)"
        )
    else:
        feedback.append(
            "FAIL: Not on Interaction Details page. "
            "Agent may have stopped at the Results screen. "
            "Tap the arrow/chevron icon on the result card to open Interaction Details."
        )

    # ── Criterion 4: CYP3A4 pharmacokinetic mechanism text ────────────────
    if mechanism_found:
        score += 20
        feedback.append(
            "PASS: CYP3A4 pharmacokinetic mechanism text visible — "
            "clinical interaction details are fully displayed (+20)"
        )
    else:
        feedback.append(
            "INFO: CYP3A4 mechanism text not detected. "
            "The Interaction Details page may not be fully scrolled or rendered."
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
