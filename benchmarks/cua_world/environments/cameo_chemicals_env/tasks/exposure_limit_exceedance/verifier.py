"""
Verifier for exposure_limit_exceedance task.

Scenario: 6 work zones with air monitoring readings for 6 different chemicals.
4 zones exceed OSHA PELs (Xylene, MEK, n-Hexane, Methanol); 2 are within limits
(Toluene, Tetrachloroethylene/PERC). One worker has peripheral neuropathy — caused
by n-Hexane (metabolized to neurotoxic 2,5-hexanedione).

Scoring breakdown (100 pts total):
- GATE: Output file must exist, else score=0 immediately
- Criterion 1 (30 pts): Correctly identifies exceedance zones (4 × 7.5 pts)
- Criterion 2 (30 pts): Identifies n-Hexane as the neuropathy-causing chemical
- Criterion 3 (20 pts): References OSHA PEL and/or IDLH values
- Criterion 4 (20 pts): Provides corrective action recommendations

Pass threshold: 60 pts
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_exposure_limit_exceedance(traj, env_info, task_info):
    """
    Verify the agent correctly identified PEL exceedances, connected n-Hexane
    to peripheral neuropathy, and produced a compliant exceedance report.
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
            suffix="_exposure_limit_exceedance_result.json", delete=False
        ) as tmp:
            result_path = tmp.name

        copy_from_env("/tmp/exposure_limit_exceedance_result.json", result_path)

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
            "feedback": "Output file /home/ga/Documents/exposure_exceedance_report.txt was not created.",
            "criteria": {"file_gate": False},
        }

    feedback.append("Output file exists.")
    criteria["file_gate"] = True

    # ── Criterion 1: Exceedance zone identification (30 pts) ─────────────────
    exceedance_checks = {
        "Xylene Zone 2": result.get("identifies_xylene_exceedance", 0),
        "MEK Zone 3": result.get("identifies_mek_exceedance", 0),
        "n-Hexane Zone 4": result.get("identifies_hexane_exceedance", 0),
        "Methanol Zone 5": result.get("identifies_methanol_exceedance", 0),
    }
    exceedances_found = result.get("exceedances_found", 0)
    exceedance_score = exceedances_found * 7  # 7 pts each, max 28
    if exceedances_found == 4:
        exceedance_score = 30  # Bonus for getting all 4
    score += exceedance_score
    criteria["exceedance_identification"] = exceedances_found

    if exceedances_found == 4:
        feedback.append(f"All 4 PEL exceedances correctly identified. +30 pts")
    else:
        missing = [k for k, v in exceedance_checks.items() if not v]
        feedback.append(
            f"Identified {exceedances_found}/4 PEL exceedances (+{exceedance_score} pts). "
            f"Missed: {', '.join(missing)}"
        )

    # ── Criterion 2: n-Hexane → neuropathy connection (30 pts) ───────────────
    hexane_neuropathy = result.get("identifies_hexane_neuropathy", 0)
    if hexane_neuropathy:
        score += 30
        criteria["hexane_neuropathy"] = True
        feedback.append(
            "Correctly identified n-Hexane as the cause of worker's peripheral neuropathy. +30 pts"
        )
    else:
        # Partial credit if n-hexane is identified as exceeding PEL but neuropathy not linked
        hexane_exceedance = result.get("identifies_hexane_exceedance", 0)
        if hexane_exceedance:
            score += 10
            criteria["hexane_neuropathy"] = "partial"
            feedback.append(
                "Identified n-Hexane exceedance but did not connect to worker's neuropathy symptoms. +10 pts"
            )
        else:
            criteria["hexane_neuropathy"] = False
            feedback.append(
                "Did not identify n-Hexane as the cause of peripheral neuropathy. +0 pts"
            )

    # ── Criterion 3: References PEL and/or IDLH values (20 pts) ─────────────
    mentions_pel = result.get("mentions_pel", 0)
    mentions_idlh = result.get("mentions_idlh", 0)
    if mentions_pel and mentions_idlh:
        score += 20
        criteria["pel_idlh_reference"] = True
        feedback.append("References both OSHA PEL and IDLH values. +20 pts")
    elif mentions_pel:
        score += 12
        criteria["pel_idlh_reference"] = "partial"
        feedback.append("References OSHA PEL values but not IDLH. +12 pts")
    elif mentions_idlh:
        score += 8
        criteria["pel_idlh_reference"] = "partial"
        feedback.append("References IDLH but not PEL explicitly. +8 pts")
    else:
        criteria["pel_idlh_reference"] = False
        feedback.append("Does not reference OSHA PEL or IDLH values. +0 pts")

    # ── Criterion 4: Corrective actions (20 pts) ─────────────────────────────
    mentions_corrective = result.get("mentions_corrective", 0)
    if mentions_corrective:
        score += 20
        criteria["corrective_actions"] = True
        feedback.append("Provides corrective action recommendations. +20 pts")
    else:
        criteria["corrective_actions"] = False
        feedback.append("Does not provide corrective action recommendations. +0 pts")

    # ── Final result ──────────────────────────────────────────────────────────
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback),
        "criteria": criteria,
    }
