#!/usr/bin/env python3
"""
Verifier for Image Alt Text Audit task.

Scoring Breakdown (100 pts total):
1. CSV Export (40 pts):
   - File exists and created during task (15)
   - Contains image-specific columns (15)
   - Contains data for target domain (10)

2. Audit Report (60 pts):
   - File exists (10)
   - Sufficient length > 500 chars (10)
   - Contains numeric counts (15)
   - Contains 'recommendation' section (15)
   - References target site URL (10)

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_image_alt_text_audit(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 3. Evaluate CSV Export (40 pts)
    csv_data = result.get("csv", {})
    
    if csv_data.get("exists"):
        score += 15
        feedback.append("Image CSV export found (+15)")
        
        if csv_data.get("has_image_columns"):
            score += 15
            feedback.append("CSV contains image data columns (+15)")
        else:
            feedback.append("CSV lacks image-specific columns (e.g. Alt Text)")
            
        if csv_data.get("has_target_domain") and csv_data.get("has_data"):
            score += 10
            feedback.append(f"CSV contains {csv_data.get('row_count')} rows for target domain (+10)")
        else:
            feedback.append("CSV is empty or misses target domain data")
    else:
        feedback.append("No valid image CSV export found matching pattern '*image*.csv'")

    # 4. Evaluate Audit Report (60 pts)
    report_data = result.get("report", {})
    
    if report_data.get("exists"):
        score += 10
        feedback.append("Report file found (+10)")
        
        length = report_data.get("length", 0)
        if length >= 500:
            score += 10
            feedback.append(f"Report length sufficient ({length} chars) (+10)")
        else:
            feedback.append(f"Report too short ({length}/500 chars)")
            
        if report_data.get("has_numbers"):
            score += 15
            feedback.append("Report includes data counts (+15)")
        else:
            feedback.append("Report missing numeric counts")
            
        if report_data.get("has_recommendation"):
            score += 15
            feedback.append("Report includes recommendations (+15)")
        else:
            feedback.append("Report missing 'recommendation' keyword")
            
        if report_data.get("has_url"):
            score += 10
            feedback.append("Report references target website (+10)")
        else:
            feedback.append("Report does not verify specific URLs")
    else:
        feedback.append("Audit report file not found")

    # 5. Finalize
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }