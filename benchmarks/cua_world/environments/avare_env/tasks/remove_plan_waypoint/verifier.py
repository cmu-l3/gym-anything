#!/usr/bin/env python3
"""
Verifier for remove_plan_waypoint task.

Criteria:
1. KSCK must NOT be in the plan (30 pts)
2. KOAK, KMOD, KFAT MUST be in the plan (25 pts)
3. Correct order KOAK -> KMOD -> KFAT (15 pts)
4. Visual verification via VLM (Plan list or Map route) (30 pts)
"""

import json
import os
import re
import logging
import tempfile
from typing import Dict, Any

# Gym-anything provided utilities
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_plan_waypoint(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_remove = metadata.get('target_to_remove', 'KSCK')
    required_waypoints = metadata.get('required_waypoints', ['KOAK', 'KMOD', 'KFAT'])
    
    score = 0
    feedback_parts = []
    
    # Temporary files for artifacts
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        # 1. UI Hierarchy Verification (Primary Programmatic Check)
        # -------------------------------------------------------
        has_xml = False
        try:
            copy_from_env("/sdcard/window_dump.xml", temp_xml.name)
            with open(temp_xml.name, 'r', encoding='utf-8', errors='ignore') as f:
                ui_content = f.read()
            has_xml = True
        except Exception as e:
            logger.warning(f"Failed to retrieve UI dump: {e}")
            ui_content = ""

        # Analyze UI Text
        if has_xml:
            # Check for absence of KSCK
            if target_remove in ui_content:
                feedback_parts.append(f"❌ '{target_remove}' still found in UI text.")
            else:
                score += 30
                feedback_parts.append(f"✅ '{target_remove}' successfully removed from view.")

            # Check for presence of required waypoints
            missing = [wp for wp in required_waypoints if wp not in ui_content]
            if missing:
                feedback_parts.append(f"❌ Missing required waypoints: {', '.join(missing)}")
            else:
                score += 25
                feedback_parts.append("✅ All required waypoints (KOAK, KMOD, KFAT) present.")
                
            # Note: Strict order check is hard with just raw XML dump without parsing hierarchy, 
            # so we rely on VLM for strict order verification.
        else:
            feedback_parts.append("⚠️ Could not verify text (UI dump missing). Relying on VLM.")

        # 2. VLM Verification (Visual & Order Check)
        # ----------------------------------------
        # We look at the final screenshot AND trajectory to ensure the plan was edited.
        
        final_img = get_final_screenshot(traj)
        frames = sample_trajectory_frames(traj, n=4)
        
        if final_img:
            vlm_prompt = f"""
            The user is modifying a flight plan in the Avare aviation app.
            
            Original Plan: KOAK -> KSCK -> KMOD -> KFAT.
            Goal: Remove 'KSCK' (Stockton) so the route is KOAK -> KMOD -> KFAT.
            
            Analyze the final screenshot and the workflow:
            1. Does the final view show a flight plan list OR a map with a route line?
            2. If it's a LIST: Does 'KSCK' appear in the list? Are KOAK, KMOD, KFAT listed in that order?
            3. If it's a MAP: Does the route line go straight from Oakland area to Modesto area (skipping Stockton)?
            4. Did the user navigate to the 'Plan' screen during the task?
            
            Output strictly JSON:
            {{
                "ksck_visible": boolean,
                "required_waypoints_visible": boolean,
                "route_looks_correct": boolean,
                "plan_screen_visited": boolean,
                "reasoning": "string"
            }}
            """
            
            # Combine frames for context (to see if they visited Plan screen)
            images_to_check = frames + [final_img]
            
            vlm_result = query_vlm(
                prompt=vlm_prompt,
                images=images_to_check
            )
            
            if vlm_result and vlm_result.get('success'):
                res = vlm_result.get('parsed', {})
                
                # Score VLM components
                if not res.get('ksck_visible', True):
                    # If XML check failed/was missing, give points here
                    if not has_xml: 
                        score += 30
                    feedback_parts.append("✅ VLM confirms KSCK is not visible.")
                else:
                    if not has_xml:
                        feedback_parts.append("❌ VLM sees KSCK in the view.")

                if res.get('required_waypoints_visible', False):
                    # If XML check failed/was missing, give points here
                    if not has_xml:
                        score += 25
                    feedback_parts.append("✅ VLM confirms required waypoints visible.")
                
                if res.get('route_looks_correct', False):
                    score += 15
                    feedback_parts.append("✅ VLM confirms route geometry looks correct.")
                else:
                    feedback_parts.append("❌ VLM indicates route geometry might be wrong.")
                    
                if res.get('plan_screen_visited', False):
                    score += 30
                    feedback_parts.append("✅ VLM confirms 'Plan' screen was visited.")
                else:
                    feedback_parts.append("⚠️ VLM could not confirm 'Plan' screen access.")
            else:
                feedback_parts.append("⚠️ VLM analysis failed.")
        else:
            feedback_parts.append("❌ No screenshots available.")

        # Final Score Calculation
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)