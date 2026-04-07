#!/usr/bin/env python3
"""
Verifier for update_procedure_pricing task.

Checks:
1. Programmatic: Was CPT 99213 updated to 175.00? (30 points)
2. Programmatic: Was CPT 99214 updated to 240.00? (30 points)
3. Programmatic: Did the agent avoid creating duplicate CPT entries? (20 points)
4. VLM: Did the trajectory show proper use of the FreeMED UI? (20 points)
"""

import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_price(price_str):
    """Safely parse price strings from database like '175.00' or '$175.00'."""
    try:
        # Strip out any characters that aren't digits or decimal points
        clean_str = re.sub(r'[^\d.]', '', str(price_str))
        if clean_str == '':
            return 0.0
        return float(clean_str)
    except Exception:
        return 0.0

def build_vlm_prompt():
    return """Examine these trajectory frames from a web browser showing a medical EMR (FreeMED).

Task Check: Verify if the user successfully navigated through the user interface to edit procedure/billing pricing codes (CPT).

Look for these indicators across the frames:
1. Did the user search for or list procedure codes, CPT codes, or billing items?
2. Did the user open an "Edit" screen or form specifically for these procedure codes (e.g., 99213, 99214)?
3. Did the user interact with the FreeMED web interface to do this (as opposed to opening a terminal and running raw SQL)?

Respond in pure JSON format:
{
    "used_freemed_ui": true/false,
    "navigated_to_procedures": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is seen in the frames"
}
"""

def verify_update_procedure_pricing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_99213 = float(metadata.get('expected_99213_price', 175.00))
    expected_99214 = float(metadata.get('expected_99214_price', 240.00))
    
    # 1. Retrieve the JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/update_procedure_pricing_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    initial_count = int(result.get('initial_cpt_count', 0))
    current_count = int(result.get('current_cpt_count', 0))
    price_99213 = parse_price(result.get('price_99213', '0'))
    price_99214 = parse_price(result.get('price_99214', '0'))
    
    score = 0
    feedback_parts = []
    
    # Anti-gaming: Do Nothing Check
    if price_99213 == 110.0 and price_99214 == 160.0:
        return {"passed": False, "score": 0, "feedback": "No prices were updated (both are still original values)."}
    
    # 2. Score CPT 99213 (30 points)
    if abs(price_99213 - expected_99213) < 0.01:
        score += 30
        feedback_parts.append(f"CPT 99213 price correctly updated to {price_99213}")
    else:
        feedback_parts.append(f"CPT 99213 price incorrect: expected {expected_99213}, got {price_99213}")

    # 3. Score CPT 99214 (30 points)
    if abs(price_99214 - expected_99214) < 0.01:
        score += 30
        feedback_parts.append(f"CPT 99214 price correctly updated to {price_99214}")
    else:
        feedback_parts.append(f"CPT 99214 price incorrect: expected {expected_99214}, got {price_99214}")

    # 4. Duplicate Check (20 points)
    if current_count <= initial_count:
        score += 20
        feedback_parts.append(f"No duplicates created (count: {initial_count} -> {current_count})")
    else:
        diff = current_count - initial_count
        feedback_parts.append(f"FAIL: {diff} duplicate CPT records were created instead of editing existing ones")
        
    # 5. VLM Trajectory Verification (20 points)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames:
                vlm_res = query_vlm(prompt=build_vlm_prompt(), images=frames)
                if vlm_res.get("success"):
                    vlm_parsed = vlm_res.get("parsed", {})
                    used_ui = vlm_parsed.get("used_freemed_ui", False)
                    navigated = vlm_parsed.get("navigated_to_procedures", False)
                    
                    if used_ui and navigated:
                        vlm_score = 20
                        feedback_parts.append("VLM verified: UI trajectory matches expected procedure editing workflow")
                    else:
                        feedback_parts.append("VLM noted that FreeMED procedure editing UI was not clearly used")
                else:
                    feedback_parts.append("VLM query failed, skipping visual verification")
            else:
                feedback_parts.append("No trajectory frames available for VLM")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM verification error: {str(e)[:50]}")
    else:
        # If VLM is totally unavailable in framework, grant points gracefully if DB states are perfect
        if score == 80:
            vlm_score = 20
            feedback_parts.append("VLM disabled; full programmatic score achieved")
            
    score += vlm_score
    
    passed = score >= 80  # Requires perfect DB execution (30+30+20) to pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }