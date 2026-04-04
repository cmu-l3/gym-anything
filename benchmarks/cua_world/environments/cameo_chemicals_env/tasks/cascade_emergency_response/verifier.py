"""
Verifier for cascade_emergency_response task.

Scenario: 4 tank cars with ONLY UN numbers provided. TC-101 (UN 1050 = HCl) and
TC-102 (UN 1005 = NH3) are actively leaking and physically touching — classic
HCl + NH3 reaction producing ammonium chloride white cloud.

Scoring breakdown (100 pts total):
- GATE: Output file must exist, else score=0 immediately
- Criterion 1 (20 pts): Correctly identifies all 4 chemicals by UN number
  (4 × 5 pts; partial credit per chemical)
- Criterion 2 (25 pts): Correctly assesses TC-101 + TC-102 reaction
  (both chemicals identified + reaction/cloud described)
- Criterion 3 (20 pts): Includes isolation/protective action distances
- Criterion 4 (15 pts): Specifies required PPE for first responders
- Criterion 5 (20 pts): Provides shelter-in-place vs. evacuation recommendation

Pass threshold: 60 pts
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_cascade_emergency_response(traj, env_info, task_info):
    """
    Verify that agent correctly identified all 4 UN-number chemicals,
    assessed the TC-101/TC-102 reactive incident, and provided a complete
    emergency response assessment.
    """
    copy_from_env = env_info.get("copy_from_env")
    metadata = task_info.get("metadata", {})

    score = 0
    max_score = 100
    feedback = []
    criteria = {}

    # ── Copy result JSON from VM ──────────────────────────────────────────────
    result_path = None
    try:
        with tempfile.NamedTemporaryFile(
            suffix="_cascade_emergency_response_result.json", delete=False
        ) as tmp:
            result_path = tmp.name

        copy_from_env("/tmp/cascade_emergency_response_result.json", result_path)

        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
        result = {}
    finally:
        if result_path and os.path.exists(result_path):
            os.unlink(result_path)

    # ── GATE: Output file must exist ──────────────────────────────────────────
    file_exists = result.get("file_exists", 0)
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "max_score": max_score,
            "feedback": "Output file /home/ga/Documents/train_derailment_assessment.txt was not created.",
            "criteria": {"file_gate": False},
        }

    feedback.append("Output file exists.")
    criteria["file_gate"] = True

    # ── Criterion 1: Chemical identification by UN number (20 pts) ───────────
    chemical_ids = {
        "TC-101 (UN 1050 = HCl)": result.get("identifies_hcl_tc101", 0),
        "TC-102 (UN 1005 = NH3)": result.get("identifies_nh3_tc102", 0),
        "TC-103 (UN 2209 = Formaldehyde)": result.get("identifies_formaldehyde_tc103", 0),
        "TC-104 (UN 1791 = Hypochlorite)": result.get("identifies_hypochlorite_tc104", 0),
    }
    correct_ids = sum(1 for v in chemical_ids.values() if v)
    id_score = correct_ids * 5
    score += id_score
    criteria["chemical_identification"] = correct_ids
    if correct_ids == 4:
        feedback.append(f"All 4 chemicals correctly identified by UN number. +{id_score} pts")
    else:
        missing = [k for k, v in chemical_ids.items() if not v]
        feedback.append(
            f"Identified {correct_ids}/4 chemicals by UN number (+{id_score} pts). "
            f"Missing: {', '.join(missing)}"
        )

    # ── Criterion 2: TC-101 + TC-102 reaction assessment (25 pts) ────────────
    hcl_identified = result.get("identifies_hcl_tc101", 0)
    nh3_identified = result.get("identifies_nh3_tc102", 0)
    reaction_assessed = result.get("assesses_tc101_tc102_reaction", 0)

    if hcl_identified and nh3_identified and reaction_assessed:
        score += 25
        criteria["reaction_assessment"] = True
        feedback.append(
            "Correctly assessed TC-101 (HCl) + TC-102 (NH3) reaction "
            "(ammonium chloride aerosol formation). +25 pts"
        )
    elif (hcl_identified and nh3_identified) or reaction_assessed:
        score += 12
        criteria["reaction_assessment"] = "partial"
        feedback.append(
            "Partially assessed TC-101/TC-102 interaction. "
            "Both chemicals identified but reaction product or cloud description incomplete. +12 pts"
        )
    else:
        criteria["reaction_assessment"] = False
        feedback.append(
            "Did not assess TC-101 (HCl) + TC-102 (NH3) chemical reaction. +0 pts"
        )

    # ── Criterion 3: Isolation distances (20 pts) ─────────────────────────────
    mentions_isolation = result.get("mentions_isolation_distances", 0)
    if mentions_isolation:
        score += 20
        criteria["isolation_distances"] = True
        feedback.append("Includes isolation/protective action distances. +20 pts")
    else:
        criteria["isolation_distances"] = False
        feedback.append(
            "Does not mention isolation distances or protective action zones. +0 pts"
        )

    # ── Criterion 4: PPE requirements (15 pts) ───────────────────────────────
    mentions_ppe = result.get("mentions_ppe", 0)
    if mentions_ppe:
        score += 15
        criteria["ppe_requirements"] = True
        feedback.append("Specifies PPE requirements for first responders. +15 pts")
    else:
        criteria["ppe_requirements"] = False
        feedback.append("Does not specify PPE requirements. +0 pts")

    # ── Criterion 5: Shelter-in-place vs. evacuation recommendation (20 pts) ─
    shelter_or_evacuate = result.get("mentions_shelter_or_evacuate", 0)
    if shelter_or_evacuate:
        score += 20 - 5  # 15 pts base; full 20 if also substantive
        # Check if report is long enough to be a real recommendation
        file_size = result.get("file_size_bytes", 0)
        if file_size >= 800:
            score += 5
        criteria["shelter_evacuate_recommendation"] = True
        feedback.append(
            "Provides shelter-in-place vs. evacuation recommendation for facility. +15-20 pts"
        )
    else:
        criteria["shelter_evacuate_recommendation"] = False
        feedback.append(
            "Does not provide shelter-in-place vs. evacuation recommendation. +0 pts"
        )

    # ── Final result ──────────────────────────────────────────────────────────
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback),
        "criteria": criteria,
    }
