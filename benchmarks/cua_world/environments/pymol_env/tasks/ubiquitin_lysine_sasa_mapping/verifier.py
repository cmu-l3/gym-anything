#!/usr/bin/env python3
"""
Verifier for the Ubiquitin Lysine SASA Mapping task (PDB:1UBQ).

Scoring (100 points total):
  15 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report exists, is new, and has content
  25 pts - Report correctly maps a value for all 7 lysines (6, 11, 27, 29, 33, 48, 63)
  25 pts - The SASA values are physically realistic (0.0 to 300.0 Å²)
  20 pts - The lysines are correctly ordered in the report from highest SASA to lowest SASA

Pass threshold: 70/100

Anti-gaming:
  - Timestamps: figure_is_new and report_is_new ensure outputs are generated during the session.
  - Value bounds: prevents passing with arbitrary negative or excessively large random numbers.
  - Exact subset mapping: the verifier requires exact mapping for the 7 specific lysines. 
    Fabricated prose without numeric mapping will score zero for the data-extraction criteria.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_ubiquitin_lysine_sasa_mapping(traj, env_info, task_info):
    """Verify the Ubiquitin Lysine SASA mapping task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ubq_lysine_result.json')
    target_lysines = set(metadata.get('target_lysines', [6, 11, 27, 29, 33, 48, 63]))
    sasa_min = metadata.get('sasa_min', 0.0)
    sasa_max = metadata.get('sasa_max', 300.0)

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

    # --- Criterion 1: Publication figure (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Surface visualization figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 8
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Visualization figure not found at /home/ga/PyMOL_Data/images/ubq_lysines.png")

    # --- Criterion 2: Report existence and freshness (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_is_new = result.get('report_is_new', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and report_is_new and len(report_content.strip()) > 10:
        score += 15
        parts.append("Lysine SASA report exists and was newly created")
    elif report_exists and len(report_content.strip()) > 10:
        score += 8
        parts.append("Report exists but may not be newly created")
    elif report_exists:
        parts.append("Report exists but is effectively empty")
    else:
        parts.append("Lysine SASA report not found")

    # --- Parse the report for lysine SASA values ---
    # We want to robustly find lines describing a lysine and its area.
    found_sequence = []
    found_lysines_set = set()

    for line in report_content.splitlines():
        # Look for a lysine identifier (e.g., K6, Lys 11, residue 27, or just the number in context)
        k_match = re.search(r'\b(?:K|Lys|Residue)?\s*(6|11|27|29|33|48|63)\b', line, re.IGNORECASE)
        if k_match:
            k_num = int(k_match.group(1))
            # Remove the identifier substring so we don't extract the residue number as the area
            rest_of_line = line[:k_match.start()] + line[k_match.end():]
            
            # Find the first floating point or integer number remaining on the line
            area_match = re.search(r'\b(\d+(?:\.\d+)?)\b', rest_of_line)
            if area_match:
                val = float(area_match.group(1))
                if k_num not in found_lysines_set:
                    found_lysines_set.add(k_num)
                    found_sequence.append((k_num, val))

    # --- Criterion 3: All 7 lysines identified (25 pts) ---
    missing_lysines = target_lysines - found_lysines_set
    if len(missing_lysines) == 0:
        score += 25
        parts.append("All 7 target lysines successfully identified and quantified")
    elif len(found_lysines_set) > 0:
        score += int(25 * (len(found_lysines_set) / 7.0))
        parts.append(f"Found {len(found_lysines_set)}/7 target lysines. Missing: {missing_lysines}")
    else:
        parts.append("Could not parse any target lysines with associated values from the report")

    # --- Criterion 4: Realistic SASA values (25 pts) ---
    if len(found_sequence) > 0:
        all_realistic = True
        for k, v in found_sequence:
            if not (sasa_min <= v <= sasa_max):
                all_realistic = False
                break
        
        if all_realistic:
            score += 25
            parts.append(f"All reported SASA values are physically plausible ({sasa_min}-{sasa_max} \u00c5\u00b2)")
        else:
            parts.append("One or more reported SASA values are outside the physically plausible bounds")
    else:
        parts.append("No SASA values to check for realism")

    # --- Criterion 5: Correct ranking order (20 pts) ---
    if len(found_sequence) > 1:
        values_sequence = [v for k, v in found_sequence]
        is_sorted_desc = all(values_sequence[i] >= values_sequence[i+1] for i in range(len(values_sequence)-1))
        
        if is_sorted_desc:
            score += 20
            parts.append("Lysines are correctly sorted in descending order of solvent accessibility")
        else:
            parts.append("Lysines are NOT sorted in strictly descending order as requested")
    elif len(found_sequence) > 0:
        parts.append("Not enough values found to verify sorting order")

    # Determine final pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }