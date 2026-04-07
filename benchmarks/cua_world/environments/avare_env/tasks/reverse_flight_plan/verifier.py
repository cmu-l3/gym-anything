#!/usr/bin/env python3
"""
Verifier for reverse_flight_plan task.
Verifies that the agent created a specific route and then reversed it.
"""

import os
import json
import logging
import tempfile
import re
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reverse_flight_plan(traj, env_info, task_info):
    """
    Verify the flight plan was reversed correctly.
    
    Strategy:
    1. UI Dump Analysis (Primary): Parse /sdcard/ui_dump.xml to find the list of waypoints.
       We expect to see KRNO, then KSMF, then KSJC in that vertical order.
    2. VLM Verification (Secondary): Look at screenshots to confirm the 'Reverse' action
       was likely used (efficiency) and the final state is correct.
    """
    
    # 1. Setup and copy files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_dir = tempfile.mkdtemp()
    ui_dump_path = os.path.join(temp_dir, "ui_dump.xml")
    final_img_path = os.path.join(temp_dir, "task_final.png")
    
    has_dump = False
    try:
        copy_from_env("/sdcard/ui_dump.xml", ui_dump_path)
        has_dump = os.path.exists(ui_dump_path) and os.path.getsize(ui_dump_path) > 0
    except Exception as e:
        logger.warning(f"Failed to copy UI dump: {e}")

    # 2. Programmatic Verification via UI Dump
    ui_score = 0
    ui_feedback = []
    
    waypoints_found = []
    
    if has_dump:
        try:
            tree = ET.parse(ui_dump_path)
            root = tree.getroot()
            
            # Find all nodes with text matching our airports
            # We want to find them in the list view, usually resource-id contains "list" or just by text
            # We track their Y-coordinates to determine order (top to bottom)
            
            targets = ["KRNO", "KSMF", "KSJC"]
            found_nodes = []
            
            for node in root.iter():
                text = node.attrib.get('text', '')
                if text in targets:
                    # Get bounds "[x1,y1][x2,y2]"
                    bounds = node.attrib.get('bounds', '')
                    match = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                    if match:
                        y1 = int(match.group(2))
                        found_nodes.append({'text': text, 'y': y1})
            
            # Sort by Y position (Top of screen is 0, so lower Y comes first)
            found_nodes.sort(key=lambda x: x['y'])
            waypoints_found = [n['text'] for n in found_nodes]
            
            # Remove duplicates (sometimes text appears twice in UI trees)
            # Keep order
            seen = set()
            clean_waypoints = []
            for wp in waypoints_found:
                if wp not in seen:
                    clean_waypoints.append(wp)
                    seen.add(wp)
            waypoints_found = clean_waypoints
            
            logger.info(f"UI Dump found waypoints (ordered): {waypoints_found}")
            
            # Check Order: KRNO -> KSMF -> KSJC
            if waypoints_found == ["KRNO", "KSMF", "KSJC"]:
                ui_score = 100
                ui_feedback.append("Programmatic Verify: Correct reversed order found in UI list (KRNO -> KSMF -> KSJC).")
            elif waypoints_found == ["KSJC", "KSMF", "KRNO"]:
                ui_score = 20
                ui_feedback.append("Programmatic Verify: Found OUTBOUND route (KSJC->KRNO). Did not reverse.")
            else:
                # Check for partials
                if "KRNO" in waypoints_found and "KSJC" in waypoints_found:
                    if waypoints_found.index("KRNO") < waypoints_found.index("KSJC"):
                        ui_score = 60
                        ui_feedback.append("Programmatic Verify: KRNO appears before KSJC, but intermediate waypoints might be missing or wrong.")
                    else:
                        ui_score = 0
                        ui_feedback.append("Programmatic Verify: KSJC appears before KRNO (Wrong direction).")
                else:
                    ui_score = 0
                    ui_feedback.append(f"Programmatic Verify: Could not find all required waypoints. Found: {waypoints_found}")

        except Exception as e:
            logger.error(f"Error parsing XML: {e}")
            ui_feedback.append("Error parsing UI dump.")
    else:
        ui_feedback.append("No UI dump available for programmatic check.")

    # 3. VLM Verification (Robust Fallback & Process Check)
    # We want to verify the agent actually used the menu/workflow, not just manually typed things
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent using an aviation app. 
    The goal is to create a flight plan (KSJC -> KSMF -> KRNO) and then REVERSE it.
    
    Please analyze the screenshots:
    1. Do you see a flight plan list with airports KSJC, KSMF, KRNO?
    2. In the FINAL screenshot, is the order KRNO (top) -> KSMF -> KSJC (bottom)?
    3. Do you see any evidence of the 'Reverse' or 'Invert' menu option being selected in the trajectory?
    
    Return JSON:
    {
      "plan_created": true,
      "reverse_menu_used": true,
      "final_order_correct": true,
      "final_top_waypoint": "text",
      "final_bottom_waypoint": "text"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    vlm_score = 0
    if vlm_data.get('final_order_correct'):
        vlm_score += 50
    if vlm_data.get('reverse_menu_used'):
        vlm_score += 30
    if vlm_data.get('plan_created'):
        vlm_score += 20
        
    # 4. Final Scoring Fusion
    # If UI dump was perfect, we trust it highly. If not, we rely on VLM.
    
    final_score = 0
    passed = False
    feedback = ""
    
    if ui_score == 100:
        final_score = 100
        passed = True
        feedback = "Success! " + " ".join(ui_feedback)
    elif vlm_score >= 80:
        final_score = vlm_score
        passed = True
        feedback = "Success (Verified by Vision). Agent reversed the plan correctly."
    elif ui_score > 0:
        final_score = ui_score
        passed = False
        feedback = "Partial success. " + " ".join(ui_feedback)
    else:
        final_score = vlm_score
        passed = False
        feedback = "Failed. " + " ".join(ui_feedback) + f" VLM feedback: {vlm_data}"

    # Cleanup
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback
    }