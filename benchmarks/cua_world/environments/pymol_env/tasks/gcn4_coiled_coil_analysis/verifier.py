#!/usr/bin/env python3
"""
Verifier for the GCN4 Leucine Zipper Coiled-Coil Structural Analysis task.

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report mentions the PDB ID (2ZTA) to confirm correct structure was used
  15 pts - Report identifies both chains (A and B)
  25 pts - Report identifies >=3 of the key 'd'-position leucine residues by number (5, 12, 19, 26)
  20 pts - Report contains an inter-helix distance measurement in the plausible range (7.0-14.0 A)

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Key 'd'-position leucine residues for GCN4 (PDB: 2ZTA)
TARGET_LEUCINES = {5, 12, 19, 26}

def verify_gcn4_coiled_coil_analysis(traj, env_info, task_info):
    """Verify the GCN4 coiled-coil structural analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/gcn4_result.json')

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
        parts.append(f"Coiled-coil figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/gcn4_coiled_coil.png")

    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if not report_exists:
        parts.append("Structural analysis report not found.")
        return {
            "passed": False, 
            "score": score, 
            "feedback": "\n".join(parts)
        }

    # --- Criterion 2: Report mentions PDB ID (15 pts) ---
    if re.search(r'2ZTA', report_content, re.IGNORECASE):
        score += 15
        parts.append("PDB ID 2ZTA verified in report")
    else:
        parts.append("PDB ID 2ZTA missing from report")

    # --- Criterion 3: Report identifies both chains (15 pts) ---
    has_chain_a = bool(re.search(r'\bA\b', report_content))
    has_chain_b = bool(re.search(r'\bB\b', report_content))
    
    if has_chain_a and has_chain_b:
        score += 15
        parts.append("Chains A and B identified")
    elif has_chain_a or has_chain_b:
        parts.append("Only one chain identified in report")
    else:
        parts.append("Chains A and B not identified in report")

    # --- Criterion 4: Report lists >=3 'd'-position leucine numbers (25 pts) ---
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content))
    matched_leucines = all_numbers.intersection(TARGET_LEUCINES)

    if len(matched_leucines) >= 3:
        score += 25
        parts.append(f"Identified {len(matched_leucines)} core leucine residues: {sorted(list(matched_leucines))}")
    elif len(matched_leucines) > 0:
        score += 10
        parts.append(f"Only identified {len(matched_leucines)} core leucine residues: {sorted(list(matched_leucines))} (need >=3)")
    else:
        parts.append("Core 'd'-position leucine residues (5, 12, 19, 26) not found in report")

    # --- Criterion 5: Distance in expected range (20 pts) ---
    dist_min = metadata.get('min_distance_angstroms', 7.0)
    dist_max = metadata.get('max_distance_angstroms', 14.0)

    # Extract decimals (avoids confusing residue integers for distances)
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 20
        parts.append(f"Inter-helix distance reported: {valid_distances[0]:.2f} \u00c5 (valid range {dist_min}-{dist_max} \u00c5)")
    elif all_decimals:
        parts.append(f"Decimals found {all_decimals[:3]} but none in distance range {dist_min}-{dist_max} \u00c5")
    else:
        parts.append("No numeric decimal distance value found in report")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(parts)
    }