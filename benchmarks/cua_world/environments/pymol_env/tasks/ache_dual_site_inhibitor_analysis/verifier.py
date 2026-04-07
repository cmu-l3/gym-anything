#!/usr/bin/env python3
"""
Verifier for the AChE Dual-Site Inhibitor Analysis task (PDB: 4EY7).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report exists and contains >100 characters of text
  30 pts - Report contains a distance value in the physically plausible range for the
           gorge span (Trp286 CA to Trp86 CA): 13.5–16.0 Å.
  30 pts - Report lists ≥5 valid binding residues for donepezil (E20) in 4EY7.

Pass threshold: 70/100 AND Gorge distance accuracy criteria must be met.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_ache_dual_site_inhibitor_analysis(traj, env_info, task_info):
    """Verify the AChE gorge measurement and contact analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ache_task_result.json')

    # Load result from container
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
    gorge_distance_accurate = False

    # --- Criterion 1: Publication figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Gorge figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Gorge figure not found at /home/ga/PyMOL_Data/images/ache_gorge.png")

    # --- Criterion 2: Report Exists & Length (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content.strip()) >= 100:
        score += 15
        parts.append(f"Binding report exists with substantive content ({len(report_content)} chars)")
    elif report_exists:
        parts.append(f"Report file exists but is very short ({len(report_content)} chars)")
    else:
        parts.append("Binding report not found at /home/ga/PyMOL_Data/ache_binding_report.txt")

    # --- Criterion 3: Gorge Distance Accuracy (30 pts) ---
    dist_min = metadata.get('gorge_distance_min', 13.5)
    dist_max = metadata.get('gorge_distance_max', 16.0)

    # Extract decimals from the report
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 30
        gorge_distance_accurate = True
        parts.append(f"Gorge span distance reported: {valid_distances[0]:.2f} \u00c5 (valid range {dist_min}\u2013{dist_max} \u00c5)")
    elif all_decimals:
        parts.append(f"Decimal values found ({all_decimals[:3]}) but none in expected gorge span range ({dist_min}\u2013{dist_max} \u00c5) - verify atoms (Trp286 CA and Trp86 CA)")
    else:
        parts.append("No distance value found in the report.")

    # --- Criterion 4: Pocket Residue Accuracy (30 pts) ---
    known_residues = set(metadata.get('known_contact_residues', [72, 74, 76, 86, 120, 124, 203, 286, 295, 296, 297, 334, 337, 338, 341, 447]))
    min_required = metadata.get('min_binding_residues', 5)

    # Find all standalone integer numbers in the report (likely residue IDs)
    extracted_numbers = set(int(n) for n in re.findall(r'\b(\d{2,3})\b', report_content))
    matched_residues = extracted_numbers.intersection(known_residues)

    if len(matched_residues) >= min_required:
        score += 30
        parts.append(f"Identified \u2265{min_required} known contact residues (e.g., {sorted(list(matched_residues))[:min_required]})")
    elif len(matched_residues) > 0:
        score += int(30 * (len(matched_residues) / min_required))
        parts.append(f"Identified only {len(matched_residues)}/{min_required} known contact residues in the pocket")
    else:
        parts.append("Could not find required E20 binding residues in the report")

    # --- Final Evaluation ---
    passed = (score >= 70) and gorge_distance_accurate
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }