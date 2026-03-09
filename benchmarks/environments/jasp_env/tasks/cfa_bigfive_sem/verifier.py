#!/usr/bin/env python3
"""
Verifier for CFA Big Five SEM task.

Evaluates:
1. JASP project file creation (existence & timestamp)
2. Text report creation
3. Content of the text report (Lavaan syntax, Fit indices)
4. VLM visual verification of SEM path diagram
"""

import json
import os
import base64
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cfa_bigfive_sem(traj, env_info, task_info):
    """
    Verify the agent performed a CFA on Big Five data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # CRITERION 1: File Artifacts (30 pts)
    # ------------------------------------------------------------------
    if result.get("jasp_file_exists") and result.get("jasp_file_new") and result.get("jasp_file_size", 0) > 5000:
        score += 20
        feedback_parts.append("JASP project saved correctly (20/20)")
    elif result.get("jasp_file_exists"):
        score += 10
        feedback_parts.append("JASP project exists but timestamp/size suspicious (10/20)")
    else:
        feedback_parts.append("JASP project NOT saved (0/20)")

    if result.get("report_exists"):
        score += 10
        feedback_parts.append("Report file created (10/10)")
    else:
        feedback_parts.append("Report file NOT created (0/10)")

    # ------------------------------------------------------------------
    # CRITERION 2: Report Content Analysis (40 pts)
    # ------------------------------------------------------------------
    report_text = ""
    try:
        if result.get("report_content_b64"):
            report_text = base64.b64decode(result["report_content_b64"]).decode('utf-8', errors='ignore')
    except:
        pass

    if report_text:
        # Check for 5 Factors defined (looking for =~ symbol usually used in lavaan or report text)
        # Or just checking if 5 factor names appear
        factors = ["Agreeableness", "Conscientiousness", "Extraversion", "Neuroticism", "Openness"]
        factors_found = sum(1 for f in factors if f.lower() in report_text.lower())
        
        if factors_found >= 4:
            score += 10
            feedback_parts.append(f"Factors identified in report ({factors_found}/5) (10/10)")
        elif factors_found > 0:
            score += 5
            feedback_parts.append(f"Some factors identified ({factors_found}/5) (5/10)")
            
        # Check for Fit Indices presence
        indices_found = 0
        if "CFI" in report_text or "Comparative Fit Index" in report_text: indices_found += 1
        if "RMSEA" in report_text or "Root Mean Square" in report_text: indices_found += 1
        if "SRMR" in report_text or "Standardized Root Mean" in report_text: indices_found += 1
        if "Chi" in report_text or "chi" in report_text: indices_found += 1
        
        if indices_found >= 3:
            score += 15
            feedback_parts.append("Fit indices reported (15/15)")
        elif indices_found > 0:
            score += 5
            feedback_parts.append("Partial fit indices reported (5/15)")
            
        # Check for Plausible Values
        # CFI usually 0.8-1.0, RMSEA 0.0-0.2
        try:
            cfi = float(result.get("extracted_cfi", 0))
            rmsea = float(result.get("extracted_rmsea", 0))
            if 0.7 < cfi <= 1.0 and 0.0 <= rmsea < 0.3:
                score += 15
                feedback_parts.append("Fit values are plausible (15/15)")
            else:
                feedback_parts.append(f"Fit values implausible or not parsed (CFI={cfi}, RMSEA={rmsea}) (0/15)")
        except:
            feedback_parts.append("Could not parse numeric fit values (0/15)")
    else:
        feedback_parts.append("Report content empty or unreadable (0/40)")

    # ------------------------------------------------------------------
    # CRITERION 3: VLM Visual Verification (30 pts)
    # ------------------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + ([final_screen] if final_screen else [])
    
    if images:
        vlm_prompt = """
        Review these screenshots of a JASP statistical analysis session.
        1. Is the SEM (Structural Equation Modeling) module visible?
        2. Is there a Path Diagram visible (ovals connected to rectangles)?
        3. Is there a table showing "Fit Indices" (CFI, RMSEA, etc.)?
        4. Did the user specify a model with multiple factors (e.g., text input or visual model)?
        
        Respond JSON: {"sem_module": bool, "path_diagram": bool, "fit_table": bool, "model_specified": bool}
        """
        
        vlm_res = query_vlm(images=images, prompt=vlm_prompt).get('parsed', {})
        
        vlm_score = 0
        if vlm_res.get('sem_module'): vlm_score += 5
        if vlm_res.get('path_diagram'): vlm_score += 10
        if vlm_res.get('fit_table'): vlm_score += 10
        if vlm_res.get('model_specified'): vlm_score += 5
        
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/30")
    else:
        feedback_parts.append("No screenshots available for VLM (0/30)")

    # ------------------------------------------------------------------
    # FINAL EVALUATION
    # ------------------------------------------------------------------
    passed = score >= 60 and result.get("jasp_file_exists") and result.get("report_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }