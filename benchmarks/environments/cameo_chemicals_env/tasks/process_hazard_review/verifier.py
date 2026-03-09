"""
Verifier for process_hazard_review task.

Scenario: Methyl acrylate synthesis using 5 chemicals. The agent must use the CAMEO
Reactivity tool to check all relevant pairs and identify dangerous combinations:
1. Acrylic Acid + Sodium Hydroxide: violent exothermic neutralization + polymerization risk
2. Methanol + Sulfuric Acid: exothermic, can produce dimethyl ether at elevated temperatures
Additionally, the process description mentions Building 12 lacks explosion-proof ventilation.

Scoring breakdown (100 pts total):
- GATE: Output file must exist, else score=0 immediately
- Criterion 1 (30 pts): Identifies Acrylic Acid + NaOH as a reactive hazard
- Criterion 2 (20 pts): Identifies Methanol + H2SO4 as a reactive hazard
- Criterion 3 (20 pts): Identifies the Building 12 ventilation safety gap
- Criterion 4 (15 pts): Covers all 5 process chemicals in the report
- Criterion 5 (15 pts): Includes safeguard/corrective action recommendations

Pass threshold: 60 pts
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_process_hazard_review(traj, env_info, task_info):
    """
    Verify that the agent performed a systematic process hazard analysis using
    CAMEO Chemicals Reactivity tool and identified critical reactive pairs and
    safety gaps in the methyl acrylate synthesis process.
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
            suffix="_process_hazard_review_result.json", delete=False
        ) as tmp:
            result_path = tmp.name

        copy_from_env("/tmp/process_hazard_review_result.json", result_path)

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
            "feedback": "Output file /home/ga/Documents/process_hazard_report.txt was not created.",
            "criteria": {"file_gate": False},
        }

    feedback.append("Output file exists.")
    criteria["file_gate"] = True

    # ── Criterion 1: Acrylic Acid + NaOH reactive pair (30 pts) ─────────────
    acrylic_naoh = result.get("acrylic_naoh_hazard_flagged", 0)
    if acrylic_naoh:
        score += 30
        criteria["acrylic_naoh_pair"] = True
        feedback.append(
            "Correctly identified Acrylic Acid + Sodium Hydroxide as a reactive hazard "
            "(violent exotherm / polymerization). +30 pts"
        )
    else:
        # Partial credit if both chemicals are at least mentioned together
        mentions_both = (
            result.get("mentions_acrylic_acid", 0) and result.get("mentions_naoh", 0)
        )
        if mentions_both:
            score += 10
            criteria["acrylic_naoh_pair"] = "partial"
            feedback.append(
                "Mentioned both Acrylic Acid and NaOH but did not flag their reaction as hazardous. +10 pts"
            )
        else:
            criteria["acrylic_naoh_pair"] = False
            feedback.append(
                "Did not identify Acrylic Acid + Sodium Hydroxide reactive hazard. +0 pts"
            )

    # ── Criterion 2: Methanol + H2SO4 reactive pair (20 pts) ────────────────
    methanol_h2so4 = result.get("methanol_h2so4_hazard_flagged", 0)
    if methanol_h2so4:
        score += 20
        criteria["methanol_h2so4_pair"] = True
        feedback.append(
            "Correctly identified Methanol + Sulfuric Acid as a reactive/exothermic hazard. +20 pts"
        )
    else:
        mentions_both = (
            result.get("mentions_methanol", 0) and result.get("mentions_h2so4", 0)
        )
        if mentions_both:
            score += 7
            criteria["methanol_h2so4_pair"] = "partial"
            feedback.append(
                "Mentioned both Methanol and Sulfuric Acid but did not flag their reaction. +7 pts"
            )
        else:
            criteria["methanol_h2so4_pair"] = False
            feedback.append(
                "Did not identify Methanol + Sulfuric Acid reactive hazard. +0 pts"
            )

    # ── Criterion 3: Building 12 ventilation safety gap (20 pts) ────────────
    ventilation_gap = result.get("identifies_ventilation_gap", 0)
    if ventilation_gap:
        score += 20
        criteria["ventilation_gap"] = True
        feedback.append(
            "Identified Building 12 explosion-proof ventilation gap. +20 pts"
        )
    else:
        criteria["ventilation_gap"] = False
        feedback.append(
            "Did not identify ventilation/explosion-proof safety gap in Building 12. +0 pts"
        )

    # ── Criterion 4: Covers all 5 process chemicals (15 pts) ─────────────────
    chemicals_mentioned = result.get("chemicals_mentioned", 0)
    if chemicals_mentioned == 5:
        score += 15
        criteria["all_chemicals_covered"] = True
        feedback.append("All 5 process chemicals addressed in the report. +15 pts")
    elif chemicals_mentioned >= 3:
        partial = int(15 * chemicals_mentioned / 5)
        score += partial
        criteria["all_chemicals_covered"] = "partial"
        feedback.append(
            f"Covered {chemicals_mentioned}/5 process chemicals. +{partial} pts"
        )
    else:
        criteria["all_chemicals_covered"] = False
        feedback.append(
            f"Only covered {chemicals_mentioned}/5 process chemicals. +0 pts"
        )

    # ── Criterion 5: Safeguard recommendations (15 pts) ──────────────────────
    includes_safeguards = result.get("includes_safeguards", 0)
    if includes_safeguards:
        score += 15
        criteria["safeguards"] = True
        feedback.append("Includes safeguard and corrective action recommendations. +15 pts")
    else:
        criteria["safeguards"] = False
        feedback.append("Does not include safeguard recommendations. +0 pts")

    # ── Final result ──────────────────────────────────────────────────────────
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback),
        "criteria": criteria,
    }
