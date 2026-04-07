#!/usr/bin/env python3
"""
Verifier for the Trypsin Catalytic Triad Analysis task (PDB: 2PTN).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  25 pts - Report mentions all 3 triad residues (Ser195, His57, Asp102) by number
  25 pts - Report contains >=1 distance in the plausible range for these H-bonds (2.0-4.5 Å)
  25 pts - Report has >=5 lines and >=100 characters of substantive content

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - Distance range validation: requires actually performing a measurement, not random guesses
  - Explicit residue numbers (195, 57, 102): prevents generic copy/pasted textbook text
  - Substantive report gate: prevents trivial short outputs
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_trypsin_catalytic_triad_analysis(traj, env_info, task_info):
    """Verify the Trypsin Catalytic Triad analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/trypsin_triad_result.json')

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
        parts.append(f"Catalytic triad figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/trypsin_triad.png")

    # --- Extract Report Details ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    
    if not report_exists:
        parts.append("Report not found at /home/ga/PyMOL_Data/trypsin_triad_report.txt")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(parts)
        }

    # --- Criterion 2: Triad Residue Identification (25 pts) ---
    has_195 = bool(re.search(r'\b195\b', report_content))
    has_57 = bool(re.search(r'\b57\b', report_content))
    has_102 = bool(re.search(r'\b102\b', report_content))
    
    found_residues = sum([has_195, has_57, has_102])
    
    if found_residues == 3:
        score += 25
        parts.append("All 3 catalytic triad residues (57, 102, 195) identified")
    elif found_residues > 0:
        score += 10
        parts.append(f"Only {found_residues}/3 triad residues identified")
    else:
        parts.append("No correct triad residue numbers (57, 102, 195) found in report")

    # --- Criterion 3: Valid H-bond Distances (25 pts) ---
    dist_min = metadata.get('distance_min', 2.0)
    dist_max = metadata.get('distance_max', 4.5)
    
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if len(valid_distances) >= 1:
        score += 25
        parts.append(
            f"Valid H-bond distance reported: {valid_distances[0]:.2f} \u00c5 "
            f"(valid range {dist_min}\u2013{dist_max} \u00c5)"
        )
    elif all_decimals:
        parts.append(
            f"Decimal values found ({all_decimals[:3]}) but none in H-bond distance range "
            f"({dist_min}\u2013{dist_max} \u00c5) \u2014 check measurement"
        )
    else:
        parts.append("No distance value found in report \u2014 must measure H-bonds in Angstroms")

    # --- Criterion 4: Report Length & Content (25 pts) ---
    report_lines = [l.strip() for l in report_content.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 5)
    min_chars = metadata.get('min_report_chars', 100)
    
    if len(report_lines) >= min_lines and len(report_content) >= min_chars:
        score += 25
        parts.append(f"Substantive report written ({len(report_lines)} lines)")
    elif len(report_lines) > 0:
        score += 10
        parts.append(f"Report is too short ({len(report_lines)} lines, {len(report_content)} chars)")
    else:
        parts.append("Report is empty")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }