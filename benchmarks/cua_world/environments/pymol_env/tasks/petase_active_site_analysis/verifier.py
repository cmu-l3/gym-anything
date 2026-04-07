#!/usr/bin/env python3
"""
Verifier for the IsPETase Active Site Analysis task (PDB:6EQE).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB.
  25 pts - Report lists the catalytic triad residues: Ser160, Asp206, His237.
  25 pts - Report identifies the wobbling Trp185 residue.
  25 pts - Report contains a distance value in the physically plausible range for a hydrogen bond 
           between Ser160(OG) and His237(NE2): range 2.2 - 4.2 Å.

Pass threshold: 75/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files.
  - Ser-His distance range: prevents arbitrary string values.
  - Excess numbers check: catches agents that simply dump all sequence data without analysis.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_petase_active_site_analysis(traj, env_info, task_info):
    """Verify the IsPETase active site analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/petase_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found \u2014 export script may not have run"
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
        parts.append(f"Active site figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Active site figure not found at /home/ga/PyMOL_Data/images/petase_active_site.png")

    # Parse report content
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    # Extract all numbers from the report to gracefully handle S160, Ser160, or 160.
    all_numbers = set(int(n) for n in re.findall(r'(\d+)', report_content) if 1 <= int(n) <= 500)
    
    # --- Criterion 2: Catalytic Triad Identified (25 pts) ---
    triad = {160, 206, 237}
    if triad.issubset(all_numbers):
        score += 25
        parts.append("Catalytic triad residues (160, 206, 237) identified")
    elif len(triad.intersection(all_numbers)) > 0:
        found = triad.intersection(all_numbers)
        score += 10
        parts.append(f"Only partial triad found: {found}")
    else:
        parts.append("Catalytic triad residues not found in report")

    # --- Criterion 3: Trp185 Identified (25 pts) ---
    if 185 in all_numbers:
        score += 25
        parts.append("Wobbling Trp185 identified")
    else:
        parts.append("Trp185 not found in report")

    # --- Criterion 4: Ser160-His237 Distance (25 pts) ---
    dist_min = metadata.get('ser_his_distance_min', 2.2)
    dist_max = metadata.get('ser_his_distance_max', 4.2)

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
            f"Decimal values found ({all_decimals[:3]}) but none in expected H-bond distance range "
            f"({dist_min}\u2013{dist_max} \u00c5) \u2014 check measurement"
        )
    else:
        parts.append("No valid distance value found in report")

    # Final evaluation
    passed = score >= 75
    
    # Check for excessive number dumping (Anti-gaming check)
    if len(all_numbers) > 30 and score >= 75:
        passed = False
        parts.append("Anti-gaming: Too many residue numbers found (dumped output detected). Results must be specific.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }