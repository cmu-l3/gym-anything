"""
Verifier for chemical_incident_root_cause task.

Scenario: A reactor exploded after maintenance workers cleaned a toluene-residue
vessel with 68% Nitric Acid. The reaction is a classic aromatic nitration:
    Toluene + HNO3 (conc.) → Nitrotoluene → Dinitrotoluene → TNT (explosive)
under heat. Two alternative cleaning agents (H2O2, KMnO4) were also considered —
both are also incompatible with organic residues.

Scoring breakdown (100 pts total):
- GATE: Output file must exist, else score=0 immediately
- Criterion 1 (35 pts): Correctly identifies root cause (Toluene + HNO3 nitration)
- Criterion 2 (25 pts): Evaluates both alternative cleaning agents as also incompatible
  (both H2O2 and KMnO4 are oxidizers that react with toluene residues)
- Criterion 3 (20 pts): Recommends correct preventive measures
  (purge reactor before oxidizing cleaners; use inert solvents first)
- Criterion 4 (20 pts): Report is substantive and structured (≥800 chars, mentions root cause)

Pass threshold: 60 pts
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_chemical_incident_root_cause(traj, env_info, task_info):
    """
    Verify that the agent correctly identified the nitration reaction as the root
    cause of the reactor explosion, evaluated alternative cleaning agents, and
    provided appropriate preventive measures.
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
            suffix="_chemical_incident_root_cause_result.json", delete=False
        ) as tmp:
            result_path = tmp.name

        copy_from_env("/tmp/chemical_incident_root_cause_result.json", result_path)

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
            "feedback": "Output file /home/ga/Documents/incident_root_cause_report.txt was not created.",
            "criteria": {"file_gate": False},
        }

    feedback.append("Output file exists.")
    criteria["file_gate"] = True

    # ── Criterion 1: Root cause — Toluene + HNO3 nitration (35 pts) ──────────
    root_cause_correct = result.get("root_cause_correct", 0)
    identifies_nitration = result.get("identifies_nitration", 0)
    mentions_toluene = result.get("mentions_toluene", 0)
    mentions_nitric_acid = result.get("mentions_nitric_acid", 0)

    if root_cause_correct:
        score += 35
        criteria["root_cause"] = True
        feedback.append(
            "Correctly identified root cause: Toluene + Nitric Acid nitration reaction "
            "(producing explosive nitrotoluene compounds). +35 pts"
        )
    elif mentions_toluene and mentions_nitric_acid:
        # Partial: identified both chemicals but not the nitration mechanism
        score += 15
        criteria["root_cause"] = "partial"
        feedback.append(
            "Identified Toluene and Nitric Acid as the reacting chemicals but did not "
            "explain the nitration mechanism. +15 pts"
        )
    elif identifies_nitration:
        # Mentions nitration without explicitly naming the chemicals
        score += 10
        criteria["root_cause"] = "partial"
        feedback.append(
            "Mentioned nitration reaction but incomplete chemical identification. +10 pts"
        )
    else:
        criteria["root_cause"] = False
        feedback.append(
            "Did not identify the Toluene + Nitric Acid nitration as the root cause. +0 pts"
        )

    # ── Criterion 2: Alternative agent evaluation (25 pts) ───────────────────
    h2o2_eval = result.get("evaluates_h2o2", 0)
    h2o2_incompatible = result.get("h2o2_verdict_incompatible", 0)
    kmno4_eval = result.get("evaluates_kmno4", 0)
    kmno4_incompatible = result.get("kmno4_verdict_incompatible", 0)

    alt_agents_evaluated = (h2o2_eval and h2o2_incompatible) + (kmno4_eval and kmno4_incompatible)

    if alt_agents_evaluated == 2:
        score += 25
        criteria["alternative_agents"] = True
        feedback.append(
            "Correctly evaluated both H2O2 and KMnO4 as also incompatible with toluene residues. +25 pts"
        )
    elif alt_agents_evaluated == 1:
        score += 12
        criteria["alternative_agents"] = "partial"
        missing = []
        if not (h2o2_eval and h2o2_incompatible):
            missing.append("H2O2")
        if not (kmno4_eval and kmno4_incompatible):
            missing.append("KMnO4")
        feedback.append(
            f"Evaluated 1/2 alternative agents as incompatible. Missing: {', '.join(missing)}. +12 pts"
        )
    elif h2o2_eval or kmno4_eval:
        score += 5
        criteria["alternative_agents"] = "minimal"
        feedback.append(
            "Mentioned alternative agents but did not fully evaluate their incompatibility. +5 pts"
        )
    else:
        criteria["alternative_agents"] = False
        feedback.append(
            "Did not evaluate the alternative cleaning agents (H2O2, KMnO4). +0 pts"
        )

    # ── Criterion 3: Preventive measures (20 pts) ─────────────────────────────
    mentions_prevention = result.get("mentions_prevention", 0)
    if mentions_prevention:
        score += 20
        criteria["preventive_measures"] = True
        feedback.append(
            "Provides preventive measures (e.g., purge reactor before oxidizing cleaners). +20 pts"
        )
    else:
        criteria["preventive_measures"] = False
        feedback.append("Does not provide preventive measures. +0 pts")

    # ── Criterion 4: Report structure and substance (20 pts) ─────────────────
    file_size = result.get("file_size_bytes", 0)
    mentions_root_cause_structure = result.get("mentions_root_cause", 0)

    if file_size >= 800 and mentions_root_cause_structure:
        score += 20
        criteria["report_quality"] = True
        feedback.append(f"Report is substantive ({file_size} bytes) with proper structure. +20 pts")
    elif file_size >= 400 or mentions_root_cause_structure:
        score += 10
        criteria["report_quality"] = "partial"
        feedback.append(f"Report partially meets quality requirements ({file_size} bytes). +10 pts")
    else:
        criteria["report_quality"] = False
        feedback.append(f"Report is too short or unstructured ({file_size} bytes). +0 pts")

    # ── Final result ──────────────────────────────────────────────────────────
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback),
        "criteria": criteria,
    }
