#!/usr/bin/env python3
"""
Verifier for the Bacteriorhodopsin Proton Wire Analysis task (PDB: 1C3W).

Scoring (100 points total):
  25 pts - Figure Generation: PNG exists, is >30 KB, and has a valid post-start timestamp.
  15 pts - Report Existence & Basics: txt file exists and correctly references PDB 1C3W.
  20 pts - Residue Identification: explicitly mentions Lys216, Asp85, Asp212, and Arg82.
  20 pts - Distance 1: Includes a valid distance measurement for Lys216 to Asp85 (3.5 - 4.8 A).
  20 pts - Distance 2: Includes a valid distance measurement for Lys216 to Asp212 (3.0 - 4.5 A).

Pass threshold: 75/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_bacteriorhodopsin_proton_wire(traj, env_info, task_info):
    """Verify the bacteriorhodopsin active site and proton wire analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/br_pathway_result.json')

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
        parts.append(f"Proton wire figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Proton wire figure not found at /home/ga/PyMOL_Data/images/br_proton_wire.png")

    # --- Criterion 2: Report Basics & PDB ID (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content_lower = report_content.lower().replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and '1c3w' in report_content_lower:
        score += 15
        parts.append("Report exists and references PDB 1C3W")
    elif report_exists:
        score += 5
        parts.append("Report exists but missing explicit mention of 1C3W")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/br_pathway_report.txt")

    # --- Criterion 3: Residue Mentions (20 pts) ---
    # Need to match: Lys216 (or K216), Asp85 (or D85), Asp212 (or D212), Arg82 (or R82)
    has_lys216 = bool(re.search(r'\b(lys|k)\s*216\b', report_content_lower))
    has_asp85  = bool(re.search(r'\b(asp|d)\s*85\b', report_content_lower))
    has_asp212 = bool(re.search(r'\b(asp|d)\s*212\b', report_content_lower))
    has_arg82  = bool(re.search(r'\b(arg|r)\s*82\b', report_content_lower))
    
    found_residues = sum([has_lys216, has_asp85, has_asp212, has_arg82])
    
    if found_residues == 4:
        score += 20
        parts.append("All 4 key residues (Lys216, Asp85, Asp212, Arg82) identified in report")
    elif found_residues > 0:
        score += (found_residues * 5)
        parts.append(f"Only {found_residues}/4 key residues identified")
    else:
        parts.append("None of the key residues were correctly identified in the report")

    # --- Criterion 4 & 5: Distances (20 + 20 pts) ---
    # Find all float values in the report
    decimals = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]
    
    dist_asp85_min = metadata.get('dist_asp85_min', 3.5)
    dist_asp85_max = metadata.get('dist_asp85_max', 4.8)
    dist_asp212_min = metadata.get('dist_asp212_min', 3.0)
    dist_asp212_max = metadata.get('dist_asp212_max', 4.5)

    has_dist_asp85 = any(dist_asp85_min <= d <= dist_asp85_max for d in decimals)
    has_dist_asp212 = any(dist_asp212_min <= d <= dist_asp212_max for d in decimals)
    
    # We want at least two valid distance numbers if they overlap and both are claimed
    valid_unique_measurements = set(d for d in decimals if (dist_asp85_min <= d <= dist_asp85_max) or (dist_asp212_min <= d <= dist_asp212_max))
    
    if has_dist_asp85:
        score += 20
        parts.append(f"Valid Lys216-Asp85 distance found in range {dist_asp85_min}-{dist_asp85_max} \u00c5")
    else:
        parts.append(f"Lys216-Asp85 distance missing or out of range ({dist_asp85_min}-{dist_asp85_max} \u00c5)")

    if has_dist_asp212:
        # Check if we only have 1 single measurement that happens to satisfy both due to overlap
        if has_dist_asp85 and len(valid_unique_measurements) < 2 and len(decimals) < 2:
            score += 10
            parts.append("Only one distance provided, but two are required for full points")
        else:
            score += 20
            parts.append(f"Valid Lys216-Asp212 distance found in range {dist_asp212_min}-{dist_asp212_max} \u00c5")
    else:
        parts.append(f"Lys216-Asp212 distance missing or out of range ({dist_asp212_min}-{dist_asp212_max} \u00c5)")

    # Provide extra diagnostic if decimals were found but out of range
    if not has_dist_asp85 and not has_dist_asp212 and decimals:
        parts.append(f"Decimals found {decimals} do not match the expected structural geometry distances")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }