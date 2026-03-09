#!/usr/bin/env python3
"""
Verifier for engle_granger_cointegration task.

Verifies:
1. Output file exists and was created during task
2. File content contains ADF tests for both variables
3. File content contains cointegrating regression results (coeff ~ 1.0)
4. File content contains Engle-Granger test statistic
5. File content contains correct conclusion
6. VLM workflow verification (trajectory analysis)
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_engle_granger_cointegration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Get task result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Get content of result file
    content = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/gretl_output/cointegration_results.txt", temp_txt.name)
        with open(temp_txt.name, 'r') as f:
            content = f.read()
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        feedback_parts.append("Result file could not be read")
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    content_lower = content.lower()
    
    # --- SCORING CRITERIA ---

    # Criterion 1: Output file exists and non-trivial (10 pts)
    if task_result.get("output_exists") and task_result.get("file_created_during_task"):
        if task_result.get("output_size_bytes", 0) > 100 and len(content.splitlines()) >= 10:
            score += 10
            feedback_parts.append("[+10] Result file exists and is non-trivial")
        else:
            feedback_parts.append("[+0] Result file exists but is empty or too small")
    else:
        feedback_parts.append("[+0] Result file missing or pre-dated task")

    # Criterion 2: ADF test for lgdp present (12 pts)
    if re.search(r"(adf|augmented dickey|dickey-fuller|unit.root).*(lgdp|gdp|l_gdp)", content_lower) or \
       re.search(r"(lgdp|gdp|l_gdp).*(adf|augmented dickey|dickey-fuller|unit.root)", content_lower):
        score += 12
        feedback_parts.append("[+12] ADF test for lgdp found")
    else:
        feedback_parts.append("[+0] ADF test for lgdp not found")

    # Criterion 3: ADF test for lcons present (12 pts)
    if re.search(r"(adf|augmented dickey|dickey-fuller|unit.root).*(lcons|cons|l_cons|pce|consumption)", content_lower) or \
       re.search(r"(lcons|cons|l_cons|pce|consumption).*(adf|augmented dickey|dickey-fuller|unit.root)", content_lower):
        score += 12
        feedback_parts.append("[+12] ADF test for lcons found")
    else:
        feedback_parts.append("[+0] ADF test for lcons not found")

    # Criterion 4: Unit root correctly identified (10 pts)
    unit_root_mentions = len(re.findall(r"(i\(1\)|unit.root|non.?stationary|cannot reject|fail.*reject)", content_lower))
    if unit_root_mentions >= 2 or re.search(r"(both|all).*series.*(i\(1\)|unit.root|integrated)", content_lower):
        score += 10
        feedback_parts.append("[+10] Unit root correctly identified")
    else:
        feedback_parts.append("[+0] Unit root identification unclear")

    # Criterion 5: Cointegrating regression present (15 pts)
    # Check for coefficient close to 1.0 (range 0.7 to 1.3)
    coint_reg_found = False
    if re.search(r"(coefficient|coeff|beta|lgdp|slope).*[=: ]+[01]\.[0-9]", content) or \
       re.search(r"lgdp\s+[01]\.[0-9]", content):
        coint_reg_found = True
    elif "ols" in content_lower and re.search(r"[01]\.[0-9]", content):
        coint_reg_found = True  # Partial match if strict format fails
    
    if coint_reg_found:
        score += 15
        feedback_parts.append("[+15] Cointegrating regression present")
    else:
        feedback_parts.append("[+0] Cointegrating regression coefficient not found")

    # Criterion 6: Engle-Granger test statistic present (15 pts)
    # Expect negative value, typically -3 to -6
    if re.search(r"(coint|engle|granger|cointegrat).*-[2-9]\.[0-9]", content_lower) or \
       re.search(r"tau_c.*=.*-[2-9]", content_lower) or \
       re.search(r"test.stat.*-[2-9]", content_lower):
        score += 15
        feedback_parts.append("[+15] Engle-Granger test statistic found")
    else:
        feedback_parts.append("[+0] Engle-Granger test statistic not found")

    # Criterion 7: Conclusion present (16 pts)
    if re.search(r"(cointegrat.*(found|exists|present|confirmed|detected|established|reject.*null|evidence.*for))", content_lower) or \
       re.search(r"(reject.*(null|no cointegrat))", content_lower) or \
       re.search(r"(series.*are.*cointegrat)", content_lower):
        score += 16
        feedback_parts.append("[+16] Cointegration conclusion correctly stated")
    else:
        feedback_parts.append("[+0] Conclusion unclear")

    # Criterion 8: VLM Workflow Verification (10 pts)
    # Verify the agent actually did the work using trajectory frames
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a user working in Gretl (econometrics software).
        Do you see evidence of:
        1. Using the 'Console' or 'Script' window?
        2. Running commands like 'adf', 'ols', or 'coint'?
        3. Viewing text output results?
        
        Answer YES only if you see clear evidence of econometric analysis work.
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res and vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
            score += 10
            feedback_parts.append("[+10] VLM verified workflow")
        else:
            feedback_parts.append("[+0] VLM could not verify workflow")
    else:
        # Fallback if no frames available (shouldn't happen in standard run)
        feedback_parts.append("[+0] No trajectory frames for VLM verification")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }