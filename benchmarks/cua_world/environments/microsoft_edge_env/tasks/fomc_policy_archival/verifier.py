#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fomc_archival(traj, env_info, task_info):
    """
    Verifies the FOMC Policy Archival task.
    
    Criteria:
    1. Directory '/home/ga/Documents/FOMC_Policy/' exists.
    2. 'statement.pdf' exists, is a valid PDF, and created during task.
    3. 'implementation_note.pdf' exists, is a valid PDF, and created during task.
    4. 'metadata.txt' contains a date string.
    5. 'summary_text.txt' contains relevant economic keywords.
    6. Browser history confirms visit to Federal Reserve website.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 2. Check Directory (10 pts)
    if result.get("target_dir_exists"):
        score += 10
        feedback.append("Directory created successfully.")
    else:
        feedback.append("Target directory '/home/ga/Documents/FOMC_Policy' NOT found.")
        return {"passed": False, "score": 0, "feedback": "Target directory not created."}

    files = result.get("files", {})
    
    # 3. Check Statement PDF (20 pts)
    stmt = files.get("statement.pdf", {})
    if stmt.get("exists"):
        if stmt.get("created_during_task"):
            if stmt.get("is_pdf") and stmt.get("size", 0) > 1000:
                score += 20
                feedback.append("Statement PDF downloaded successfully.")
            else:
                score += 5
                feedback.append("Statement PDF exists but seems invalid or empty.")
        else:
            feedback.append("Statement PDF exists but was NOT created during this task (stale data).")
    else:
        feedback.append("statement.pdf NOT found.")

    # 4. Check Implementation Note PDF (20 pts)
    imp = files.get("implementation_note.pdf", {})
    if imp.get("exists"):
        if imp.get("created_during_task"):
            if imp.get("is_pdf") and imp.get("size", 0) > 1000:
                score += 20
                feedback.append("Implementation Note PDF downloaded successfully.")
            else:
                score += 5
                feedback.append("Implementation Note PDF exists but seems invalid or empty.")
        else:
            feedback.append("Implementation Note PDF exists but was NOT created during this task.")
    else:
        feedback.append("implementation_note.pdf NOT found.")

    # 5. Check Metadata (15 pts)
    meta = files.get("metadata.txt", {})
    if meta.get("exists") and meta.get("created_during_task"):
        content = meta.get("content_preview", "").lower()
        # Look for month names or common date formats
        months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        has_date = any(m in content for m in months) or any(char.isdigit() for char in content)
        
        if has_date:
            score += 15
            feedback.append("Metadata file contains date info.")
        else:
            score += 5
            feedback.append("Metadata file exists but content is unclear.")
    else:
        feedback.append("metadata.txt NOT found or stale.")

    # 6. Check Summary Text (20 pts)
    summ = files.get("summary_text.txt", {})
    if summ.get("exists") and summ.get("created_during_task"):
        content = summ.get("content_preview", "").lower()
        # Keywords expected in a Fed statement
        keywords = ["committee", "inflation", "employment", "target range", "federal funds", "economic", "goals"]
        hits = sum(1 for k in keywords if k in content)
        
        if hits >= 2:
            score += 20
            feedback.append(f"Summary text extracted and contains relevant keywords (found {hits}).")
        elif len(content) > 50:
            score += 10
            feedback.append("Summary text exists but few keywords found.")
        else:
            score += 5
            feedback.append("Summary text file is too short.")
    else:
        feedback.append("summary_text.txt NOT found or stale.")

    # 7. Check History (15 pts)
    if result.get("history_found"):
        score += 15
        feedback.append("Browser history confirms visit to Federal Reserve website.")
    else:
        feedback.append("No history of visiting federalreserve.gov found.")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }