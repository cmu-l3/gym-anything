#!/usr/bin/env python3
"""
Verifier for the Streptavidin-Biotin Hydrogen Bond Network task (PDB:1STP).

Scoring (100 points total):
  25 pts - Figure exists, is new (post-task-start), and is non-trivial (>30KB).
  15 pts - Report exists and contains >= 5 lines.
  20 pts - Ligand & Count check: Report mentions "BTN" or "Biotin", and gives
           a plausible total count of H-bonding residues (integer between 5 and 15).
  20 pts - Canonical Residues (Partial): Report explicitly identifies at least 3 of
           the 8 canonical H-bonding residues: 23, 27, 43, 45, 49, 88, 90, 128.
  20 pts - Canonical Residues (Full): Report explicitly identifies at least 6 of
           the 8 canonical H-bonding residues.

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate ensures figure must be created during the agent's run.
  - Strict requirement on specific canonical residue numbers (not just a generic dump)
    ensures the agent performed the actual distance/polar contact calculation.
    Without getting the specific residues, max score is 25+15+20 = 60 < 70 (Fail).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_streptavidin_hbond_network(traj, env_info, task_info):
    """Verify the Streptavidin-Biotin H-bond network analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/1stp_hbond_result.json')
    expected_residues = set(metadata.get('expected_residues', [23, 27, 43, 45, 49, 88, 90, 128]))

    # Copy result JSON from container
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
        parts.append(f"H-bond figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("H-bond figure not found at /home/ga/PyMOL_Data/images/streptavidin_hbond.png")

    # --- Criterion 2: Report Exists & Line Count (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    # Normalize newlines
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    report_lines = [l.strip() for l in report_content.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 5)

    if report_exists and len(report_lines) >= min_lines:
        score += 15
        parts.append(f"Report exists with {len(report_lines)} lines")
    elif report_exists:
        score += 5
        parts.append(f"Report exists but is too short ({len(report_lines)} lines)")
    else:
        parts.append("H-bond report not found at /home/ga/PyMOL_Data/biotin_hbond_report.txt")

    # --- Criterion 3: Ligand & Count Check (20 pts) ---
    count_min = metadata.get('count_min', 5)
    count_max = metadata.get('count_max', 15)
    
    # Check for presence of ligand name
    has_ligand_name = bool(re.search(r'(?i)\b(BTN|Biotin)\b', report_content))
    
    # Extract all numbers from the text to find a plausible count
    all_numbers = re.findall(r'\b\d+\b', report_content)
    has_plausible_count = any(count_min <= int(n) <= count_max for n in all_numbers)

    if has_ligand_name and has_plausible_count:
        score += 20
        parts.append("Ligand (BTN/Biotin) and plausible H-bond count identified")
    elif has_ligand_name:
        score += 10
        parts.append("Ligand identified, but plausible total residue count missing")
    elif has_plausible_count:
        score += 10
        parts.append("Plausible count found, but ligand (BTN/Biotin) not explicitly mentioned")
    else:
        parts.append("Ligand identity and expected count missing from report")

    # --- Criterion 4 & 5: Canonical Residues (20 + 20 pts) ---
    # Extract all residue-like numbers from the report (1-300 range)
    found_residue_nums = set(int(n) for n in all_numbers if 1 <= int(n) <= 300)
    
    # Find intersection with canonical residues
    identified_canonical = found_residue_nums.intersection(expected_residues)
    num_identified = len(identified_canonical)

    if num_identified >= 6:
        score += 40  # Full points for both criteria
        parts.append(f"Excellent mapping! {num_identified}/8 canonical residues identified (e.g. {sorted(list(identified_canonical))})")
    elif num_identified >= 3:
        score += 20  # Partial points
        parts.append(f"Partial mapping: {num_identified}/8 canonical residues identified")
    else:
        parts.append(f"Failed to identify canonical H-bonding residues (found {num_identified}/8)")

    # Overall determination
    passed = score >= 70 and fig_exists and num_identified >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts),
        "details": {
            "figure_ok": fig_exists and fig_size >= min_fig_size,
            "canonical_found": list(identified_canonical)
        }
    }