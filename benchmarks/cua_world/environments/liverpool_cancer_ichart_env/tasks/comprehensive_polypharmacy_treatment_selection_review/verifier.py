import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "treatment_selection"
RESULT_PATH = "/sdcard/{}_result.json".format(TASK_NAME)

# All cancer drugs and co-medications involved in this task
CANCER_DRUGS = {"ibrutinib", "venetoclax", "crizotinib"}
ORIGINAL_COMEDS = {"ketoconazole", "verapamil", "warfarin"}
ALTERNATIVE_COMEDS = {"fluconazole", "bisoprolol", "apixaban"}
ALL_COMEDS = ORIGINAL_COMEDS | ALTERNATIVE_COMEDS


def verify_comprehensive_polypharmacy_treatment_selection_review(traj, env_info, task_info):
    """
    Verifier for comprehensive_polypharmacy_treatment_selection_review.

    The agent must systematically check three cancer drugs (Ibrutinib, Venetoclax,
    Crizotinib) against three co-medications (Ketoconazole, Verapamil, Warfarin),
    review Interaction Details for Red/Orange results, compare safety profiles,
    check safer alternatives for the selected drug, and end on the correct
    Interaction Details page.

    This is primarily a screen-state verifier. Full process verification is
    handled externally via the VLM checklist verifier.

    Scoring (100 pts total, pass >= 70):
      - Gate 1: At least one cancer drug visible on screen     (0 if absent)
      - Gate 2: Interaction Details page reached               (0 if absent, partial credit)
      - Criterion 1: On Interaction Details page               +35 pts
      - Criterion 2: Cancer drug name visible                  +15 pts
      - Criterion 3: Co-medication or alternative visible      +15 pts
      - Criterion 4: Mechanism text present                    +25 pts
      - Criterion 5: Severity indicator visible                +10 pts
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

    # Extract flags from result JSON
    ibrutinib_found = bool(result.get("ibrutinib_found", False))
    venetoclax_found = bool(result.get("venetoclax_found", False))
    crizotinib_found = bool(result.get("crizotinib_found", False))

    ketoconazole_found = bool(result.get("ketoconazole_found", False))
    fluconazole_found = bool(result.get("fluconazole_found", False))
    verapamil_found = bool(result.get("verapamil_found", False))
    bisoprolol_found = bool(result.get("bisoprolol_found", False))
    warfarin_found = bool(result.get("warfarin_found", False))
    apixaban_found = bool(result.get("apixaban_found", False))

    severity_red = bool(result.get("severity_do_not_coadminister", False))
    severity_amber = bool(result.get("severity_potential_interaction", False))
    severity_green = bool(result.get("severity_no_interaction", False))
    details_page = bool(result.get("on_interaction_details_page", False))
    mechanism_found = bool(result.get("mechanism_text_found", False))

    has_any_cancer_drug = ibrutinib_found or venetoclax_found or crizotinib_found
    has_any_comed = (
        ketoconazole_found or fluconazole_found
        or verapamil_found or bisoprolol_found
        or warfarin_found or apixaban_found
    )
    has_any_alternative = fluconazole_found or bisoprolol_found or apixaban_found

    # ── GATE 1: At least one cancer drug must be on screen ────────────────
    if not has_any_cancer_drug:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: No cancer drug (Ibrutinib, Venetoclax, or Crizotinib) "
                "visible on screen. Agent did not navigate to any drug interaction "
                "screen or did not complete the task."
            ),
        }

    score = 0
    feedback = []

    # ── Criterion 1: Interaction Details page reached ─────────────────────
    if details_page:
        score += 35
        feedback.append(
            "PASS: Interaction Details page reached — full clinical mechanism "
            "and pharmacokinetic information visible (+35)"
        )
    else:
        feedback.append(
            "FAIL: Not on Interaction Details page. "
            "Agent may have stopped at the Results screen or another page. "
            "The task requires navigating to and remaining on an Interaction Details page."
        )

    # ── Criterion 2: Cancer drug name visible ─────────────────────────────
    visible_drugs = []
    if ibrutinib_found:
        visible_drugs.append("Ibrutinib")
    if venetoclax_found:
        visible_drugs.append("Venetoclax")
    if crizotinib_found:
        visible_drugs.append("Crizotinib")

    score += 15
    feedback.append(
        "PASS: Cancer drug visible on screen: {} (+15)".format(
            ", ".join(visible_drugs)
        )
    )

    # ── Criterion 3: Co-medication or alternative visible ─────────────────
    if has_any_comed:
        visible_comeds = []
        for name, found in [
            ("Ketoconazole", ketoconazole_found),
            ("Fluconazole", fluconazole_found),
            ("Verapamil", verapamil_found),
            ("Bisoprolol", bisoprolol_found),
            ("Warfarin", warfarin_found),
            ("Apixaban", apixaban_found),
        ]:
            if found:
                visible_comeds.append(name)
        score += 15
        feedback.append(
            "PASS: Co-medication visible on screen: {} (+15)".format(
                ", ".join(visible_comeds)
            )
        )
    else:
        feedback.append(
            "FAIL: No co-medication or alternative co-medication visible on screen."
        )

    # ── Criterion 4: Pharmacological mechanism text ───────────────────────
    if mechanism_found:
        score += 25
        feedback.append(
            "PASS: Pharmacological mechanism text visible (CYP/AUC/induction/"
            "inhibition keywords detected) — confirms Interaction Details "
            "content is displayed (+25)"
        )
    else:
        feedback.append(
            "FAIL: No pharmacological mechanism text detected. "
            "The Interaction Details page may not be fully rendered or the agent "
            "is not on a details page."
        )

    # ── Criterion 5: Severity indicator visible ───────────────────────────
    if severity_red or severity_amber:
        score += 10
        severity_type = "Red" if severity_red else "Orange/Amber"
        feedback.append(
            "PASS: Severity indicator '{}' visible on screen (+10)".format(
                severity_type
            )
        )
    elif severity_green:
        score += 5
        feedback.append(
            "PARTIAL: 'No Interaction Expected' (Green) visible — agent may be "
            "on a low-severity interaction details page (+5)"
        )
    else:
        feedback.append(
            "INFO: No severity indicator text detected — may be scrolled off screen."
        )

    passed = score >= 70 and details_page
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "interaction_details_page": 35 if details_page else 0,
            "cancer_drug_visible": 15 if has_any_cancer_drug else 0,
            "comedication_visible": 15 if has_any_comed else 0,
            "mechanism_text": 25 if mechanism_found else 0,
            "severity_indicator": (
                10 if (severity_red or severity_amber)
                else (5 if severity_green else 0)
            ),
        },
    }
