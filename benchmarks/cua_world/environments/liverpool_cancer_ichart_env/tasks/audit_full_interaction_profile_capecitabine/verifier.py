#!/usr/bin/env python3
"""
Verifier for Capecitabine Interaction Audit task.

Verification Strategy:
1. File Verification (40%):
   - Check if /sdcard/Download/capecitabine_audit.txt exists.
   - Verify it contains valid structure (categories, counts).
   - Check for internal consistency (sum of categories = total).

2. VLM Trajectory Verification (60%):
   - Verify the agent actually navigated through the app.
   - Look for Capecitabine selection.
   - Look for multiple category visits (systematic exploration).
"""

import json
import tempfile
import os
import logging
import re
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from vlm_utils import query_vlm, sample_trajectory_frames
except ImportError:
    # Mock for standalone testing if needed
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_capecitabine_audit(traj, env_info, task_info):
    """
    Verify the Capecitabine audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    result_data = {}
    report_content = ""
    
    try:
        # Get JSON result
        try:
            copy_from_env("/sdcard/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load result JSON: {e}")

        # Get Report Content
        try:
            copy_from_env("/sdcard/Download/capecitabine_audit.txt", temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to load report file: {e}")
            
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_report.name): os.unlink(temp_report.name)

    # 2. Evaluate File Content (40 points)
    file_score = 0
    feedback = []
    
    if result_data.get("output_exists"):
        file_score += 10
        feedback.append("Report file created.")
        
        # Parse content
        categories_found = re.findall(r'- (.*?): (\d+) co-medications', report_content)
        total_match = re.search(r'Total.*: (\d+)', report_content)
        
        if len(categories_found) >= 3:
            file_score += 10
            feedback.append(f"Found {len(categories_found)} categories in report.")
        else:
            feedback.append("Report lists too few categories (need at least 3).")
            
        if total_match:
            reported_total = int(total_match.group(1))
            calculated_total = sum(int(c[1]) for c in categories_found)
            
            if reported_total > 0:
                file_score += 10
                feedback.append("Total count present.")
                
            if abs(reported_total - calculated_total) < 2: # Allow small math error
                file_score += 10
                feedback.append("Total matches sum of categories.")
            else:
                feedback.append(f"Math mismatch: Listed total {reported_total} != sum {calculated_total}.")
        else:
            feedback.append("No total count found in report.")
    else:
        feedback.append("No report file found.")

    # 3. VLM Trajectory Verification (60 points)
    vlm_score = 0
    
    # Sample frames to check workflow
    frames = sample_trajectory_frames(traj, n=8)
    
    if not frames:
        feedback.append("No trajectory frames available for verification.")
    else:
        prompt = """
        You are auditing an agent's workflow in the 'Liverpool Cancer iChart' Android app.
        The agent's goal is to select 'Capecitabine' and check multiple co-medication categories.
        
        Look at these screenshots in order and determine:
        1. Did the agent navigate to the 'Capecitabine' page? (Look for header 'Capecitabine' or similar)
        2. Did the agent enter multiple different categories? (e.g. 'Analgesics', 'Antibiotics', etc. - look for list views with checkboxes or counts)
        3. Did the agent scroll or navigate back and forth (evidence of systematic checking)?
        
        Respond in JSON:
        {
            "capecitabine_visited": true/false,
            "multiple_categories_visited": true/false,
            "systematic_navigation": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, images=frames)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("capecitabine_visited"):
                vlm_score += 20
                feedback.append("VLM: Capecitabine page visited.")
            
            if parsed.get("multiple_categories_visited"):
                vlm_score += 20
                feedback.append("VLM: Multiple categories visited.")
                
            if parsed.get("systematic_navigation"):
                vlm_score += 20
                feedback.append("VLM: Systematic navigation observed.")
        else:
            feedback.append("VLM analysis failed.")

    # 4. Final Scoring
    total_score = file_score + vlm_score
    passed = total_score >= 55 and result_data.get("output_exists")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "file_score": file_score,
            "vlm_score": vlm_score,
            "report_length": len(report_content)
        }
    }