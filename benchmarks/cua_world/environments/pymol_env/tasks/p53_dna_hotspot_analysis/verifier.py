#!/usr/bin/env python3
"""
Verifier for the p53 DNA Hotspot Analysis task (PDB:1TSR).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report exists with >= 8 lines of content
  25 pts - Report contains >= 4 of the 6 key hotspot residue numbers (175, 245, 248, 249, 273, 282)
  20 pts - Report contains at least one plausible distance measurement (2.0–10.0 A) representing
           the distance between a contact residue (R248 or R273) and the DNA.
  15 pts - Report distinguishes between "contact" and "structural" mutations using appropriate
           classification language.

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing image files
  - Hotspot residues check: ensures actual cancer biology domain knowledge/analysis is recorded
  - Distance check: requires actual measurement in Angstroms, not arbitrary numbers
  - Classification check: validates the required cognitive task of separating mutation types
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_p53_dna_hotspot_analysis(traj, env_info, task_info):
    """Verify the p53 DNA hotspot analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/p53_hotspot_result.json')

    # Copy the result JSON from the container
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
        parts.append(f"Hotspot figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Hotspot figure not found at expected path")

    # --- Criterion 2: Report existence and length (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    
    lines = [line for line in report_content.split('\n') if line.strip()]
    min_lines = metadata.get('min_report_lines', 8)

    if report_exists and len(lines) >= min_lines:
        score += 15
        parts.append(f"Report has sufficient length ({len(lines)} lines)")
    elif report_exists and len(lines) >= 4:
        score += 8
        parts.append(f"Report is too short ({len(lines)} lines, expected >={min_lines})")
    elif report_exists:
        parts.append(f"Report exists but is largely empty ({len(lines)} lines)")
    else:
        parts.append("Report file not found")

    # --- Criterion 3: Hotspot residue identification (25 pts) ---
    expected_hotspots = metadata.get('hotspot_residues', [175, 245, 248, 249, 273, 282])
    min_hotspots = metadata.get('min_hotspots_required', 4)
    
    found_hotspots = []
    for hs in expected_hotspots:
        # Match the number as a discrete word boundary
        if re.search(rf'\b{hs}\b', report_content):
            found_hotspots.append(hs)
            
    if len(found_hotspots) >= min_hotspots:
        score += 25
        parts.append(f"Identified {len(found_hotspots)} hotspot residues ({found_hotspots})")
    elif len(found_hotspots) > 0:
        score += int(25 * (len(found_hotspots) / min_hotspots))
        parts.append(f"Only identified {len(found_hotspots)} hotspot residues (expected >={min_hotspots})")
    else:
        parts.append("No required hotspot residues identified in report")

    # --- Criterion 4: Plausible distance measurement (20 pts) ---
    dist_min = metadata.get('distance_min_angstroms', 2.0)
    dist_max = metadata.get('distance_max_angstroms', 10.0)
    
    # Extract all floats
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 20
        parts.append(f"Found plausible distance measurement: {valid_distances[0]:.2f} \u00c5")
    elif all_decimals:
        parts.append(f"Found decimal values {all_decimals[:3]} but none in valid range ({dist_min}-{dist_max} \u00c5)")
    else:
        parts.append("No distance measurements found in report")

    # --- Criterion 5: Mutation Classification (15 pts) ---
    has_contact = bool(re.search(r'(?i)(contact|bind|groove|phosphate|direct)', report_content))
    has_structural = bool(re.search(r'(?i)(structur|fold|destabiliz|zinc|scaffold|indirect)', report_content))
    
    if has_contact and has_structural:
        score += 15
        parts.append("Correctly distinguishes between contact and structural mutations")
    elif has_contact or has_structural:
        score += 7
        parts.append("Partially classifies mutations (missing either structural or contact terminology)")
    else:
        parts.append("Missing required mutation classification terminology")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }