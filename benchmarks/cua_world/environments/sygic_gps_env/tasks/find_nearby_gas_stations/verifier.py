#!/usr/bin/env python3
"""
Verifier for find_nearby_gas_stations task.

Verification Strategy:
1. XML Analysis: Check for gas station keywords and detail view indicators in UI dump.
2. Activity Check: Ensure Sygic is the focused app.
3. VLM Verification: Confirm the visual state shows a gas station detail view.
4. Anti-Gaming: Ensure task took reasonable time (>5s).
"""

import json
import os
import time
import logging
import tempfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_find_nearby_gas_stations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata keywords
    metadata = task_info.get('metadata', {})
    target_keywords = metadata.get('target_keywords', ["Gas", "Fuel", "Shell", "Chevron"])
    detail_indicators = metadata.get('detail_indicators', ["Navigate", "Address", "mi", "km"])

    score = 0
    feedback_parts = []
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        # ---------------------------------------------------------
        # 1. Load Basic Result JSON
        # ---------------------------------------------------------
        local_result_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/task_verification/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}

        # ---------------------------------------------------------
        # 2. Check Anti-Gaming (Time)
        # ---------------------------------------------------------
        start_time = int(result_data.get("task_start", 0))
        end_time = int(result_data.get("task_end", 0))
        duration = end_time - start_time
        
        if duration < 5:
            return {"passed": False, "score": 0, "feedback": "Task completed too quickly (impossible speed)."}
        
        # ---------------------------------------------------------
        # 3. Check App Running (10 pts)
        # ---------------------------------------------------------
        if result_data.get("app_running", False):
            score += 10
            feedback_parts.append("App is running (+10)")
        else:
            feedback_parts.append("App was closed")

        # ---------------------------------------------------------
        # 4. Analyze UI Hierarchy XML (40 pts)
        # ---------------------------------------------------------
        local_xml = os.path.join(temp_dir, "ui_dump.xml")
        xml_score = 0
        gas_keyword_found = False
        detail_indicator_found = False
        
        try:
            copy_from_env("/sdcard/task_verification/ui_dump.xml", local_xml)
            if os.path.getsize(local_xml) > 0:
                with open(local_xml, 'r', encoding='utf-8', errors='ignore') as f:
                    xml_content = f.read()
                    
                # Search for gas station names
                for kw in target_keywords:
                    if kw.lower() in xml_content.lower():
                        gas_keyword_found = True
                        break
                
                # Search for detail indicators (distance, navigate button)
                for ind in detail_indicators:
                    if ind in xml_content: # Case sensitive for 'mi'/'km' usually better
                        detail_indicator_found = True
                        break
                
                if gas_keyword_found:
                    xml_score += 20
                    feedback_parts.append("Gas station name found in UI (+20)")
                
                if detail_indicator_found:
                    xml_score += 20
                    feedback_parts.append("Detail view indicators found (+20)")
                    
                score += xml_score
            else:
                feedback_parts.append("UI dump empty")
        except Exception as e:
            feedback_parts.append(f"UI analysis failed: {str(e)}")

        # ---------------------------------------------------------
        # 5. VLM Verification (50 pts)
        # ---------------------------------------------------------
        # We use trajectory frames to ensure they actually browsed/searched
        # and the final screenshot to confirm the specific detail view.
        
        final_screenshot = get_final_screenshot(traj)
        trajectory_frames = sample_trajectory_frames(traj, n=3)
        
        vlm_prompt = """
        You are verifying an Android navigation task. 
        The goal is: "Find nearby gas stations via category browse and select one to view details."

        Review the screenshots (trajectory and final state):
        1. Did the user open a search or category menu?
        2. Is a list of gas stations or a specific gas station detail view visible in the FINAL screenshot?
        3. Does the screen show details like an address, distance, or 'Navigate' button for a fuel station?

        Respond in JSON:
        {
            "category_or_search_accessed": boolean,
            "gas_station_visible": boolean,
            "detail_view_confirmed": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_score = 0
        try:
            # Combine frames: last 3 steps + final state
            images_to_check = trajectory_frames + [final_screenshot]
            
            vlm_result = query_vlm(
                prompt=vlm_prompt,
                images=images_to_check
            )
            
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("gas_station_visible", False):
                vlm_score += 20
                feedback_parts.append("VLM confirms gas station visible (+20)")
                
            if parsed.get("detail_view_confirmed", False):
                vlm_score += 30
                feedback_parts.append("VLM confirms detail view (+30)")
                
            score += vlm_score
            
        except Exception as e:
            feedback_parts.append(f"VLM verification failed: {str(e)}")
            # Fallback: if XML found everything, we might still pass, but score is lower
            
        # ---------------------------------------------------------
        # Final Scoring
        # ---------------------------------------------------------
        passed = score >= 60 and (gas_keyword_found or (vlm_score >= 20))
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback_parts)
        }