#!/usr/bin/env python3
"""
Verifier for create_tag_cloud_dashboard task.

Verification Strategy:
1. File Verification (Anti-Gaming):
   - Check if 'Customer_Loyalty_Cloud.dva' exists.
   - Verify it was saved AFTER the task started.
   - Check file size > 0.

2. VLM Trajectory Verification (Process & Content):
   - Verify the agent created a Tag Cloud (text-based cloud, not bars/lines).
   - Verify Top 50 filter (cloud is not overly dense).
   - Verify 'Customer Segment' color encoding (multiple text colors).
   - Verify Dashboard Filter interaction (List Box for Year present).
   - Verify Title/Canvas naming.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_tag_cloud_dashboard(traj, env_info, task_info):
    """
    Verify the creation of a Tag Cloud dashboard with filters.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get Programmatic Results (File check)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # In Windows env, paths might be C:\tmp\... but copy_from_env usually handles standard linux-style paths 
        # or we might need to be careful. The export script saved to C:\tmp\task_result.json.
        # Docker/Container mapping usually exposes this as /tmp/task_result.json if using standard gym_anything wrappers,
        # OR we just request the path defined in export script.
        # Assuming standard mapping or direct path access:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        file_result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    feedback = []
    
    # 2. Score File Existence (Anti-Gaming) - 20 pts
    output_exists = file_result.get('output_exists', False)
    created_during = file_result.get('file_created_during_task', False)
    
    if output_exists:
        if created_during:
            score += 20
            feedback.append("Workbook saved successfully during task.")
        else:
            score += 5
            feedback.append("Workbook exists but timestamp indicates it wasn't modified during this session.")
    else:
        feedback.append("Workbook 'Customer_Loyalty_Cloud.dva' not found.")

    # 3. VLM Verification - 80 pts
    # We use trajectory frames to verify the workflow and final state
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}
        
    all_frames = frames + [final_frame]
    
    vlm_prompt = """
    You are evaluating an agent using Oracle Analytics Desktop.
    The goal was to create a "Tag Cloud" visualization of customers and add a dashboard filter for "Year".
    
    Please analyze the screenshots (chronological order) and the final screen to check:
    
    1. **Visualization Type**: Is there a Tag Cloud / Word Cloud visible? (Look for a cloud of names/text of different sizes).
    2. **Dashboard Filter**: Is there a list box or dropdown control separate from the chart, likely labeled "Order Date", "Year", or showing years like "2019", "2020"?
    3. **Content**: 
       - Do the words look like names (e.g., "John Smith")?
       - Are they colored differently (indicating segment coloring)?
       - Does the cloud look filtered (Top 50) rather than thousands of tiny illegible words?
    4. **Titles**: Can you see "VIP Customers" or "Loyalty Analysis" text?
    
    Provide a score breakdown in JSON:
    {
        "tag_cloud_visible": true/false,
        "dashboard_filter_visible": true/false,
        "color_encoding_visible": true/false,
        "title_correct": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_response = query_vlm(images=all_frames, prompt=vlm_prompt)
    
    if vlm_response and vlm_response.get('success'):
        parsed = vlm_response.get('parsed', {})
        
        # Tag Cloud Presence (30 pts)
        if parsed.get('tag_cloud_visible'):
            score += 30
            feedback.append("Tag Cloud visualization verified.")
        else:
            feedback.append("Tag Cloud visualization NOT detected.")
            
        # Interactive Filter (20 pts)
        if parsed.get('dashboard_filter_visible'):
            score += 20
            feedback.append("Dashboard filter/List box verified.")
        else:
            feedback.append("Dashboard filter (interactive control) NOT detected.")
            
        # Coloring (10 pts)
        if parsed.get('color_encoding_visible'):
            score += 10
            feedback.append("Color encoding (Segments) verified.")
            
        # Titles (10 pts)
        if parsed.get('title_correct'):
            score += 10
            feedback.append("Titles/Canvas name verified.")
            
    else:
        feedback.append("VLM verification failed to process images.")

    # Final Pass Check
    # Must have file + Tag Cloud + Filter to pass
    passed = (output_exists and created_during and 
              score >= 70 and 
              parsed.get('tag_cloud_visible') and 
              parsed.get('dashboard_filter_visible'))

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }