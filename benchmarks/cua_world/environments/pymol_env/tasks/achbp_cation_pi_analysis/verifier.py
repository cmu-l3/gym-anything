#!/usr/bin/env python3
"""
Verifier for the AChBP Cation-Pi Analysis task (PDB:1UW6).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  30 pts - Report correctly identifies the 5 key aromatic box residues (W53, Y89, W143, Y185, Y192)
           (6 points per residue identified).
  20 pts - Report correctly identifies the 2 vicinal disulfide residues (C187, C188)
           (10 points per residue identified).
  25 pts - Report contains a distance measurement between the pyrrolidine nitrogen and Trp143
           within the physically plausible range of 2.8 - 5.5 Å.

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files.
  - specific distance value: arbitrary decimals outside the 2.8-5.5 range earn 0 points.
  - precise residue numbers: without extracting the exact structure numbering via PyMOL,
    the agent cannot guess the full set of aromatic box and disulfide residues.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known AChBP Cation-Pi interaction residues
AROMATIC_BOX = {53, 89, 143, 185, 192}
DISULFIDES = {187, 188}

def verify_achbp_cation_pi_analysis(traj, env_info, task_info):
    """Verify the AChBP Cation-Pi binding analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/achbp_result.json')

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
        parts.append(f"Cation-pi figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Binding site figure not found at /home/ga/PyMOL_Data/images/achbp_cation_pi.png")

    # Extract all numbers from the report for analysis
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    
    if not report_exists:
        parts.append("Report file not found at /home/ga/PyMOL_Data/achbp_report.txt")
        return {"passed": False, "score": score, "feedback": " | ".join(parts)}

    # Regex to find residue numbers (2-3 digits)
    reported_residues = set(int(n) for n in re.findall(r'\b\d{2,3}\b', report_content))
    
    # --- Criterion 2: Aromatic Box Residues (30 pts) ---
    found_aromatics = AROMATIC_BOX.intersection(reported_residues)
    aromatic_score = len(found_aromatics) * 6
    score += aromatic_score
    parts.append(f"Identified {len(found_aromatics)}/5 aromatic box residues ({list(found_aromatics)})")
    
    # --- Criterion 3: Vicinal Disulfide Cysteines (20 pts) ---
    found_disulfides = DISULFIDES.intersection(reported_residues)
    disulfide_score = len(found_disulfides) * 10
    score += disulfide_score
    parts.append(f"Identified {len(found_disulfides)}/2 vicinal disulfide residues ({list(found_disulfides)})")

    # --- Criterion 4: Cation-Pi Distance Measurement (25 pts) ---
    dist_min = metadata.get('cation_pi_distance_min', 2.8)
    dist_max = metadata.get('cation_pi_distance_max', 5.5)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 25
        parts.append(
            f"Distance reported: {valid_distances[0]:.2f} \u00c5 "
            f"(valid range {dist_min}\u2013{dist_max} \u00c5)"
        )
    elif all_decimals:
        parts.append(
            f"Decimal values found ({all_decimals[:3]}) but none in expected distance range "
            f"({dist_min}\u2013{dist_max} \u00c5)"
        )
    else:
        parts.append("No distance value found in report")

    # Evaluate pass/fail
    passed = score >= 70
    feedback = " | ".join(parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }