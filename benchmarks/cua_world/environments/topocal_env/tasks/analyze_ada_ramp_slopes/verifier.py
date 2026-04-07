#!/usr/bin/env python3
"""
Verifier for analyze_ada_ramp_slopes task in TopoCal.

VERIFICATION STRATEGY:
1. Copy JSON result exported by export_result.ps1
2. Analyze report content for logical correctness (Ramp A=PASS, B=FAIL, C=FAIL)
3. Confirm files were created during task (Anti-Gaming)
4. Confirm DXF file contains annotation strings
5. Query VLM over trajectory frames to ensure TopoCal measuring/drafting was done.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent using TopoCal (a topographic CAD software).
The agent was asked to:
1. Import a point file (`intersection_asbuilt.xyz`).
2. Measure point-to-point distances/slopes for ramps.
3. Draw lines around the ramps.
4. Add "PASS" and "FAIL" text annotations to the drawing.

Review these trajectory screenshots and determine:
1. Did the agent open or interact with the TopoCal application?
2. Did the agent import point data (are there points visible in the drawing area)?
3. Did the agent use measuring tools, draft lines, or place text annotations inside TopoCal?

Respond EXACTLY in this JSON format:
{
    "used_topocal": true/false,
    "imported_points": true/false,
    "drafted_or_measured": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_ada_ramp_slopes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result File
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='ascii', errors='ignore') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract state metrics
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    report_content = result.get('report_content', '').upper()
    dxf_exists = result.get('dxf_exists', False)
    dxf_created = result.get('dxf_created_during_task', False)
    dxf_pass_fail = result.get('dxf_contains_pass_fail', False)

    # Criterion 1: Files created during task (Anti-Gaming)
    if report_exists and report_created:
        score += 10
        feedback_parts.append("Report file created successfully.")
    elif report_exists:
        feedback_parts.append("Report file exists but was NOT created during task (Possible cheating).")
        
    if dxf_exists and dxf_created:
        score += 10
        feedback_parts.append("DXF drawing created successfully.")
    elif dxf_exists:
        feedback_parts.append("DXF exists but was NOT created during task.")

    # Criterion 2: Logic Evaluation in Report
    if report_exists and report_content:
        # Check Ramp A (Should PASS)
        if re.search(r'RAMP\s*A[^A-Z]*(PASS|FAIL)', report_content):
            if 'RAMP A' in report_content and 'PASS' in re.search(r'RAMP\s*A.*?(\bPASS\b|\bFAIL\b)', report_content).group():
                score += 15
                feedback_parts.append("Ramp A correctly evaluated as PASS.")
            else:
                feedback_parts.append("Ramp A incorrectly evaluated.")
                
        # Check Ramp B (Should FAIL due to Cross Slope)
        if re.search(r'RAMP\s*B[^A-Z]*(PASS|FAIL)', report_content):
            if 'RAMP B' in report_content and 'FAIL' in re.search(r'RAMP\s*B.*?(\bPASS\b|\bFAIL\b)', report_content).group():
                score += 15
                feedback_parts.append("Ramp B correctly evaluated as FAIL.")
            else:
                feedback_parts.append("Ramp B incorrectly evaluated.")

        # Check Ramp C (Should FAIL due to Running Slope)
        if re.search(r'RAMP\s*C[^A-Z]*(PASS|FAIL)', report_content):
            if 'RAMP C' in report_content and 'FAIL' in re.search(r'RAMP\s*C.*?(\bPASS\b|\bFAIL\b)', report_content).group():
                score += 10
                feedback_parts.append("Ramp C correctly evaluated as FAIL.")
            else:
                feedback_parts.append("Ramp C incorrectly evaluated.")
    else:
        feedback_parts.append("Report missing or empty. Cannot check slope logic.")

    # Criterion 3: DXF Annotation verification
    if dxf_exists and dxf_pass_fail:
        score += 10
        feedback_parts.append("DXF file contains compliance annotations.")
    elif dxf_exists:
        feedback_parts.append("DXF file is missing PASS/FAIL text entities.")

    # Criterion 4: VLM Trajectory check
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_topocal'):
                        score += 10
                        feedback_parts.append("VLM confirms TopoCal usage.")
                    if parsed.get('imported_points'):
                        score += 10
                        feedback_parts.append("VLM confirms point import.")
                    if parsed.get('drafted_or_measured'):
                        score += 10
                        feedback_parts.append("VLM confirms drafting/measuring activity.")
                else:
                    feedback_parts.append(f"VLM verification failed: {vlm_res.get('error')}")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append(f"VLM exception: {e}")
    else:
        feedback_parts.append("VLM function not available - skipping visual verification.")

    key_criteria_met = (report_exists and dxf_exists and (score >= 60))
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }