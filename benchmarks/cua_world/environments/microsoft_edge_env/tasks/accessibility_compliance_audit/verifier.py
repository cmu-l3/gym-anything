#!/usr/bin/env python3
"""
Verifier for Accessibility Compliance Audit task.

Scoring Criteria:
1. Report file exists and was created/modified during task (10 pts)
2. Target HTML file was visited in browser (10 pts)
3. Report correctly identifies the ID for Missing Alt Text error (30 pts)
4. Report correctly identifies the ID for Low Contrast error (30 pts)
5. Report correctly identifies the ID for Missing Label error (20 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_accessibility_audit(traj, env_info, task_info):
    # 1. Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Load the actual report content
    report_content = ""
    if result.get("report_exists"):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(result["report_path"], temp_report.name)
            with open(temp_report.name, 'r', errors='ignore') as f:
                report_content = f.read().lower()  # Normalize for regex/search
        except Exception as e:
            logger.warning(f"Failed to read report file: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # 4. Evaluation Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Report Existence & Freshness (10 pts)
    if result.get("report_exists") and result.get("report_modified_during_task"):
        score += 10
        feedback_parts.append("Report file created successfully (10/10)")
    elif result.get("report_exists"):
        score += 5
        feedback_parts.append("Report file exists but timestamp is stale (5/10)")
    else:
        feedback_parts.append("Report file not found (0/10)")

    # Criterion 2: Browser History (10 pts)
    if result.get("target_file_visited"):
        score += 10
        feedback_parts.append("Target HTML file visited in Edge (10/10)")
    else:
        feedback_parts.append("Browser history does not show visit to target file (0/10)")

    # Criteria 3-5: Content Analysis
    # We look for the ID and relevant keywords in the report content.
    # Note: We don't require them to be on the same line, just present in the document 
    # and contextually distinct if possible, but for simple string matching:
    # A passing report MUST contain the ID.
    
    metadata = task_info.get("metadata", {})
    expected_issues = metadata.get("expected_issues", [])
    
    for issue in expected_issues:
        elem_id = issue["id"]
        keywords = issue["type_keywords"]
        points = 0
        
        # Check if ID is present
        if elem_id in report_content:
            # Check if any type keyword is present
            if any(kw in report_content for kw in keywords):
                # Full points: ID + Relevant Keyword found
                if elem_id == "newsletter-input": points = 20
                else: points = 30
                
                feedback_parts.append(f"Correctly identified '{elem_id}' with issue details ({points}/{points})")
            else:
                # Partial points: ID found but issue type unclear
                points = 10
                feedback_parts.append(f"Found ID '{elem_id}' but missing issue description keywords ({points})")
        else:
            feedback_parts.append(f"Failed to identify Element ID '{elem_id}' (0)")
        
        score += points

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }