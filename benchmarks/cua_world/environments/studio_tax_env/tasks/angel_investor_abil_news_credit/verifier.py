#!/usr/bin/env python3
"""
Verifier for angel_investor_abil_news_credit task.

Julian Rossi — T4 ($115,000), T5 ($1,200 actual / $1,656 taxable), 
Allowable Business Investment Loss ($40,000 cost), 
Digital News Credit ($525 paid -> $500 cap), Student Loan Interest ($840).

Verification Strategy:
1. Copy results JSON produced by export_result.ps1
2. Evaluate presence of files, timestamps, and key numeric/string markers.
3. Multi-criteria scoring with a hard cap if the critical concept (ABIL) is entirely missed.
4. Hybrid VLM validation to confirm agent navigation of the workflow trajectory.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_angel_investor_abil_news_credit(traj, env_info, task_info):
    score = 0
    feedback = []

    # CRITICAL: Use copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier Error: No copy_from_env helper"}

    # 1. Retrieve the exported JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        
        copy_from_env("C:/Users/Docker/Desktop/abil_result.json", temp_path)
        
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
            
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}

    # 2. Evaluate Criteria

    # Criterion 1: File saved with correct name & size (10 pts)
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    if file_exists and file_size > 500:
        score += 10
        feedback.append("✅ Return file 'julian_rossi.24t' saved")
    else:
        feedback.append("❌ Return file not found or empty")

    # Criterion 2: Timestamp anti-gaming validation (10 pts)
    if result.get('file_is_new', False):
        score += 10
        feedback.append("✅ File created/modified during task session")
    else:
        feedback.append("❌ File timestamp invalid (prior file used)")

    # Criterion 3: Taxpayer Name (10 pts)
    if result.get('contains_rossi', False) and result.get('contains_julian', False):
        score += 10
        feedback.append("✅ Taxpayer name found")
    else:
        feedback.append("❌ Taxpayer name missing")

    # Criterion 4: T4 Employment Income (15 pts)
    if result.get('contains_115000', False):
        score += 15
        feedback.append("✅ T4 Employment income ($115,000) found")
    else:
        feedback.append("❌ T4 Employment income missing")

    # Criterion 5: T5 Dividend Income (10 pts)
    if result.get('contains_1200', False) or result.get('contains_1656', False):
        score += 10
        feedback.append("✅ T5 Dividend income data found")
    else:
        feedback.append("❌ T5 Dividend data missing")

    # Criterion 6: Allowable Business Investment Loss (ABIL) (20 pts)
    abil_ok = False
    if result.get('contains_40000', False) and result.get('contains_halifax', False):
        abil_ok = True
        score += 20
        feedback.append("✅ ABIL details ($40,000 & CCPC Name) found")
    elif result.get('contains_40000', False):
        score += 10
        feedback.append("⚠️ ABIL partial: Amount found but CCPC name missing")
    else:
        feedback.append("❌ ABIL details missing")

    # Criterion 7: Digital News Credit - Capped at $500 (5 pts)
    if result.get('contains_500', False):
        score += 5
        feedback.append("✅ Digital news credit found (capped at $500)")
    else:
        feedback.append("❌ Digital news credit missing or incorrectly calculated")

    # Criterion 8: Student Loan Interest (5 pts)
    if result.get('contains_840', False):
        score += 5
        feedback.append("✅ Student loan interest ($840) found")
    else:
        feedback.append("❌ Student loan interest missing")

    # 3. Trajectory VLM Verification (15 pts)
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames
        
        if images:
            vlm_prompt = (
                "You are evaluating an agent performing a tax preparation task in StudioTax 2024. "
                "Look at these screenshots representing the agent's workflow trajectory. "
                "Does the agent actively navigate to 'Schedule 3' (Capital Gains/Losses) and specifically "
                "interact with the section for 'Shares of a Small Business Corporation' or 'Business Investment Loss'? "
                "Respond with a JSON object: {\"schedule_3_navigated\": true/false, \"abil_section_used\": true/false}"
            )
            
            try:
                vlm_res = query_vlm(prompt=vlm_prompt, images=images)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('schedule_3_navigated'):
                        vlm_score += 5
                        feedback.append("✅ VLM: Schedule 3 navigation detected")
                    if parsed.get('abil_section_used'):
                        vlm_score += 10
                        feedback.append("✅ VLM: Small Business Corporation/ABIL section interaction detected")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                
    score += vlm_score

    # 4. Enforce Score Cap for Core Complexity
    # If the agent completely missed the ABIL/Capital Loss reporting, they failed the primary learning objective.
    if not abil_ok and score > 55:
        score = 55
        feedback.append("⚠️ SCORE CAPPED: Core task requirement (ABIL reporting) was missing or incorrect.")

    is_passed = score >= 65

    return {
        "passed": is_passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }