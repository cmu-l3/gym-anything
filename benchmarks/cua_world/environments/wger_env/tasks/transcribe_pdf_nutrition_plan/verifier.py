#!/usr/bin/env python3
"""
Verifier for Transcribe PDF Nutrition Plan task.

Verification Criteria:
1. "Nutritionist Protocol" Plan was created (10 pts)
2. Accurate transcription of all 7 items with precise quantities (10 pts per item = 70 pts)
3. VLM Verification: Agent actually opened/viewed the PDF during the trajectory (20 pts)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are evaluating a web automation agent. The agent was supposed to transcribe a PDF document into a fitness web application.

Look at these trajectory screenshots. Is there ANY visual evidence that the agent successfully opened or viewed a PDF file (likely named "nutrition_protocol.pdf") or a document titled "Daily Nutrition Protocol" during its execution?
It could have been opened in a separate PDF viewer window, or inside a Firefox browser tab (e.g. starting with file:///).

Return your response in JSON format with two keys:
1. "pdf_opened": true if you see the PDF document open in ANY of the frames, false otherwise.
2. "reasoning": A short explanation of what you see.
"""

def verify_transcribe_pdf_nutrition_plan(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Fetch expected metadata
    metadata = task_info.get('metadata', {})
    expected_items = metadata.get('expected_items', [])

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Programmatic DB Verification
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    plan_found = result.get('plan_found', False)
    meals = result.get('meals', [])

    if plan_found:
        score += 10
        feedback_parts.append("✅ Nutrition Plan 'Nutritionist Protocol' successfully created.")
        
        # Flatten all items in the plan to simplify checking (we care about exact items and amounts)
        actual_items = []
        for meal in meals:
            actual_items.extend(meal.get('items', []))
            
        items_matched = 0
        missing_items = []
        
        for expected in expected_items:
            expected_name = expected['name'].lower()
            expected_amount = expected['amount']
            
            # Find matching item in the transcribed plan
            match_found = False
            for actual in actual_items:
                actual_name = actual['ingredient_name'].lower()
                actual_amount = float(actual['amount'])
                
                # Check for close name match and exact amount (allow 1g tolerance for rounding)
                if expected_name in actual_name and abs(expected_amount - actual_amount) <= 1.0:
                    match_found = True
                    break
            
            if match_found:
                items_matched += 1
                score += 10
            else:
                missing_items.append(expected['name'])
                
        if items_matched == len(expected_items):
            feedback_parts.append(f"✅ All {len(expected_items)} ingredients were transcribed with perfect quantities.")
        elif items_matched > 0:
            feedback_parts.append(f"⚠️ Partially correct transcription: {items_matched}/{len(expected_items)} correct. Missing/Wrong: {', '.join(missing_items)}.")
        else:
            feedback_parts.append("❌ No correct ingredients or amounts found in the nutrition plan.")
            
    else:
        feedback_parts.append("❌ Target Nutrition Plan was never created.")

    # ---------------------------------------------------------
    # 2. VLM Trajectory Verification
    # ---------------------------------------------------------
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        final = get_final_screenshot(traj)
        
        images_to_check = frames
        if final not in images_to_check:
            images_to_check.append(final)
            
        try:
            vlm_response = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=images_to_check
            )
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("pdf_opened", False):
                    vlm_points = 20
                    score += 20
                    feedback_parts.append("✅ VLM confirmed the PDF document was opened and viewed.")
                else:
                    feedback_parts.append(f"⚠️ VLM did not see the PDF being opened. (Reasoning: {parsed.get('reasoning', 'None')})")
            else:
                feedback_parts.append("⚠️ VLM query failed, skipping trajectory verification.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("⚠️ VLM verification encountered an error.")
    else:
        feedback_parts.append("⚠️ VLM function not available, skipping trajectory check.")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # Threshold: 70 points (requires Plan Creation + majority of items accurate + ideally VLM confirmation)
    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }