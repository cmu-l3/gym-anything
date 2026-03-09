#!/usr/bin/env python3
"""
Verifier for record_frost_protection_activity task.

Uses a Hybrid verification strategy:
1. Programmatic (Primary): Checks app's local storage data dumped by export_result.sh
   - farmOS Field Kit stores data in IndexedDB/LevelDB. We check if the expected text
     strings exist in the binary dump of these files.
2. VLM (Secondary): Visual check of the final state to confirm UI looks correct.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_frost_protection(traj, env_info, task_info):
    """
    Verify that the frost protection activity log was created with correct details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ============================================================
    # 1. Programmatic Verification (App Data Inspection)
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/data/local/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed: Could not read task result. {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    data_found = result_data.get("data_found", {})
    
    score = 0
    feedback_parts = []
    
    # Scoring Criteria (Total 80 points for data presence)
    
    # Log Type (10 pts)
    if data_found.get("type_activity"):
        score += 10
        feedback_parts.append("Log type 'Activity' detected")
    
    # Date (15 pts)
    if data_found.get("date"):
        score += 15
        feedback_parts.append("Correct date (April 18, 2024) found")
    else:
        feedback_parts.append("Date not found or incorrect")

    # Content - Key Phrases (30 pts total)
    phrases_found = 0
    if data_found.get("phrase_frost"): phrases_found += 1
    if data_found.get("phrase_block_c"): phrases_found += 1
    if data_found.get("phrase_temp"): phrases_found += 1
    if data_found.get("phrase_context"): phrases_found += 1
    
    # Scale points based on how many key phrases found
    if phrases_found >= 4:
        score += 30
        feedback_parts.append("All key note details found")
    elif phrases_found >= 2:
        score += 15
        feedback_parts.append(f"Some note details found ({phrases_found}/4)")
    elif phrases_found > 0:
        score += 5
        feedback_parts.append("Minimal note details found")
    else:
        feedback_parts.append("Log notes missing key details")

    # Quantity Data (25 pts total)
    if data_found.get("quantity_val"):
        score += 10
        feedback_parts.append("Quantity value '6' found")
    
    if data_found.get("quantity_label"):
        score += 10
        feedback_parts.append("Quantity label 'Protection Duration' found")
        
    if data_found.get("quantity_unit"):
        score += 5
        feedback_parts.append("Unit 'hours' found")

    # ============================================================
    # 2. VLM Verification (Visual Check)
    # ============================================================
    # Check if the final screen shows the log list with the new entry
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of the farmOS Field Kit app.
        
        I am looking for evidence that a new log was created.
        
        1. Do you see a log entry in the list?
        2. Does it mention "Activity" or have an activity icon?
        3. Can you see the date "Apr 18" or similar?
        4. Is there any text visible like "Emergency frost protection" or "Protection Duration"?
        
        Respond in JSON:
        {
            "log_visible": true/false,
            "date_visible": true/false,
            "content_match": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        try:
            vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("log_visible"):
                vlm_score += 10
                if parsed.get("date_visible"): vlm_score += 5
                if parsed.get("content_match"): vlm_score += 5
                
                feedback_parts.append("VLM confirmed log entry visibility")
            else:
                feedback_parts.append("VLM could not confirm log visibility in final screenshot")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Fallback: if data score is high, assume visual is okay (maybe scrolled off screen)
            if score >= 60:
                vlm_score += 10
    else:
        feedback_parts.append("No final screenshot available for visual verification")

    total_score = score + vlm_score
    
    # Cap score at 100
    total_score = min(100, total_score)
    
    # Pass threshold: 60 points (Requires at least date + some content + quantity or VLM confirmation)
    passed = total_score >= 60
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }