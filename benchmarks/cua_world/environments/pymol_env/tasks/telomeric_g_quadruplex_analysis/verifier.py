#!/usr/bin/env python3
"""
Verifier for the Telomeric G-Quadruplex DNA Coordination Analysis task (PDB:1KF1).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  20 pts - Text report exists with >= 10 lines of content
  25 pts - Report correctly identifies >= 6 specific coordinating guanine residues 
           from the 1KF1 structure (tetrads).
  30 pts - Report contains >= 8 physically accurate K-O6 distance measurements (2.5 - 3.5 A).

Pass threshold: 75/100 (Implicitly requires Distance Accuracy criterion to be met)

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - Distance range constraint prevents hallucinated data scoring points.
  - Required tetrad DG residues limit generic structural descriptions.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known coordinating guanine residues in the 1KF1 G-quadruplex
KNOWN_TETRAD_RESIDUES = {2, 3, 4, 8, 9, 10, 14, 15, 16, 20, 21, 22}


def verify_telomeric_g_quadruplex_analysis(traj, env_info, task_info):
    """Verify the Telomeric G-Quadruplex Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/g_quadruplex_result.json')

    # Copy the JSON result from the container
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
        parts.append(f"G-quadruplex figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/g_quadruplex.png")

    # --- Criterion 2: Report existence and length (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    
    report_lines = [line.strip() for line in report_content.splitlines() if line.strip()]
    min_lines = metadata.get('min_report_lines', 10)

    if report_exists and len(report_lines) >= min_lines:
        score += 20
        parts.append(f"Report contains {len(report_lines)} lines")
    elif report_exists and len(report_lines) >= 3:
        score += 10
        parts.append(f"Report exists but is short ({len(report_lines)} lines)")
    elif report_exists:
        parts.append(f"Report file exists but is nearly empty ({len(report_lines)} lines)")
    else:
        parts.append("Coordination report not found at /home/ga/PyMOL_Data/k_coordination_report.txt")

    # --- Criterion 3: Residue Accuracy (25 pts) ---
    # Extract numbers between 1 and 30 (1KF1 is a 22-mer, giving buffer)
    all_numbers_in_report = set(int(n) for n in re.findall(r'\b(\d{1,2})\b', report_content) if 1 <= int(n) <= 30)
    found_tetrad_residues = all_numbers_in_report.intersection(KNOWN_TETRAD_RESIDUES)
    
    min_residues = metadata.get('min_coordinating_residues', 6)

    if len(found_tetrad_residues) >= min_residues:
        score += 25
        parts.append(f"Identified {len(found_tetrad_residues)} coordinating guanine residues")
    elif len(found_tetrad_residues) >= 3:
        score += 10
        parts.append(f"Partially identified coordinating guanine residues ({len(found_tetrad_residues)} found)")
    else:
        parts.append(f"Failed to identify sufficient coordinating guanine residues (found {len(found_tetrad_residues)})")

    # --- Criterion 4: Distance Accuracy (30 pts) ---
    dist_min = metadata.get('k_o6_distance_min', 2.50)
    dist_max = metadata.get('k_o6_distance_max', 3.50)
    min_dists = metadata.get('min_distance_measurements', 8)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if len(valid_distances) >= min_dists:
        score += 30
        parts.append(f"Reported {len(valid_distances)} valid K-O6 distances (range {dist_min}-{dist_max} \u00c5)")
    elif len(valid_distances) >= 4:
        score += 15
        parts.append(f"Reported only {len(valid_distances)} valid K-O6 distances (needed {min_dists})")
    elif len(valid_distances) > 0:
        score += 5
        parts.append(f"Reported only {len(valid_distances)} valid K-O6 distances (needed {min_dists})")
    else:
        if len(all_decimals) > 0:
            parts.append(f"Report contains decimals but none in valid K-O6 coordination range ({dist_min}-{dist_max} \u00c5)")
        else:
            parts.append("No distance measurements found in report")

    # Assess overall pass/fail
    # Must hit threshold AND successfully extract some distance data
    passed = (score >= 75) and (len(valid_distances) >= min_dists)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }