#!/usr/bin/env python3
"""
Verifier for the Adenylate Kinase B-factor Flexibility Analysis task.

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (created after task start),
           and is non-trivial (>30KB)
  15 pts - Flexibility report exists and contains ≥5 lines of content (top-5 residues required)
  20 pts - Report contains at least 5 distinct residue numbers (integers in range 1–214),
           indicating a real per-residue analysis rather than a generic description
  40 pts - Report contains ≥2 residue numbers from the LID domain range (118–167),
           demonstrating that the most flexible domain was correctly identified.
           Specifically tests that the agent identified LID domain residues as the most
           flexible, which is the key scientific insight of this task.

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: figure must be modified AFTER task start
  - LID domain residue check (40 pts): requires actual residue numbers 118-167 in report,
    NOT just the word "LID" — prevents writing "LID domain is flexible" without real data.
    Without LID residues: max 25+15+20=60 < 70 — cannot pass by analyzing only CORE domain.
  - Residue number check: agent cannot pass with prose description alone
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# LID domain residue range in E. coli adenylate kinase (4AKE)
LID_DOMAIN_RANGE = set(range(118, 168))  # residues 118-167


def verify_adenylate_kinase_bfactor_flexibility(traj, env_info, task_info):
    """Verify the adenylate kinase B-factor flexibility analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/adk_bfactor_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"B-factor figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("B-factor figure not found at /home/ga/PyMOL_Data/images/adk_bfactor.png")

    # --- Criterion 2: Report with ≥5 lines (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    report_lines = [l.strip() for l in report_content.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 5)

    if report_exists and len(report_lines) >= min_lines:
        score += 15
        parts.append(f"Flexibility report has {len(report_lines)} lines")
    elif report_exists and len(report_lines) >= 2:
        score += 7
        parts.append(
            f"Report only has {len(report_lines)} lines "
            f"(need \u2265{min_lines} for top-5 residue listing)"
        )
    elif report_exists:
        parts.append(f"Report file exists but has too few entries ({len(report_lines)} lines)")
    else:
        parts.append("Flexibility report not found at /home/ga/PyMOL_Data/adk_flexibility_report.txt")

    # --- Criterion 3: ≥5 distinct residue numbers in report (20 pts) ---
    # Residues in 4AKE chain A: 1–214
    all_numbers = re.findall(r'\b(\d{1,3})\b', report_content)
    residue_candidates = set(int(n) for n in all_numbers if 1 <= int(n) <= 214)

    if len(residue_candidates) >= 5:
        score += 20
        sample = sorted(residue_candidates)[:5]
        parts.append(f"Report contains \u22655 residue numbers (e.g., {sample})")
    elif len(residue_candidates) >= 2:
        score += 8
        parts.append(
            f"Report contains only {len(residue_candidates)} residue numbers "
            "(need \u22655 for top-5 flexible residues)"
        )
    else:
        parts.append(
            "Report lacks specific residue numbers — "
            "must list top flexible residues by residue number and B-factor"
        )

    # --- Criterion 4: ≥2 residue numbers from LID domain (118–167) in report (40 pts) ---
    # Require actual LID residue numbers, not just the word "LID"
    # This ensures the agent genuinely identified LID domain as the most flexible
    lid_in_report = LID_DOMAIN_RANGE & residue_candidates

    if len(lid_in_report) >= 2:
        score += 40
        sample_lid = sorted(lid_in_report)[:3]
        parts.append(f"LID domain flexibility correctly identified — {len(lid_in_report)} LID residues reported (e.g., {sample_lid})")
    elif len(lid_in_report) == 1:
        score += 15
        parts.append(
            f"Only 1 LID domain residue found ({sorted(lid_in_report)[0]}); "
            "need \u22652 residues from range 118\u2013167 to confirm LID domain identification"
        )
    else:
        parts.append(
            "No LID domain residues (118\u2013167) found in report — "
            "the LID domain is the most flexible region of apo adenylate kinase; "
            "B-factor analysis must include residues in this range"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }
