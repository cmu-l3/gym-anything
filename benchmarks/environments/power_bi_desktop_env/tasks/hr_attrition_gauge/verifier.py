#!/usr/bin/env python3
"""
Verifier for hr_attrition_gauge task.

Criteria:
1. File Saved & Recent (15 pts): .pbix exists and modified during task.
2. Page Name (10 pts): Page renamed to "Attrition Overview".
3. Visuals (35 pts): 2 Gauges (20pts) and 1 Treemap (15pts).
4. Data Model (40 pts): "Attrition_Rate", "Avg_Monthly_Income", "Tenure_Band" exist.

Pass Threshold: 65 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hr_attrition_gauge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Error: copy_from_env not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/hr_attrition_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence and Timestamp (15 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 15
        feedback.append("✅ Report file saved and modified during task.")
    elif result.get('file_exists'):
        score += 5
        feedback.append("⚠️ Report file exists but timestamp check failed (might be old file).")
    else:
        feedback.append("❌ Report file 'HR_Attrition_Report.pbix' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Page Name (10 pts)
    # Check if any page name contains "Attrition Overview" (case insensitive)
    page_names = [p.lower() for p in result.get('page_names', [])]
    if any("attrition overview" in p for p in page_names):
        score += 10
        feedback.append("✅ Page renamed to 'Attrition Overview'.")
    else:
        feedback.append(f"❌ Page 'Attrition Overview' not found. Pages found: {result.get('page_names')}.")

    # 3. Visuals (35 pts)
    visuals = [v.lower() for v in result.get('visual_types', [])]
    gauge_count = sum(1 for v in visuals if 'gauge' in v)
    treemap_count = sum(1 for v in visuals if 'treemap' in v)

    # Check Gauges (20 pts)
    if gauge_count >= 2:
        score += 20
        feedback.append(f"✅ Found {gauge_count} Gauge visuals.")
    elif gauge_count == 1:
        score += 10
        feedback.append("⚠️ Found only 1 Gauge visual (expected 2).")
    else:
        feedback.append("❌ No Gauge visuals found.")

    # Check Treemap (15 pts)
    if treemap_count >= 1:
        score += 15
        feedback.append(f"✅ Found {treemap_count} Treemap visual.")
    else:
        feedback.append("❌ No Treemap visual found.")

    # 4. Data Model Terms (40 pts)
    found_terms = result.get('model_terms_found', [])
    required_terms = ["Attrition_Rate", "Avg_Monthly_Income", "Tenure_Band"]
    
    model_score = 0
    missing_terms = []
    
    # Weight breakdown: Measures 15pts each, Column 10pts
    if "Attrition_Rate" in found_terms:
        model_score += 15
    else:
        missing_terms.append("Attrition_Rate")

    if "Avg_Monthly_Income" in found_terms:
        model_score += 15
    else:
        missing_terms.append("Avg_Monthly_Income")

    if "Tenure_Band" in found_terms:
        model_score += 10
    else:
        missing_terms.append("Tenure_Band")
        
    score += model_score
    if not missing_terms:
        feedback.append("✅ All DAX measures and columns found in data model.")
    else:
        feedback.append(f"❌ Missing data model objects: {', '.join(missing_terms)}.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }