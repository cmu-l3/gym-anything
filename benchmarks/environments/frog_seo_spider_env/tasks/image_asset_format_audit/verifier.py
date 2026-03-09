#!/usr/bin/env python3
"""
Verifier for Image Asset Format Audit task.

Scoring (100 points total):
1. Screaming Frog interaction (10 pts)
2. Valid CSV Export (40 pts)
   - Exists & created during task (10)
   - Contains Image data/extensions (10)
   - Contains target domain URLs (10)
   - Sufficient row count (>50) (10)
3. Strategic Report (50 pts)
   - Exists & created during task (10)
   - Contains counts/numbers (10)
   - Mentions file sizes/heaviest assets (15)
   - Contains optimization recommendations (15)

Pass threshold: 60 points (Must have at least basic CSV and Report)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_image_asset_format_audit(traj, env_info, task_info):
    """Verify the image asset audit task."""
    
    # 1. Setup & Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 2. Criterion: System Interaction (10 pts)
    if result.get('sf_running', False) or result.get('window_info', ''):
        score += 10
        feedback_parts.append("System: SF Active (10/10)")
    else:
        feedback_parts.append("System: SF Not Detected (0/10)")

    # 3. Criterion: CSV Export (40 pts)
    csv_score = 0
    if result.get('csv_found', False):
        csv_score += 10
        details = []
        
        if result.get('is_image_data', False):
            csv_score += 10
            details.append("Image Data")
        
        if result.get('has_target_domain', False):
            csv_score += 10
            details.append("Target Domain")
            
        row_count = result.get('csv_row_count', 0)
        if row_count >= 50:
            csv_score += 10
            details.append(f"{row_count} rows")
        elif row_count > 0:
            csv_score += 5
            details.append(f"Low row count: {row_count}")
            
        feedback_parts.append(f"CSV: Found ({csv_score}/40) [{', '.join(details)}]")
    else:
        feedback_parts.append("CSV: Not Found (0/40)")
    
    score += csv_score

    # 4. Criterion: Report (50 pts)
    report_score = 0
    if result.get('report_found', False):
        report_score += 10
        details = []
        
        if result.get('report_has_counts', False):
            report_score += 10
            details.append("Counts")
        
        if result.get('report_has_size_analysis', False):
            report_score += 15
            details.append("Size Analysis")
            
        if result.get('report_has_recommendation', False):
            report_score += 15
            details.append("Recommendations")
            
        feedback_parts.append(f"Report: Found ({report_score}/50) [{', '.join(details)}]")
    else:
        feedback_parts.append("Report: Not Found (0/50)")
        
    score += report_score

    # 5. Final Determination
    # Must have at least created the files to pass
    passed = (result.get('csv_found', False) and result.get('report_found', False) and score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }