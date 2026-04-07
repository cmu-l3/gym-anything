#!/usr/bin/env python3
"""
Verifier for Chloroplast Genome Inverted Repeat Mapping task.
Scores multiple independent signals: 
- Custom Annotations presence in GenBank
- Spatial bounds of the massive ~26kb inverted repeats
- Sequence extraction
- Arithmetic synthesis of Large/Small Single Copy lengths
- Trajectory VLM evidence of tool usage
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing the agent's workflow in a bioinformatics application (UGENE).
Please review these screenshots from the agent's trajectory. 

Determine if the agent actively engaged with structural sequence analysis tools. 
Look for:
1. The Sequence View or Alignment View being open.
2. Interaction with tools like "Find Repeats", "Find Inverted Repeats", or "Dotplot".
3. Visual evidence of annotations being created or modified on a sequence.

Respond in strict JSON format:
{
    "engaged_with_analysis_tools": true/false,
    "reasoning": "Brief explanation of what is visible"
}
"""

def verify_chloroplast_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not found."}

    # Fetch ground truth bounds from metadata
    meta = task_info.get('metadata', {}).get('expected_values', {})
    gt_ir_len = meta.get('ir_length', 26266)
    gt_irb_start = meta.get('irb_start', 84171)
    gt_ira_start = meta.get('ira_start', 128212)
    gt_lsc = meta.get('lsc_length', 84170)
    gt_ssc = meta.get('ssc_length', 17775)
    tol = meta.get('tolerance_bp', 300)

    # 1. Load result JSON from the container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/cp_mapping_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            res = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load verification data: {e}. Agent likely did not complete the task."
        }

    score = 0
    feedback = []

    # --- CRITERION 1: GenBank File and Annotation Group (15 pts) ---
    c1 = 0
    if res.get("gb_exists", False):
        c1 += 5
        if res.get("gb_valid", False):
            c1 += 5
            if res.get("has_cp_structure_group", False):
                c1 += 5
                feedback.append("GenBank valid with 'cp_structure' group (+15)")
            else:
                feedback.append("GenBank valid but missing 'cp_structure' group (+10)")
        else:
            feedback.append("GenBank file invalid format (+5)")
    else:
        feedback.append("GenBank file MISSING (0)")
    score += c1

    # --- CRITERION 2: IR Length and Positional Accuracy (30 pts) ---
    c2 = 0
    annotations = res.get("annotations", [])
    if len(annotations) >= 2:
        c2 += 10
        feedback.append(f"Found {len(annotations)} 'Inverted_Repeat' annotations (+10)")
        
        # Check lengths and positions
        valid_irs = 0
        for ann in annotations:
            length = ann["end"] - ann["start"] + 1
            if abs(length - gt_ir_len) <= tol:
                # Is it IRa or IRb?
                if abs(ann["start"] - gt_irb_start) <= tol or abs(ann["start"] - gt_ira_start) <= tol:
                    valid_irs += 1
                    
        if valid_irs >= 2:
            c2 += 20
            feedback.append("Two massive IRs correctly located (~26kb) (+20)")
        elif valid_irs == 1:
            c2 += 10
            feedback.append("Only one IR correctly located (+10)")
        else:
            feedback.append("Annotations found but coordinates/lengths are incorrect (0)")
    elif len(annotations) == 1:
        c2 += 5
        feedback.append("Only one 'Inverted_Repeat' annotation found (+5)")
    else:
        feedback.append("No 'Inverted_Repeat' annotations found (0)")
    score += c2

    # --- CRITERION 3: Extracted IR FASTA (15 pts) ---
    c3 = 0
    if res.get("fasta_exists", False):
        fasta_len = res.get("fasta_len", 0)
        if abs(fasta_len - gt_ir_len) <= tol:
            c3 += 15
            feedback.append(f"IR sequence correctly extracted to FASTA ({fasta_len}bp) (+15)")
        else:
            c3 += 5
            feedback.append(f"FASTA extracted but wrong length ({fasta_len}bp) (+5)")
    else:
        feedback.append("Extracted FASTA file MISSING (0)")
    score += c3

    # --- CRITERION 4: Structural Report (20 pts) ---
    c4 = 0
    if res.get("report_exists", False):
        c4 += 5
        lsc = res.get("report_lsc")
        ssc = res.get("report_ssc")
        
        if lsc is not None and abs(lsc - gt_lsc) <= tol:
            c4 += 8
            feedback.append("LSC length correctly calculated and reported (+8)")
        elif lsc is not None:
            feedback.append(f"LSC reported but incorrect (Found: {lsc})")
            
        if ssc is not None and abs(ssc - gt_ssc) <= tol:
            c4 += 7
            feedback.append("SSC length correctly calculated and reported (+7)")
        elif ssc is not None:
            feedback.append(f"SSC reported but incorrect (Found: {ssc})")
            
        if lsc is None and ssc is None:
            feedback.append("Report exists but missing LSC/SSC calculations")
    else:
        feedback.append("Structural report file MISSING (0)")
    score += c4

    # --- CRITERION 5: Trajectory VLM Check (20 pts) ---
    c5 = 0
    try:
        from vlm_utils import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("engaged_with_analysis_tools", False):
            c5 = 20
            feedback.append("VLM confirms tool engagement (+20)")
        else:
            feedback.append("VLM could not confirm tool engagement (0)")
    except Exception as e:
        logger.warning(f"VLM verification failed/unavailable: {e}")
        # If VLM is broken/unavailable but programmatic signals are strong, grant the points
        if score >= 60:
            c5 = 20
            feedback.append("VLM skipped but programmatic evidence is strong (+20)")
    score += c5

    # Evaluate Pass/Fail
    # To pass, they must have placed the annotations correctly AND reported the math
    key_criteria_met = (c2 >= 20) and (c4 >= 10)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }