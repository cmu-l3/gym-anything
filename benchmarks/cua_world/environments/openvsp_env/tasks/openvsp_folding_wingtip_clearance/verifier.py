#!/usr/bin/env python3
"""
Verifier for openvsp_folding_wingtip_clearance task.

Robust Multi-Criteria Verification:
1. Output file exists and was modified after start (15 pts) - Anti-gaming
2. XML structure confirms topology was modified (> baseline sections) (35 pts)
3. XML structure confirms 90-degree outer dihedral applied (30 pts)
4. Span calculation report exists (10 pts)
5. Semantic verification of accurate reduced span range (10 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot


def _extract_numeric(text, lo, hi):
    """Search for a numeric value within acceptable physics ranges"""
    numbers = re.findall(r'[+-]?\d+\.?\d*', text)
    for n in numbers:
        try:
            v = float(n)
            if lo <= v <= hi:
                return v
        except ValueError:
            pass
    return None


def verify_openvsp_folding_wingtip_clearance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    result_file = "/tmp/openvsp_folding_wingtip_clearance_result.json"
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)
            
    score = 0
    feedback_parts = []
    
    base_info = data.get('baseline', {})
    fold_info = data.get('folded', {})
    task_start = data.get('task_start', 0)
    
    file_exists = fold_info.get('exists', False)
    mtime = fold_info.get('mtime', 0)
    
    # ------------------------------------------------------------
    # Check 1: File Existence & Modification (15 pts)
    # ------------------------------------------------------------
    if not file_exists:
        feedback_parts.append("File eCRM_folded.vsp3 not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    if mtime > 0 and task_start > 0 and mtime < task_start:
        feedback_parts.append("File eCRM_folded.vsp3 is older than task start (not modified during session)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    score += 15
    feedback_parts.append("File eCRM_folded.vsp3 exists")
        
    # ------------------------------------------------------------
    # Check 2: Topology Modified (35 pts)
    # ------------------------------------------------------------
    base_sections = base_info.get('sections', 4)
    fold_sections = fold_info.get('sections', 0)
    
    if fold_sections > base_sections:
        score += 35
        feedback_parts.append(f"Topology modified: {fold_sections} sections found (baseline had {base_sections})")
    elif fold_sections > 0 and fold_sections == base_sections:
        feedback_parts.append(f"Topology unchanged: {fold_sections} sections found (same as baseline)")
    else:
        feedback_parts.append(f"Topology incorrect: {fold_sections} sections found")
        
    # ------------------------------------------------------------
    # Check 3: Fold Angle Applied (30 pts)
    # ------------------------------------------------------------
    outer_dihedral = fold_info.get('outer_dihedral')
    if outer_dihedral is not None and 85.0 <= outer_dihedral <= 95.0:
        score += 30
        feedback_parts.append(f"Fold angle correct: outer dihedral is {outer_dihedral:.1f} degrees")
    elif outer_dihedral is not None:
        feedback_parts.append(f"Fold angle incorrect: outer dihedral is {outer_dihedral:.1f} degrees")
    else:
        feedback_parts.append("Could not find outer dihedral parameter in XML")
        
    # ------------------------------------------------------------
    # Check 4 & 5: Report Exists & Semantic Span Validation (20 pts)
    # ------------------------------------------------------------
    report_exists = data.get('report_exists', False)
    report_content = data.get('report_content', '')
    
    if report_exists and len(report_content.strip()) > 0:
        score += 10
        feedback_parts.append("Report file exists")
        
        # Original span is ~58m. Folded tip reduction places span between 30 and 55.
        span_val = _extract_numeric(report_content, 30.0, 55.0)
        if span_val is not None:
            score += 10
            feedback_parts.append(f"Reported span {span_val:.1f}m is in acceptable reduced range [30, 55]")
        else:
            feedback_parts.append("Reported span value not found or out of acceptable folded range [30, 55]")
    else:
        feedback_parts.append("Report file not found or empty")
        
    # ------------------------------------------------------------
    # VLM Trajectory Verification
    # ------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if frames and final:
                vlm_prompt = """You are verifying an aerospace engineering task in OpenVSP.
The agent was asked to split the outer wing section of an aircraft and fold it up by 90 degrees.
Look at the trajectory and final screenshot.
1. Did the agent interact with the OpenVSP GUI?
2. Is there a visible fold in the wing (a 90-degree vertical angle on the outer wing panel)?
Respond in JSON format:
{"ui_interaction": true/false, "wing_folded_visible": true/false}"""
                vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("wing_folded_visible"):
                        feedback_parts.append("VLM confirmed visual wing fold")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    
    passed = score >= 80
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}