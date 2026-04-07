#!/usr/bin/env python3
"""
Verifier for protein_biochemical_profiling task.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_float_value(val_str):
    """Robustly extract a float from a string like '69.3 kDa' or '69,321.49'"""
    if not val_str:
        return None
    val_str = str(val_str).replace(',', '').strip()
    match = re.search(r'\d+(?:\.\d+)?', val_str)
    if match:
        val = float(match.group())
        # If the value is suspiciously small for a protein (e.g. < 200),
        # they probably recorded it in kDa. Convert to Da.
        if val < 200:
            val *= 1000.0
        return val
    return None

def find_key(row, possible_names):
    """Find a dictionary key that loosely matches one of the possible names."""
    for k in row.keys():
        if not k: continue
        k_lower = k.lower()
        if any(n in k_lower for n in possible_names):
            return row[k]
    return None

def verify_protein_biochemical_profiling(traj, env_info, task_info):
    """
    Verifies the CSV compilation of Molecular Weight and Isoelectric Points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing."}

    # Extract task metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    tolerance = metadata.get('tolerance_percent', 5.0) / 100.0

    # 1. Retrieve the exported JSON from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check CSV and Row count (15 points)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', [])
    
    if not csv_exists:
        return {"passed": False, "score": 0, "feedback": "gel_calibration.csv was not created."}
    
    if len(csv_rows) >= 5:
        score += 15
        feedback_parts.append("CSV exists with sufficient rows (+15)")
    elif len(csv_rows) > 0:
        score += 5
        feedback_parts.append(f"CSV exists but only has {len(csv_rows)} rows (+5)")
    else:
        feedback_parts.append("CSV exists but is empty (0)")

    # 3. Data Validation (Accessions: 10pts, MW: 25pts, pI: 25pts)
    accession_aliases = ["accession", "id", "protein", "uniprot", "name"]
    mw_aliases = ["molecular weight", "mw", "mass", "weight", "daltons"]
    pi_aliases = ["isoelectric", "pi", "point"]

    accessions_found = set()
    mw_correct_count = 0
    pi_correct_count = 0

    for row in csv_rows:
        acc_str = find_key(row, accession_aliases)
        mw_str = find_key(row, mw_aliases)
        pi_str = find_key(row, pi_aliases)

        if not acc_str:
            continue

        # Find which ground truth protein this row represents
        matched_gt_key = None
        for gt_key in ground_truth.keys():
            if gt_key in acc_str.upper():
                matched_gt_key = gt_key
                break

        if matched_gt_key:
            accessions_found.add(matched_gt_key)
            gt_vals = ground_truth[matched_gt_key]

            # Validate MW
            mw_val = parse_float_value(mw_str)
            if mw_val is not None:
                # check against ±5% tolerance
                lower_bound = gt_vals['mw'] * (1 - tolerance)
                upper_bound = gt_vals['mw'] * (1 + tolerance)
                if lower_bound <= mw_val <= upper_bound:
                    mw_correct_count += 1

            # Validate pI
            pi_val = parse_float_value(pi_str)
            if pi_val is not None:
                lower_bound = gt_vals['pi'] * (1 - tolerance)
                upper_bound = gt_vals['pi'] * (1 + tolerance)
                if lower_bound <= pi_val <= upper_bound:
                    pi_correct_count += 1

    # Score Accessions
    acc_score = len(accessions_found) * 2
    score += acc_score
    feedback_parts.append(f"Found {len(accessions_found)}/5 correct accessions (+{acc_score})")

    # Score MW
    mw_score = mw_correct_count * 5
    score += mw_score
    feedback_parts.append(f"{mw_correct_count}/5 MW values correct (+{mw_score})")

    # Score pI
    pi_score = pi_correct_count * 5
    score += pi_score
    feedback_parts.append(f"{pi_correct_count}/5 pI values correct (+{pi_score})")

    # 4. Check Raw Reports (10 points)
    reports_count = result.get('reports_count', 0)
    ugene_stats_found = result.get('ugene_stats_found', False)

    if reports_count > 0 and ugene_stats_found:
        score += 10
        feedback_parts.append(f"Raw reports saved with UGENE stats (+10)")
    elif reports_count > 0:
        score += 5
        feedback_parts.append(f"Raw reports saved but missing stats text (+5)")
    else:
        feedback_parts.append(f"No raw reports found (0)")

    # 5. VLM Verification of UGENE UI usage (15 points)
    # We want to make sure they actually used the GUI and not just python scripts.
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames

        if images:
            prompt = """
            Look at these trajectory screenshots for a bioinformatics agent operating UGENE.
            Did the agent actively use UGENE's graphical interface to calculate protein properties?
            Look specifically for the 'Sequence Statistics', 'Protein Properties', or alignment windows.
            Return a JSON object with:
            {
                "used_ugene_gui": true or false,
                "reasoning": "brief explanation"
            }
            """
            vlm_res = query_vlm(prompt=prompt, images=images)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_ugene_gui', False):
                    score += 15
                    feedback_parts.append("VLM verified UGENE GUI usage (+15)")
                else:
                    feedback_parts.append("VLM did not detect UGENE GUI usage (0)")
            else:
                feedback_parts.append(f"VLM query failed, skipping 15pts")
    except ImportError:
        logger.warning("VLM module not available, skipping VLM check.")
        feedback_parts.append("VLM verification skipped (module unavailable).")

    # Determine pass threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }