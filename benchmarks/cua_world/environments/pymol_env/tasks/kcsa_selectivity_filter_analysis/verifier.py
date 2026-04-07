#!/usr/bin/env python3
"""
Verifier for the KcsA Selectivity Filter Analysis task (PDB:1K4C).

Scoring Criteria (100 points total, Pass threshold: 70):
  25 pts - Publication figure exists, >30KB, and is new (post-task-start)
  25 pts - Report correctly identifies K+ ions and records a plausible count (1-8)
  25 pts - Report contains a distance measurement in the physically plausible range 
           for opposing filter carbonyls (2.0-8.0 Å)
  25 pts - Report identifies the selectivity filter sequence (TVGYG) or specific 
           filter residues (T75, V76, G77, Y78, G79)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_kcsa_selectivity_filter_analysis(traj, env_info, task_info):
    """Verify the KcsA selectivity filter analysis."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/kcsa_result.json')

    # Safely load the exported JSON result
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

    # --- Criterion 1: Figure Quality & Timestamp (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may be stale")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Selectivity filter figure not found")

    # --- Read Report ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    report_lower = report_content.lower()

    if not report_exists or not report_content.strip():
        parts.append("Report missing or empty")
        return {"passed": False, "score": score, "feedback": " | ".join(parts)}

    # --- Criterion 2: K+ Ion Identification (25 pts) ---
    k_mentioned = bool(re.search(r'\bk\+?\b|potassium', report_lower))
    
    # Check for K+ count mapping (1-8 plausible inside cavity/filter)
    words = "one|two|three|four|five|six|seven|eight"
    # Matches "4 K+", "four ions", etc.
    pattern1 = r'\b([1-8]|' + words + r')\s*(?:bound\s*)?(?:k\+?|potassium|ions?)\b'
    # Matches "K+ count: 4", "ions: 4", etc.
    pattern2 = r'\b(?:k\+?|potassium|ions?)(?:\s*count)?\s*(?:is|:|=)?\s*([1-8]|' + words + r')\b'
    
    k_count_found = bool(re.search(pattern1, report_lower) or re.search(pattern2, report_lower))

    if k_mentioned and k_count_found:
        score += 25
        parts.append("K+ ions identified with plausible count")
    elif k_mentioned:
        score += 15
        parts.append("K+ ions mentioned but count missing/invalid")
    else:
        parts.append("K+ ions not identified")

    # --- Criterion 3: Pore Distance Measurement (25 pts) ---
    dist_min = metadata.get('pore_distance_min', 2.0)
    dist_max = metadata.get('pore_distance_max', 8.0)
    
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]
    has_distance_context = bool(re.search(r'distance|pore|diameter|angstrom|\u00c5|\ba\b|filter|carbonyl', report_lower))

    if valid_distances and has_distance_context:
        score += 25
        parts.append(f"Pore distance reported: {valid_distances[0]:.2f} \u00c5")
    elif all_decimals and has_distance_context:
        parts.append(f"Distance-like values found but none in range {dist_min}-{dist_max} \u00c5")
    else:
        parts.append("No valid pore distance value found in report")

    # --- Criterion 4: Selectivity Filter Identification (25 pts) ---
    tvgyg_found = bool(re.search(r'TVGYG', report_content, re.IGNORECASE))
    
    res_count = 0
    for res in ["75", "76", "77", "78", "79"]:
        if re.search(rf'\b(T|V|G|Y|Thr|Val|Gly|Tyr|residue\s*)?{res}\b', report_content, re.IGNORECASE):
            res_count += 1

    if tvgyg_found or res_count >= 3:
        score += 25
        parts.append("Selectivity filter (TVGYG) correctly identified")
    elif res_count >= 1:
        score += 10
        parts.append(f"Partial filter identification ({res_count} signature residues)")
    else:
        parts.append("Selectivity filter residues not identified")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }