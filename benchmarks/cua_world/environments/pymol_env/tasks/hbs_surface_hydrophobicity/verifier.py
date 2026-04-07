#!/usr/bin/env python3
"""
Verifier for the Sickle Cell Hemoglobin Surface Hydrophobicity Analysis task.

Scoring (100 points total):
  15 pts - Modified PDB file exists at the correct path.
  25 pts - Hydrophobic residues in the PDB have an average B-factor > 45.0 (Target: 50.0).
  25 pts - Polar/charged residues in the PDB have an average B-factor < 15.0 and > 0.0 (Target: 10.0).
  10 pts - Report correctly identifies Valine 6 and Chains B/D.
  10 pts - Report identifies acceptor pocket residues (Phe85, Leu88) and gives a physically 
           plausible distance (15-35 Å) between Val6 and Phe85.
  15 pts - Publication figure exists, is newly created, and is non-trivial (>30KB).

Pass threshold: 75/100

Anti-gaming:
  - Direct PDB parsing ensures the agent genuinely used PyMOL commands (e.g., `alter`) or the 
    Python API to modify the coordinate file in memory and export it, rather than just coloring it 
    temporarily or using an arbitrary pre-existing dataset.
  - Figure timestamp checking ensures it was created during the task.
  - Required specific distance bound (15-35 Å) acts as proof of real geometric measurement.
  - Maximum score without modifying B-factors is 15+0+0+10+10+15 = 50 < 75. 
    The agent MUST succeed at the core programmatic property mapping skill to pass.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hbs_surface_hydrophobicity(traj, env_info, task_info):
    """Verify the Sickle Cell Hemoglobin Surface Hydrophobicity Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/hbs_result.json')

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

    # --- Criterion 1: Modified PDB exists (15 pts) ---
    if result.get('pdb_exists', False):
        score += 15
        parts.append("Modified PDB file saved successfully")
    else:
        parts.append("Modified PDB file NOT found at expected path")

    # --- Criterion 2 & 3: B-factor Modifications (25 pts + 25 pts) ---
    avg_b_hydro = result.get('avg_b_hydro', 0.0)
    avg_b_polar = result.get('avg_b_polar', 0.0)

    if result.get('pdb_exists', False):
        if avg_b_hydro > 45.0:
            score += 25
            parts.append(f"Hydrophobic B-factors successfully modified (Avg: {avg_b_hydro:.1f})")
        else:
            parts.append(f"Hydrophobic B-factors not properly set to ~50.0 (Avg: {avg_b_hydro:.1f})")

        if 0.0 < avg_b_polar < 15.0:
            score += 25
            parts.append(f"Polar B-factors successfully modified (Avg: {avg_b_polar:.1f})")
        else:
            parts.append(f"Polar B-factors not properly set to ~10.0 (Avg: {avg_b_polar:.1f})")

    # --- Criterion 4: Report Content - Identifications (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')

    val6_found = bool(re.search(r'(?i)\b(val\s*6|valine\s*6|v6)\b', report_content))
    chains_found = bool(re.search(r'(?i)\b(chain\s*b|chain\s*d)\b', report_content))
    
    if val6_found and chains_found:
        score += 10
        parts.append("Valine 6 mutation and Beta Chains (B/D) correctly identified in report")
    elif val6_found or chains_found:
        score += 5
        parts.append("Partial identification in report (missing either Val6 or Chain B/D)")
    else:
        parts.append("Valine 6 mutation details missing from report")

    # --- Criterion 5: Report Content - Pocket & Distance (10 pts) ---
    phe85_found = bool(re.search(r'(?i)\b(phe\s*85|phenylalanine\s*85|f85)\b', report_content))
    leu88_found = bool(re.search(r'(?i)\b(leu\s*88|leucine\s*88|l88)\b', report_content))
    
    dist_min = metadata.get('distance_min', 15.0)
    dist_max = metadata.get('distance_max', 35.0)
    
    all_decimals = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if phe85_found and leu88_found and valid_distances:
        score += 10
        parts.append(f"Acceptor pocket correctly identified with valid distance: {valid_distances[0]:.2f} \u00c5")
    elif (phe85_found or leu88_found) and valid_distances:
        score += 7
        parts.append(f"Partial acceptor pocket identified with valid distance: {valid_distances[0]:.2f} \u00c5")
    elif phe85_found and leu88_found:
        score += 5
        parts.append("Acceptor pocket identified, but missing/invalid distance measurement")
    else:
        parts.append("Acceptor pocket and valid distance measurement missing from report")

    # --- Criterion 6: Publication figure (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Surface figure successfully created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 5
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Surface figure not found at expected path")

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }