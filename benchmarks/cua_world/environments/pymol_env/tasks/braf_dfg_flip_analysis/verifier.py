#!/usr/bin/env python3
"""
Verifier for the BRAF DFG-Flip Structural Analysis task.

Scoring Breakdown (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB.
  25 pts - Report contains a distance value within the physically plausible range for
           the Phe595 C-alpha displacement: range 1.5–10.0 Å accepted.
  25 pts - Report explicitly identifies the states of both PDBs.
           10 pts for mentioning both 3OG7 and 1UWH.
           +15 pts for mapping 3OG7 as active/in and 1UWH as inactive/out.
  25 pts - Report explains the Type II inhibition mechanism by mentioning the 
           'allosteric' or 'hydrophobic' pocket.

Pass threshold: 75/100

Anti-gaming logic:
  - figure_is_new verifies the PNG file was written after setup script completion.
  - CA distance bounds checks protect against fabricated or wildly mismeasured coordinates.
  - Required textual keywords test the underlying biological knowledge.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_braf_dfg_flip_analysis(traj, env_info, task_info):
    """Verify the BRAF DFG-flip structural analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/braf_dfg_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run."
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

    # --- Criterion 1: Publication Figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created ({fig_size // 1024} KB).")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created.")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder.")
    else:
        parts.append("Figure not found at ~/PyMOL_Data/images/braf_dfg_flip.png.")

    # --- Criterion 2: CA-CA Distance Measurement (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    dist_min = metadata.get('phe595_distance_min', 1.5)
    dist_max = metadata.get('phe595_distance_max', 10.0)

    # Extract all floating point numbers
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 25
        parts.append(f"Phe595 displacement distance reported: {valid_distances[0]:.2f} \u00c5.")
    elif all_decimals:
        parts.append(f"Numeric values found but none in valid {dist_min}-{dist_max} \u00c5 range.")
    else:
        parts.append("No numeric distance value found in report.")

    # --- Criterion 3: State Identification (25 pts) ---
    content_lower = report_content.lower()
    has_3og7 = '3og7' in content_lower
    has_1uwh = '1uwh' in content_lower

    if has_3og7 and has_1uwh:
        score += 10
        parts.append("Both PDBs (3OG7, 1UWH) identified in report.")
        
        # Look for associations mapping 3OG7 -> active/in and 1UWH -> inactive/out
        # Allowing up to 60 characters distance to accommodate phrasing
        has_active_3og7 = bool(re.search(r'3og7.{0,60}(active|in\b)|(active|in\b).{0,60}3og7', content_lower, re.DOTALL))
        has_inactive_1uwh = bool(re.search(r'1uwh.{0,60}(inactive|out\b)|(inactive|out\b).{0,60}1uwh', content_lower, re.DOTALL))
        
        if has_active_3og7 and has_inactive_1uwh:
            score += 15
            parts.append("Correctly mapped 3OG7 as active/DFG-in and 1UWH as inactive/DFG-out.")
        elif has_active_3og7 or has_inactive_1uwh:
            score += 5
            parts.append("Partially mapped conformational states to specific PDBs.")
        else:
            parts.append("States not explicitly and correctly mapped to PDBs.")
    else:
        parts.append("Failed to explicitly mention both 3OG7 and 1UWH.")

    # --- Criterion 4: Structural Mechanism (25 pts) ---
    if re.search(r'allosteric|hydrophobic', content_lower):
        score += 25
        parts.append("Structural mechanism (allosteric/hydrophobic pocket) correctly explained.")
    elif report_exists and len(content_lower) > 20:
        score += 5
        parts.append("Report written but missing 'allosteric' or 'hydrophobic' keyword for mechanism.")
    else:
        parts.append("No structural mechanism explanation found.")

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }