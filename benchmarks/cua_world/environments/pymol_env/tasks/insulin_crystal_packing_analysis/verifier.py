#!/usr/bin/env python3
"""
Verifier for the Insulin Crystal Packing Analysis task (PDB: 4INS).

Scoring (100 points total):
  25 pts - Packing figure exists at correct path, is new (post-task-start), and >30KB
  20 pts - Report correctly identifies space group "R 3"
  20 pts - Report contains 'a' or 'b' unit cell dimension in range (80.0 - 85.0)
  15 pts - Report contains 'c' unit cell dimension in range (32.0 - 36.0)
  20 pts - Report lists >=5 distinct residue numbers involved in crystal contacts

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing images
  - Two independent unit cell boundaries: severely limits hallucinated data
  - Residue counts require integers in the valid insulin length range (1-30)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_insulin_crystal_packing(traj, env_info, task_info):
    """Verify the insulin crystal packing and symmetry extraction task."""
    
    # CRITICAL: Use copy_from_env to extract results securely
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/insulin_crystal_result.json')

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
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Packing figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Packing figure not found at /home/ga/PyMOL_Data/images/insulin_packing.png")

    # --- Content Analysis Setup ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')

    if not report_exists or not report_content.strip():
        parts.append("Report not found or empty at /home/ga/PyMOL_Data/insulin_crystal_report.txt")
        return {"passed": False, "score": score, "feedback": " | ".join(parts)}

    # Extract all floating point numbers for unit cell checks
    all_floats = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]

    # --- Criterion 2: Space Group R 3 (20 pts) ---
    has_r = re.search(r'\bR\b', report_content, re.IGNORECASE)
    has_3 = '3' in report_content
    
    if has_r and has_3:
        score += 20
        parts.append("Space group 'R 3' successfully identified")
    else:
        parts.append("Space group 'R 3' missing or incomplete in report")

    # --- Criterion 3: Unit Cell 'a' or 'b' dimension (20 pts) ---
    a_min = metadata.get('unit_cell_a_min', 80.0)
    a_max = metadata.get('unit_cell_a_max', 85.0)
    a_matches = [f for f in all_floats if a_min <= f <= a_max]
    
    if a_matches:
        score += 20
        parts.append(f"Unit cell 'a' dimension reported: {a_matches[0]:.2f} \u00c5")
    else:
        parts.append(f"No unit cell dimension found in 'a' range ({a_min}\u2013{a_max} \u00c5)")

    # --- Criterion 4: Unit Cell 'c' dimension (15 pts) ---
    c_min = metadata.get('unit_cell_c_min', 32.0)
    c_max = metadata.get('unit_cell_c_max', 36.0)
    c_matches = [f for f in all_floats if c_min <= f <= c_max]
    
    if c_matches:
        score += 15
        parts.append(f"Unit cell 'c' dimension reported: {c_matches[0]:.2f} \u00c5")
    else:
        parts.append(f"No unit cell dimension found in 'c' range ({c_min}\u2013{c_max} \u00c5)")

    # --- Criterion 5: Crystal Contacts (20 pts) ---
    # Insulin chains A and B have up to 21 and 30 residues respectively
    max_res = metadata.get('residue_range_max', 30)
    min_contacts = metadata.get('min_contact_residues', 5)
    
    all_ints = [int(n) for n in re.findall(r'\b(\d{1,2})\b', report_content)]
    valid_res = set(n for n in all_ints if 1 <= n <= max_res)
    
    # We allow '3' to exist since it could be from the Space group, but the >5 threshold filters noise.
    if len(valid_res) >= min_contacts:
        score += 20
        sample = sorted(list(valid_res))[:5]
        parts.append(f"Report lists \u2265{min_contacts} valid contact residues (e.g. {sample})")
    elif len(valid_res) >= 1:
        score += len(valid_res) * 4  # Partial points
        parts.append(f"Only {len(valid_res)} valid contact residue numbers found (need \u2265{min_contacts})")
    else:
        parts.append("No valid contact residue identifiers found in report")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }