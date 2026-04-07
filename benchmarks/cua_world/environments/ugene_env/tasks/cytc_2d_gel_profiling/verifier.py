#!/usr/bin/env python3
"""
Verifier for cytc_2d_gel_profiling task.

Criteria:
1. CSV exists and is formatted correctly (4 cols, 8 rows).
2. Extracted lengths are correct.
3. Extracted MW values are within 5% tolerance (Da or kDa handling).
4. Extracted pI values are within +/- 0.5 tolerance.
5. Recommendation text file identifies the min and max pI accessions correctly.
6. VLM Trajectory Verification verifies UGENE UI was used.
"""

import os
import json
import csv
import io
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_mw(mw_str):
    """Parse string like '11.5 kDa' or '11500 Da' into unified Da float."""
    mw_str = mw_str.lower().replace(',', '')
    # Extract numbers
    match = re.search(r'([\d.]+)', mw_str)
    if not match:
        return None
    val = float(match.group(1))
    
    # Heuristic: if < 500, it's likely kDa
    if 'k' in mw_str or val < 500:
        val *= 1000.0
    return val

def verify_vlm_trajectory(traj, query_vlm):
    """Use VLM on trajectory to verify UGENE sequence properties UI usage."""
    if not query_vlm:
        return {"success": False, "verified": False}
        
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            return {"success": False, "verified": False}
            
        prompt = """Examine these trajectory frames from a user operating the UGENE bioinformatics software.
        
Task: Verify that the user interacted with UGENE's Sequence Properties/Statistics interface to view properties like Molecular Weight (MW) and Isoelectric Point (pI).

Check for these indicators:
1. Is the UGENE application open?
2. Is the user viewing protein sequence data (e.g. alignment view or sequence view)?
3. Is a panel or dialog box visible that displays sequence statistics, such as "Length", "Molecular weight", "Isoelectric point"?

Respond in JSON format:
{
    "used_ugene_ui": true/false,
    "viewed_properties": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""
        res = query_vlm(images=frames, prompt=prompt)
        if res.get("success"):
            parsed = res.get("parsed", {})
            return {
                "success": True, 
                "verified": parsed.get("used_ugene_ui", False) and parsed.get("viewed_properties", False)
            }
        return {"success": False, "verified": False}
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return {"success": False, "verified": False}

def verify_cytc_2d_gel_profiling(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load Result
    result = {}
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/cytc_2d_gel_profiling_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    # Load Ground Truth
    gt = {}
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_gt.close()
    try:
        copy_from_env("/tmp/cytc_2d_gel_profiling_gt.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth JSON, using strict fallback: {e}")
    finally:
        if os.path.exists(tmp_gt.name):
            os.unlink(tmp_gt.name)

    # 1. Verify CSV Existence & Format (15 points)
    if not result.get("csv_exists"):
        feedback_parts.append("CSV file missing.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    
    if not result.get("csv_created_during_task"):
        feedback_parts.append("CSV file was not modified during task session (Anti-gaming).")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
        
    csv_content = result.get("csv_content", "")
    reader = csv.DictReader(io.StringIO(csv_content))
    fieldnames = [f.lower().strip() for f in (reader.fieldnames or [])]
    
    required = ["accession", "length", "mw", "pi"]
    has_cols = all(any(req in f for f in fieldnames) for req in required)
    
    rows = list(reader)
    if has_cols and len(rows) >= 8:
        score += 15
        feedback_parts.append("CSV format correct (+15).")
    elif has_cols:
        score += 5
        feedback_parts.append(f"CSV missing rows (found {len(rows)}) (+5).")
    else:
        feedback_parts.append(f"CSV headers incorrect: {fieldnames} (0).")
        
    # Map headers dynamically for extraction
    key_map = {}
    for req in required:
        for f in fieldnames:
            if req in f:
                key_map[req] = reader.fieldnames[fieldnames.index(f)]
                break

    # Extract Agent Data
    agent_data = {}
    if len(key_map) == 4:
        for row in rows:
            acc_raw = row.get(key_map["accession"], "")
            # Clean accession just in case (e.g., P99999)
            match = re.search(r'[P|Q]\d{4,5}', acc_raw)
            if match:
                acc = match.group(0)
            else:
                acc = acc_raw.strip()
                
            try:
                length = float(row.get(key_map["length"], 0))
                mw = parse_mw(row.get(key_map["mw"], "0"))
                pi = float(row.get(key_map["pi"], 0))
                if acc and mw is not None:
                    agent_data[acc] = {"length": length, "mw": mw, "pi": pi}
            except Exception:
                pass

    # Compare against Ground Truth
    gt_seqs = gt.get("sequences", {})
    correct_len = 0
    correct_mw = 0
    correct_pi = 0
    
    for acc, a_vals in agent_data.items():
        # Find matching GT key (agent might have 'P99999' while GT has 'P99999')
        gt_key = next((k for k in gt_seqs.keys() if acc in k), None)
        if not gt_key:
            continue
            
        gt_vals = gt_seqs[gt_key]
        
        # Length check (exact match usually)
        if abs(a_vals["length"] - gt_vals["length"]) <= 1:
            correct_len += 1
            
        # MW check (5% tolerance)
        if abs(a_vals["mw"] - gt_vals["mw"]) / gt_vals["mw"] <= 0.05:
            correct_mw += 1
            
        # pI check (0.5 tolerance)
        if abs(a_vals["pi"] - gt_vals["pi"]) <= 0.5:
            correct_pi += 1

    expected_total = len(gt_seqs) if gt_seqs else 8
    
    # 2. Lengths Correct (15 points)
    len_score = int(15 * (correct_len / expected_total)) if expected_total > 0 else 0
    score += len_score
    feedback_parts.append(f"Lengths correct: {correct_len}/{expected_total} (+{len_score}).")
    
    # 3. MW Correct (15 points)
    mw_score = int(15 * (correct_mw / expected_total)) if expected_total > 0 else 0
    score += mw_score
    feedback_parts.append(f"MW correct: {correct_mw}/{expected_total} (+{mw_score}).")
    
    # 4. pI Correct (15 points)
    pi_score = int(15 * (correct_pi / expected_total)) if expected_total > 0 else 0
    score += pi_score
    feedback_parts.append(f"pI correct: {correct_pi}/{expected_total} (+{pi_score}).")

    # 5. Recommendation Text File (15 points)
    if result.get("txt_exists") and result.get("txt_created_during_task"):
        txt_content = result.get("txt_content", "").lower()
        min_pi_acc = gt.get("min_pi_acc", "").lower()
        max_pi_acc = gt.get("max_pi_acc", "").lower()
        
        found_min = min_pi_acc in txt_content if min_pi_acc else False
        found_max = max_pi_acc in txt_content if max_pi_acc else False
        
        if found_min and found_max:
            score += 15
            feedback_parts.append("Recommendation identifies correct min/max pI (+15).")
        elif found_min or found_max:
            score += 7
            feedback_parts.append("Recommendation identifies one of min/max pI (+7).")
        else:
            feedback_parts.append("Recommendation text lacks correct min/max pI accessions (0).")
    else:
        feedback_parts.append("Recommendation text missing or stale (0).")

    # 6. VLM Trajectory Verification (25 points)
    query_vlm = env_info.get("query_vlm")
    vlm_res = verify_vlm_trajectory(traj, query_vlm)
    if vlm_res.get("verified"):
        score += 25
        feedback_parts.append("VLM verified UGENE UI interaction (+25).")
    else:
        feedback_parts.append("VLM could not verify UGENE UI interaction (0).")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }