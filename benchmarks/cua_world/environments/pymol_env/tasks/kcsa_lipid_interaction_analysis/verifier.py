#!/usr/bin/env python3
"""
Verifier for KcsA Lipid Interaction Analysis task.

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new, and is non-trivial (>30KB)
  10 pts - Report file exists and is not empty
  20 pts - Report correctly identifies Chain C as the KcsA channel
  25 pts - Report contains the correct minimum distance from DGA to Arg64 (within tolerance)
  25 pts - Report contains the correct minimum distance from DGA to Arg89 (within tolerance)

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_kcsa_lipid_interaction_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/kcsa_lipid_result.json')
    dist_tolerance = metadata.get('distance_tolerance', 0.5)

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

    # --- Criterion 1: Figure exists, is new, >30KB (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/kcsa_lipid.png")

    # --- Criterion 2: Report exists (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    
    if report_exists and len(report_content.strip()) > 5:
        score += 10
        parts.append("Report file exists with content")
    else:
        parts.append("Report file not found or empty")

    # --- Criterion 3: Correct Chain ID identified (20 pts) ---
    # KcsA is chain C in 1K4C
    explicit_chains = re.findall(r'\b[Cc]hain\s*[:=]?\s*([A-Za-z])\b', report_content)
    if explicit_chains:
        has_chain_c = any(c.upper() == 'C' for c in explicit_chains)
        has_other_chains = any(c.upper() in ['A', 'B'] for c in explicit_chains)
    else:
        # Fallback to standalone letters
        letters = re.findall(r'\b([ABC])\b', report_content)
        has_chain_c = 'C' in letters
        has_other_chains = 'A' in letters or 'B' in letters
    
    if has_chain_c and not has_other_chains:
        score += 20
        parts.append("Correctly identified Chain C as KcsA")
    elif has_chain_c:
        score += 10
        parts.append("Mentioned Chain C, but also mentioned other chains")
    else:
        parts.append("Did not correctly identify KcsA as Chain C")

    # --- Criterion 4 & 5: Distances to Arg64 and Arg89 (25 pts each) ---
    gt_dist64 = result.get('gt_dist64', 5.2)
    gt_dist89 = result.get('gt_dist89', 2.9)
    
    # Extract all numbers from report (ints and floats)
    all_numbers = [float(n) for n in re.findall(r'\b\d+(?:\.\d+)?\b', report_content)]
    
    dist64_found = False
    dist89_found = False
    
    for d in all_numbers:
        # Ignore obvious non-distance numbers like residue indices or generic integers
        if d in [64.0, 89.0, 1.0, 4.0]: 
            continue
            
        if abs(d - gt_dist64) <= dist_tolerance and not dist64_found:
            score += 25
            dist64_found = True
            parts.append(f"Arg64 distance accurate: {d} \u00c5 (GT: {gt_dist64:.2f})")
        elif abs(d - gt_dist89) <= dist_tolerance and not dist89_found:
            score += 25
            dist89_found = True
            parts.append(f"Arg89 distance accurate: {d} \u00c5 (GT: {gt_dist89:.2f})")
            
    if not dist64_found:
        parts.append(f"Arg64 distance not found or inaccurate (expected ~{gt_dist64:.2f} \u00c5)")
    if not dist89_found:
        parts.append(f"Arg89 distance not found or inaccurate (expected ~{gt_dist89:.2f} \u00c5)")

    # To pass: must exceed 70 points AND have basic deliverables AND correct chain OR at least one correct distance
    passed = score >= 70 and fig_exists and report_exists and (has_chain_c or dist64_found or dist89_found)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }