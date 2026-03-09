#!/usr/bin/env python3
"""
Verifier for AMP Implementation Audit task.

Scoring breakdown:
- Screaming Frog ran (10 pts)
- AMP CSV Export found (newly created, proper name) (20 pts)
- AMP CSV content valid (headers + data rows) (30 pts)
- Report file exists (10 pts)
- Report content analysis (mentions specific errors) (30 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_amp_implementation_audit(traj, env_info, task_info):
    """Verify that AMP audit was performed, exported, and reported."""
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # Read result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 1. Check SF Running (10 pts)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog active")
    else:
        feedback_parts.append("Screaming Frog not active")

    # 2. Check CSV Existence (20 pts)
    if result.get('amp_csv_found', False):
        score += 20
        feedback_parts.append("AMP CSV file created")
    else:
        feedback_parts.append("AMP CSV file missing")

    # 3. Check CSV Content (30 pts)
    # The export script already checked for headers like "AMP" or "Validation" and row count
    if result.get('amp_data_valid', False):
        row_count = result.get('amp_row_count', 0)
        if row_count >= 2:
            score += 30
            feedback_parts.append(f"AMP CSV content valid ({row_count} rows)")
        else:
            score += 15
            feedback_parts.append(f"AMP CSV exists but has few rows ({row_count})")
    else:
        feedback_parts.append("AMP CSV content invalid or empty")

    # 4. Check Report Existence (10 pts)
    if result.get('report_found', False):
        score += 10
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file missing")

    # 5. Check Report Content (30 pts)
    # We need to read the actual text content to verify they identified errors
    report_valid = False
    report_feedback = "Report content generic"
    
    if result.get('report_found', False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/amp_report_check.txt", temp_report.name)
            with open(temp_report.name, 'r', errors='ignore') as f:
                content = f.read().lower()
                
            # Check for keywords related to the errors on crawler-test.com
            # Errors: "Missing Canonical", "Missing Non-AMP Return Link", "Validation Error"
            keywords_found = 0
            if "canonical" in content: keywords_found += 1
            if "return link" in content or "return-link" in content: keywords_found += 1
            if "validation" in content or "error" in content: keywords_found += 1
            
            if keywords_found >= 2:
                score += 30
                report_valid = True
                report_feedback = "Report correctly identifies multiple error types"
            elif keywords_found == 1:
                score += 15
                report_feedback = "Report identifies some errors"
            else:
                report_feedback = "Report missing specific error keywords"
                
        except Exception as e:
            report_feedback = f"Error reading report: {e}"
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
                
    feedback_parts.append(report_feedback)

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }