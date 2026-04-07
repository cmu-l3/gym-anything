#!/usr/bin/env python3
"""
Verifier for the OmpF Porin Constriction Zone Analysis task (PDB: 2OMF).

Scoring (100 points total):
  20 pts - Valid PNG Figure: Exists at correct path, >50KB, generated post-start.
  10 pts - Report Exists: Exists and has >50 bytes of content.
  15 pts - Fold Identified: Correctly identifies the main structure as a beta-barrel.
  20 pts - Basic Residues: Explicitly mentions >=2 basic residues (Arg42, Arg82, Arg132).
  20 pts - Acidic Residues: Explicitly mentions key L3 acidic residues (Asp113, Glu117).
  15 pts - Pore Measurement: Plausible Arg82-Asp113 distance (7.0-18.0 A).

Pass threshold: 70/100 (Must have the figure generated AND at least one set of correct residues identified).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_ompf_porin_constriction_zone_analysis(traj, env_info, task_info):
    """Verify the OmpF Porin Constriction Zone Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ompf_result.json')

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

    # --- Criterion 1: Valid PNG Figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 50000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Constriction zone figure not found at expected path")

    # --- Criterion 2: Report Exists (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    min_rep_size = metadata.get('min_report_size_bytes', 50)

    if report_exists and report_size >= min_rep_size:
        score += 10
        parts.append(f"Report exists ({report_size} bytes)")
    elif report_exists:
        parts.append(f"Report exists but is too small ({report_size} bytes)")
    else:
        parts.append("Structural report not found")

    # Only process textual requirements if report exists
    has_basic = False
    has_acidic = False

    if report_exists and report_content:
        # --- Criterion 3: Fold Identified (15 pts) ---
        if re.search(r'\b(?:beta|β)[\s-]*barrel\b', report_content, re.IGNORECASE):
            score += 15
            parts.append("Fold correctly identified as beta-barrel")
        else:
            parts.append("Beta-barrel fold not identified in report")

        # --- Criterion 4: Basic Residues (20 pts) ---
        basic_found = set()
        for res in ['42', '82', '132']:
            if re.search(r'\b(?:R|Arg|Arginine)[\s-]*' + res + r'\b', report_content, re.IGNORECASE):
                basic_found.add(res)
        
        if len(basic_found) >= 2:
            score += 20
            has_basic = True
            parts.append(f"Basic cluster identified: {', '.join(['Arg'+r for r in basic_found])}")
        elif len(basic_found) == 1:
            score += 10
            parts.append(f"Partial basic cluster identified (only 1 key arginine)")
        else:
            parts.append("Basic wall residues not properly identified")

        # --- Criterion 5: Acidic Residues (20 pts) ---
        has_d113 = bool(re.search(r'\b(?:D|Asp|Aspartic\s*Acid)[\s-]*113\b', report_content, re.IGNORECASE))
        has_e117 = bool(re.search(r'\b(?:E|Glu|Glutamic\s*Acid)[\s-]*117\b', report_content, re.IGNORECASE))
        
        if has_d113 and has_e117:
            score += 20
            has_acidic = True
            parts.append("Key L3 acidic residues (Asp113, Glu117) identified")
        elif has_d113 or has_e117:
            score += 10
            parts.append("Only one key L3 acidic residue identified")
        else:
            parts.append("Key L3 acidic residues not identified")

        # --- Criterion 6: Pore Measurement (15 pts) ---
        dist_min = metadata.get('distance_min', 7.0)
        dist_max = metadata.get('distance_max', 18.0)
        
        all_decimals = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]
        valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

        if valid_distances:
            score += 15
            parts.append(f"Plausible pore distance measured: {valid_distances[0]:.2f} \u00c5")
        elif all_decimals:
            parts.append(f"Decimals found but none in plausible pore range ({dist_min}-{dist_max} \u00c5)")
        else:
            parts.append("No distance measurement found in report")
            
    # Determine pass/fail
    # Pass threshold: 70 points AND figure exists AND at least one residue set identified
    passed = (score >= 70) and fig_exists and (has_basic or has_acidic)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }