"""
Verifier for storage_segregation_audit task.

Scoring breakdown (100 pts total):
- GATE: Output file must exist, else score=0 immediately
- Criterion 1 (15 pts): File is substantive (≥ 1000 chars / ≥ 20 lines)
- Criterion 2 (30 pts): Correctly identifies Sulfuric Acid + Sodium Cyanide as dangerous pair
  (must mention BOTH chemicals; HCN/hydrogen cyanide generation is the key hazard)
- Criterion 3 (25 pts): Correctly identifies Hydrogen Peroxide + Acetone as dangerous pair
  (explosive peroxides; both must be mentioned)
- Criterion 4 (15 pts): Report includes storage/segregation recommendations
- Criterion 5 (15 pts): Identifies ≥ 2 additional dangerous pairs beyond the two above
  (e.g., Chlorine+Ammonia, Nitric Acid+organics, Sodium Azide instability)

Pass threshold: 60 pts
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_storage_segregation_audit(traj, env_info, task_info):
    """
    Verify that the agent completed a comprehensive storage segregation audit
    for the 15-chemical facility inventory using CAMEO Chemicals.
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
            suffix="_storage_segregation_audit_result.json", delete=False
        ) as tmp:
            result_path = tmp.name

        copy_from_env("/tmp/storage_segregation_audit_result.json", result_path)

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
            "feedback": "Output file /home/ga/Documents/storage_audit_report.txt was not created.",
            "criteria": {"file_gate": False},
        }

    feedback.append("Output file exists.")
    criteria["file_gate"] = True

    # ── Criterion 1: Substantive report (15 pts) ─────────────────────────────
    file_size = result.get("file_size_bytes", 0)
    file_lines = result.get("file_lines", 0)
    if file_size >= 1000 and file_lines >= 20:
        score += 15
        criteria["substantive_report"] = True
        feedback.append(f"Report is substantive ({file_size} bytes, {file_lines} lines). +15 pts")
    else:
        criteria["substantive_report"] = False
        feedback.append(
            f"Report is too short ({file_size} bytes, {file_lines} lines). Expected ≥1000 chars and ≥20 lines. +0 pts"
        )

    # ── Criterion 2: Sulfuric Acid + Sodium Cyanide pair (30 pts) ────────────
    mentions_sulfuric = result.get("mentions_sulfuric", 0)
    mentions_cyanide = result.get("mentions_cyanide", 0)
    if mentions_sulfuric and mentions_cyanide:
        score += 30
        criteria["sulfuric_cyanide_pair"] = True
        feedback.append(
            "Correctly identified Sulfuric Acid + Sodium Cyanide as a dangerous pair "
            "(HCN gas generation). +30 pts"
        )
    else:
        criteria["sulfuric_cyanide_pair"] = False
        missing = []
        if not mentions_sulfuric:
            missing.append("Sulfuric Acid")
        if not mentions_cyanide:
            missing.append("Sodium Cyanide")
        feedback.append(
            f"Did not identify Sulfuric Acid + Sodium Cyanide dangerous pair. "
            f"Missing: {', '.join(missing)}. +0 pts"
        )

    # ── Criterion 3: Hydrogen Peroxide + Acetone pair (25 pts) ───────────────
    mentions_peroxide = result.get("mentions_peroxide", 0)
    mentions_acetone = result.get("mentions_acetone", 0)
    if mentions_peroxide and mentions_acetone:
        score += 25
        criteria["peroxide_acetone_pair"] = True
        feedback.append(
            "Correctly identified Hydrogen Peroxide + Acetone as a dangerous pair "
            "(explosive peroxides). +25 pts"
        )
    else:
        criteria["peroxide_acetone_pair"] = False
        missing = []
        if not mentions_peroxide:
            missing.append("Hydrogen Peroxide")
        if not mentions_acetone:
            missing.append("Acetone")
        feedback.append(
            f"Did not identify Hydrogen Peroxide + Acetone dangerous pair. "
            f"Missing: {', '.join(missing)}. +0 pts"
        )

    # ── Criterion 4: Storage/segregation recommendations (15 pts) ────────────
    has_recommendations = result.get("has_recommendations", 0)
    if has_recommendations:
        score += 15
        criteria["has_recommendations"] = True
        feedback.append("Report includes storage/segregation recommendations. +15 pts")
    else:
        criteria["has_recommendations"] = False
        feedback.append(
            "Report does not include storage/segregation recommendations "
            "(expected keywords: recommend/segregate/separate/incompatible). +0 pts"
        )

    # ── Criterion 5: ≥ 2 additional dangerous pairs (15 pts) ─────────────────
    additional_pairs = result.get("additional_pairs_found", 0)
    if additional_pairs >= 2:
        score += 15
        criteria["additional_pairs"] = True
        feedback.append(
            f"Identified {additional_pairs} additional dangerous pairs "
            "(e.g., Cl2+NH3, Nitric Acid+organics, Sodium Azide). +15 pts"
        )
    elif additional_pairs == 1:
        score += 7
        criteria["additional_pairs"] = "partial"
        feedback.append(
            f"Identified only {additional_pairs} additional dangerous pair. Expected ≥2. +7 pts"
        )
    else:
        criteria["additional_pairs"] = False
        feedback.append(
            "Did not identify additional dangerous pairs beyond the two main ones. +0 pts"
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
