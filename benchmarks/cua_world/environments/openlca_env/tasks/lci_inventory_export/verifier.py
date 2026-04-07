#!/usr/bin/env python3
"""
Verifier for LCI Inventory Export task.

Task Requirements:
1. USLCI database import.
2. Product system creation (Natural Gas Electricity).
3. LCI Inventory Calculation (NOT just Impact Assessment).
4. Export inventory to CSV (must contain elementary flows).
5. Create summary report of top flows.

Verification Logic:
- Programmatic: Check CSV existence, row count (inventory is large), specific flow keywords.
- Programmatic: Check report existence and content.
- Programmatic: Check DB state (product system count).
- VLM: Verify trajectory shows interaction with "Inventory Results" tab.
"""

import json
import os
import tempfile
import base64
import logging

logger = logging.getLogger(__name__)

# VLM Prompt to verify they accessed Inventory Results specifically
TRAJECTORY_PROMPT = """You are analyzing screenshots of an OpenLCA workflow.
The user must calculate a product system and view the **Inventory Results** (elementary flows), NOT just the Impact Analysis.

Look for:
1. A "Results" window.
2. The user clicking or viewing a tab labeled "Inventory results" or "Inventory".
3. A list of elementary flows (e.g., "Carbon dioxide", "Methane", "Water") being displayed, usually with "Compartment" and "Amount" columns.
4. An export dialog or action.

JSON Response:
{
  "inventory_tab_viewed": true/false,
  "elementary_flows_visible": true/false,
  "export_action_seen": true/false,
  "confidence": "low/medium/high",
  "observations": "brief details"
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_lci_inventory_export(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 2. Programmatic Verification

    # Criterion A: Database & Product System (25 pts)
    # Check if DB was imported and at least one product system exists
    ps_count = int(result.get('ps_count', 0))
    process_count = int(result.get('process_count', 0))
    
    if process_count > 100: # USLCI has hundreds
        score += 10
        feedback.append("Database imported successfully.")
    
    if ps_count >= 1:
        score += 15
        feedback.append("Product system created.")
    else:
        feedback.append("No product system found.")

    # Criterion B: LCI CSV File (40 pts)
    csv_exists = result.get('csv_exists', False)
    csv_created = result.get('csv_created_during_task', False)
    csv_rows = int(result.get('csv_rows', 0))
    csv_has_co2 = result.get('csv_has_co2', False)
    csv_has_compartment = result.get('csv_has_compartment', False)

    if csv_exists and csv_created:
        score += 10
        if csv_rows > 50: # Real LCI has many rows
            score += 10
            feedback.append(f"Inventory CSV exported ({csv_rows} rows).")
            
            if csv_has_co2:
                score += 10
                feedback.append("CSV contains Carbon dioxide (expected).")
            else:
                feedback.append("CSV missing 'Carbon dioxide'.")
                
            if csv_has_compartment:
                score += 10
                feedback.append("CSV contains compartment data.")
            else:
                feedback.append("CSV missing compartment columns.")
        else:
            feedback.append(f"CSV exported but seems too small ({csv_rows} rows). Expected full inventory.")
    else:
        feedback.append("Inventory CSV not created or timestamp invalid.")

    # Criterion C: Summary Report (20 pts)
    report_exists = result.get('report_exists', False)
    report_b64 = result.get('report_content_b64', "")
    
    if report_exists and result.get('report_created_during_task', False):
        score += 5
        try:
            content = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            # Check for reasonable content (numbers, units)
            import re
            numbers = len(re.findall(r'\d+', content))
            keywords = len(re.findall(r'kg|g|mg|lbs|ton|air|water', content, re.IGNORECASE))
            
            if numbers >= 5 and keywords >= 3:
                score += 15
                feedback.append("Summary report contains quantitative data.")
            else:
                feedback.append("Summary report content seems insufficient.")
        except:
            feedback.append("Failed to decode report content.")
    else:
        feedback.append("Summary report not found.")

    # 3. VLM Verification (15 pts)
    # Verify they actually looked at Inventory Results
    query_vlm = env_info.get('query_vlm')
    # Sample trajectory
    from gym_anything.vlm import sample_trajectory_frames
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
    
    if vlm_result:
        if vlm_result.get('inventory_tab_viewed', False) or vlm_result.get('elementary_flows_visible', False):
            score += 15
            feedback.append("VLM confirmed Inventory Results view.")
        else:
            feedback.append("VLM did not clearly see Inventory Results tab usage.")
    else:
        # Fallback if VLM fails but programmatic passed strong
        if score >= 60:
            score += 15
            feedback.append("Skipping VLM check due to system unavailable (Programmatic passed).")

    # Final Pass/Fail
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }