#!/usr/bin/env python3
"""
Verifier for Freight Transport Project task.

This task requires using the specific "Project" feature in OpenLCA to compare
Truck vs Rail transport.

Scoring Breakdown (100 pts total):
1. Database & Process Setup (30 pts)
   - DB Imported (>10MB/Processes exist): 10 pts
   - At least 2 Product Systems created: 20 pts
2. Project Creation (25 pts)
   - TBL_PROJECTS count >= 1: 25 pts (CRITICAL: Proves "Project" feature was used)
3. Result Export (25 pts)
   - File exists & created during task: 5 pts
   - Contains keywords (truck, rail): 10 pts
   - Contains impact data (GWP, numbers): 10 pts
4. VLM Verification (20 pts)
   - Trajectory shows Project editor usage
   - Final state shows comparison results

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompts
TRAJECTORY_PROMPT = """You are analyzing an agent's workflow in OpenLCA.
The goal is to create a 'Project' to compare two transport modes (Truck vs Rail).

Look for these specific screens:
1. Database Import: Importing a zip file.
2. Product System Creation: Creating systems for 'Truck' and 'Rail'.
3. **Project Editor**: A specific tab in OpenLCA usually labeled 'Project: [Name]'. It has sections for 'Variants' (where you add product systems) and 'LCIA Method'.
4. Comparison Report: A chart or table showing side-by-side bars for different impact categories.

Assess:
- Did the agent create Product Systems?
- Did the agent open the 'Project' editor (Critical)?
- Did the agent add variants to the project?
- Did the agent run the project comparison report?

Return JSON:
{
  "product_systems_created": true/false,
  "project_editor_used": true/false,
  "variants_added": true/false,
  "comparison_report_seen": true/false,
  "confidence": "low/medium/high"
}"""

FINAL_STATE_PROMPT = """Analyze the final screenshot of the OpenLCA task.
Expected: A CSV file open showing comparison data OR the OpenLCA Project Report view.

Check for:
- Keywords: 'Truck', 'Rail', 'Train', 'Global Warming', 'Acidification'.
- Data: Side-by-side numeric comparisons.
- Application: OpenLCA showing a 'Report' tab or a Spreadsheet showing the CSV.

Return JSON:
{
  "comparison_data_visible": true/false,
  "truck_rail_references": true/false,
  "numeric_values_visible": true/false,
  "task_completed": true/false
}"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm: return None
    try:
        res = query_vlm(prompt=prompt, image=image, images=images)
        if res and res.get('success'): return res.get('parsed', {})
    except: pass
    return None

def verify_freight_transport_project(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name): os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Database Setup (10 pts)
    if result.get('db_imported') and int(result.get('process_count', 0)) > 50:
        score += 10
        feedback.append("Database imported successfully.")
    else:
        feedback.append("Database import failed or insufficient data.")

    # 2. Product Systems (20 pts)
    ps_count = int(result.get('product_system_count', 0))
    if ps_count >= 2:
        score += 20
        feedback.append(f"Created {ps_count} product systems (Truck & Rail).")
    elif ps_count == 1:
        score += 10
        feedback.append("Only 1 product system created (need 2).")
    else:
        feedback.append("No product systems created.")

    # 3. Project Creation (25 pts) - CRITICAL FEATURE CHECK
    project_count = int(result.get('project_count', 0))
    if project_count >= 1:
        score += 25
        feedback.append("OpenLCA 'Project' entity created.")
    else:
        feedback.append("Failed to create OpenLCA 'Project' entity. Did you just run separate calculations?")

    # 4. Result Export (25 pts)
    file_found = result.get('file_found')
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start_time', 0)
    keywords = result.get('keywords_found', "")
    
    if file_found and file_mtime > task_start:
        score += 5
        feedback.append("Result file exported.")
        
        # Parse keyword flags from string "truck:1,rail:1..."
        kw_map = {k.split(':')[0]: int(k.split(':')[1]) for k in keywords.split(',') if ':' in k}
        
        if kw_map.get('truck') and kw_map.get('rail'):
            score += 10
            feedback.append("File contains Truck and Rail keywords.")
        
        if kw_map.get('gwp') and kw_map.get('numbers'):
            score += 10
            feedback.append("File contains Impact Data (GWP/Numbers).")
    else:
        feedback.append("No valid result file exported.")

    # 5. VLM Verification (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Check trajectory for Project Editor usage
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, 4)
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if traj_res and traj_res.get('project_editor_used'):
            score += 15
            feedback.append("VLM confirmed usage of Project Editor.")
        elif traj_res and traj_res.get('product_systems_created'):
            score += 5
            feedback.append("VLM saw product systems but missed Project Editor.")
            
        # Check final state
        final_img = get_final_screenshot(traj)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
        if final_res and final_res.get('comparison_data_visible'):
            score += 5
            feedback.append("VLM confirmed final comparison data.")

    passed = score >= 60 and project_count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }