#!/usr/bin/env python3
"""
Verifier for group_by_resource_pdf task.

Verification Strategy:
1. Check if PDF exists and was created during the task.
2. Extract text from PDF.
3. Verify grouping logic by checking the order of tasks.
   - In standard WBS (ID order): "Database Schema Design" (ID 3) appears BEFORE "UI/UX Wireframes" (ID 4).
   - In Resource Grouping (Alphabetical): "UI/UX Wireframes" (Carol Williams) should appear BEFORE "Database Schema Design" (David Brown),
     because Carol comes before David alphabetically.
"""

import json
import os
import sys
import tempfile
import logging

# Ensure pdfminer is available
try:
    from pdfminer.high_level import extract_text
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pdfminer.six"])
    from pdfminer.high_level import extract_text

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_group_by_resource_pdf(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Desktop/resource_report.pdf')
    
    # Task Strings for order checking
    # "UI/UX Wireframes" is assigned to Carol
    # "Database Schema Design" is assigned to David
    # Alphabetical Resources: Carol < David
    # Therefore, in grouped view, UI/UX (Carol) should be found BEFORE Database (David)
    task_carol = metadata.get('task_string_1', "UI/UX Wireframes")
    task_david = metadata.get('task_string_2', "Database Schema Design")
    
    res_carol = "Carol Williams"
    res_david = "David Brown"

    # Temporary files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Load Result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

        # 2. Check File Existence & Timestamp (30 pts)
        if not result.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "PDF report not found on Desktop."}
        
        if not result.get('file_created_during_task', False):
             # If file exists but wasn't created now, it's stale (anti-gaming)
            return {"passed": False, "score": 0, "feedback": "A PDF exists but was not created during this task session."}
            
        if result.get('output_size_bytes', 0) < 1000:
            return {"passed": False, "score": 0, "feedback": "PDF file is too small (likely empty)."}
            
        score += 30
        feedback_parts.append("Valid PDF created")

        # 3. Analyze PDF Content (70 pts)
        try:
            copy_from_env(expected_path, temp_pdf.name)
            text = extract_text(temp_pdf.name)
            
            # Normalize whitespace
            text_clean = " ".join(text.split())
            
            # Check for presence of key strings
            if task_carol not in text_clean:
                feedback_parts.append(f"Missing task text: '{task_carol}'")
            if task_david not in text_clean:
                feedback_parts.append(f"Missing task text: '{task_david}'")
                
            idx_carol = text_clean.find(task_carol)
            idx_david = text_clean.find(task_david)
            
            # Check sorting logic
            if idx_carol != -1 and idx_david != -1:
                if idx_carol < idx_david:
                    score += 50
                    feedback_parts.append("Tasks are correctly grouped by Resource (Carol's tasks appear before David's).")
                else:
                    feedback_parts.append("Tasks appear in standard ID order (David before Carol). Grouping NOT applied.")
            
            # Check for Group Headers (Bonus/Confirmation)
            # If grouping is active, resource names usually appear as headers
            if res_carol in text_clean and res_david in text_clean:
                score += 20
                feedback_parts.append("Resource names found in report.")
            else:
                feedback_parts.append("Resource names missing from report.")

        except Exception as e:
            feedback_parts.append(f"Error analyzing PDF content: {str(e)}")
            
    finally:
        # Cleanup
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_pdf.name): os.unlink(temp_pdf.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }