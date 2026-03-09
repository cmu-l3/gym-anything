#!/usr/bin/env python3
"""
Verifier for Inventory Aging Report (inventory_aging_report@1).
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback if gym_anything not available in local test
    query_vlm = None
    get_final_screenshot = lambda x: None
    sample_trajectory_frames = lambda x, n: []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_aging(traj, env_info, task_info):
    """
    Verify the Power BI Inventory Aging task.
    
    Criteria:
    1. File Existence & Timestamp (10 pts)
    2. Data Model Elements (45 pts): Total_Value, Days_In_Stock, Aging_Bucket
    3. Visual Elements (25 pts): Matrix, Donut
    4. VLM Verification (20 pts): Visual confirmation of Matrix structure and buckets
    """
    
    # 1. Setup & Read JSON Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # PBI environment uses Windows paths in the VM, but we copy from the mount or via dockur/windows logic
        # The export script saved to C:\Users\Docker\Desktop\inventory_aging_result.json
        # In this env, that maps usually to the Desktop path.
        copy_from_env("C:/Users/Docker/Desktop/inventory_aging_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification results from VM"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (80 pts max)
    
    # File Checks (10 pts)
    if result.get("file_exists") and result.get("file_valid_time"):
        score += 10
        feedback_parts.append("File saved correctly")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("File exists but timestamp is suspicious")
    else:
        feedback_parts.append("File 'Inventory_Aging.pbix' not found")
        
    # Data Model Checks (45 pts)
    # Total_Value (15)
    if result.get("has_total_value"):
        score += 15
        feedback_parts.append("Measure 'Total_Value' found")
    else:
        feedback_parts.append("Missing 'Total_Value' calculation")
        
    # Days_In_Stock (15)
    if result.get("has_days_column"):
        score += 15
        feedback_parts.append("Column 'Days_In_Stock' found")
    else:
        feedback_parts.append("Missing 'Days_In_Stock' calculation")
        
    # Aging_Bucket (15)
    if result.get("has_bucket_column"):
        score += 15
        feedback_parts.append("Column 'Aging_Bucket' found")
    else:
        feedback_parts.append("Missing 'Aging_Bucket' grouping")

    # Visual Checks (25 pts)
    # Matrix (15)
    if result.get("has_matrix_visual"):
        score += 15
        feedback_parts.append("Matrix visual present")
    else:
        feedback_parts.append("Matrix visual missing")
        
    # Donut (10)
    if result.get("has_donut_visual"):
        score += 10
        feedback_parts.append("Donut chart present")
    else:
        feedback_parts.append("Donut chart missing")

    # 3. VLM Verification (20 pts)
    # Using trajectory to check if they actually built it
    vlm_score = 0
    if query_vlm:
        final_screen = get_final_screenshot(traj)
        frames = sample_trajectory_frames(traj, n=3)
        
        prompt = """
        Review these screenshots of a Power BI task.
        The user should have built an 'Inventory Aging Report'.
        
        Check for:
        1. A Matrix or Table visual showing categories (rows) and age buckets like '0-90 Days' (columns).
        2. A Donut or Pie chart.
        3. The text '0-90 Days', '> 1 Year', or similar aging buckets visible in the report.
        
        Return JSON: {"matrix_visible": bool, "donut_visible": bool, "buckets_text_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("matrix_visible"): vlm_score += 5
                if parsed.get("donut_visible"): vlm_score += 5
                if parsed.get("buckets_text_visible"): vlm_score += 10
                
                if vlm_score == 20:
                    feedback_parts.append("VLM confirmed all visuals")
                elif vlm_score > 0:
                    feedback_parts.append(f"VLM confirmed partial visuals ({vlm_score}pts)")
            else:
                # If VLM fails, we fallback to trusting the file check slightly more or just 0
                feedback_parts.append("VLM verification failed to run")
        except Exception as e:
            logger.warning(f"VLM Error: {e}")
            
    score += vlm_score
    
    # 4. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }