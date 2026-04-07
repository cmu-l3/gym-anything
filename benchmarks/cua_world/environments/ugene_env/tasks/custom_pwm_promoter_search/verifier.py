#!/usr/bin/env python3
"""
Verifier for custom_pwm_promoter_search task.

VERIFICATION STRATEGY:
1. Programmatic checks (70 points max):
   - Matrix file existence and validity (20 points)
   - GFF3 output existence and hit count (30 points)
   - Summary report existence and content (20 points)
2. Trajectory VLM checks (30 points max):
   - Confirms the agent used the UGENE UI for Weight Matrix Builder and Pattern Search
     (prevents gaming via bash scripts generating fake files).

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent performing a bioinformatics task in UGENE.
The agent was tasked with:
1. Building a Position Weight Matrix (PWM) from a set of promoters.
2. Searching a target sequence using that matrix with an 85% threshold.

Examine the provided screenshots from the agent's workflow trajectory.
Determine if the agent used the appropriate UI tools.

Look for:
- "Build weight matrix" dialog box.
- "Search for Pattern" dialog box (with "Weight matrix" tab active).
- A threshold setting visible at "85%".

Respond ONLY in valid JSON format:
{
    "matrix_builder_used": true/false,
    "pattern_search_used": true/false,
    "threshold_85_visible": true/false
}
"""

def verify_custom_pwm_promoter_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Parse JSON results from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Check anti-gaming (files created during task)
    any_file_created = (
        result.get("matrix_created_during_task", False) or 
        result.get("gff_created_during_task", False) or 
        result.get("report_created_during_task", False)
    )
    
    if not any_file_created:
        return {"passed": False, "score": 0, "feedback": "No output files were created during the task session (detected 0 timestamps >= task_start)."}

    # 2. Programmatic Evaluation
    
    # Matrix Evaluation (20 points)
    if result.get("matrix_exists"):
        score += 10
        feedback.append("Matrix file found (+10).")
        if result.get("matrix_is_valid"):
            score += 10
            feedback.append("Matrix file contains expected structure (+10).")
        else:
            feedback.append("Matrix file lacks expected structural content.")
    else:
        feedback.append("Matrix file MISSING.")

    # GFF3 Evaluation (30 points)
    if result.get("gff_exists"):
        score += 15
        feedback.append("GFF3 annotations file found (+15).")
        hits = result.get("gff_hit_count", 0)
        if hits > 0:
            score += 15
            feedback.append(f"GFF3 contains {hits} annotated hits (+15).")
        else:
            feedback.append("GFF3 file is empty (no hits).")
    else:
        feedback.append("GFF3 annotations file MISSING.")

    # Report Evaluation (20 points)
    if result.get("report_exists"):
        score += 10
        feedback.append("Summary report found (+10).")
        if result.get("report_mentions_85"):
            score += 5
            feedback.append("Report explicitly mentions 85% threshold (+5).")
        
        rep_hits = result.get("report_hit_count", 0)
        gff_hits = result.get("gff_hit_count", 0)
        if rep_hits > 0 and rep_hits == gff_hits:
            score += 5
            feedback.append(f"Report accurately lists hit count of {rep_hits} (+5).")
        elif rep_hits > 0:
            score += 3
            feedback.append(f"Report lists hit count of {rep_hits} (+3).")
    else:
        feedback.append("Summary report MISSING.")

    # 3. Trajectory VLM Evaluation (30 points)
    if VLM_AVAILABLE and 'query_vlm' in globals():
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                vlm_score = 0
                
                if parsed.get("matrix_builder_used", False):
                    vlm_score += 10
                    feedback.append("VLM: Matrix builder dialog detected (+10).")
                
                if parsed.get("pattern_search_used", False):
                    vlm_score += 10
                    feedback.append("VLM: Pattern search dialog detected (+10).")
                    
                if parsed.get("threshold_85_visible", False):
                    vlm_score += 10
                    feedback.append("VLM: 85% threshold visibly entered (+10).")
                
                score += vlm_score
            else:
                feedback.append(f"VLM verification failed: {vlm_res.get('error')}. Giving partial credit (+15).")
                score += 15
        else:
            feedback.append("No trajectory frames available for VLM. Giving partial credit (+15).")
            score += 15
    else:
        feedback.append("VLM not available for trajectory verification. Giving partial credit (+15).")
        score += 15

    # Determine Pass/Fail
    # To pass, agent must have created GFF3 output with hits AND achieved >= 70 total score.
    gff_passed = result.get("gff_exists", False) and result.get("gff_hit_count", 0) > 0
    passed = (score >= 70) and gff_passed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }