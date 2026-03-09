#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_us_legislation_swimlane(traj, env_info, task_info):
    """
    Verifies the US Legislation Swimlane diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected requirements from metadata
    # (Defaults if metadata missing)
    min_swimlanes = 4
    min_steps = 14
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Extract analysis data
    analysis = result.get('analysis', {})
    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified', False)
    png_exists = result.get('png_exists', False)
    png_size = result.get('png_size', 0)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Saved & Modified (5 pts)
    if file_exists and file_modified:
        score += 5
        feedback_parts.append("File saved.")
    elif file_exists:
        feedback_parts.append("File exists but not modified (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "No file saved."}
        
    # Criterion 2: Swimlanes (20 pts)
    # Expect 4: House, Senate, Conference, President
    sl_count = analysis.get('swimlane_count', 0)
    sl_labels = str(analysis.get('swimlane_labels', [])).lower()
    
    required_actors = ["house", "senate", "president", "conference"]
    actors_found = sum(1 for actor in required_actors if actor in sl_labels)
    
    if sl_count >= 4 and actors_found >= 3:
        score += 20
        feedback_parts.append(f"Swimlanes correct ({sl_count}).")
    elif sl_count >= 2:
        score += 10
        feedback_parts.append(f"Partial swimlanes ({sl_count}).")
    else:
        feedback_parts.append(f"Missing swimlanes (found {sl_count}).")
        
    # Criterion 3: Process Steps (15 pts)
    # Complex process requires many steps
    steps = analysis.get('process_steps', 0)
    if steps >= 14:
        score += 15
        feedback_parts.append(f"Sufficient process steps ({steps}).")
    elif steps >= 8:
        score += 8
        feedback_parts.append(f"Partial process steps ({steps}).")
    else:
        feedback_parts.append(f"Too few process steps ({steps}).")

    # Criterion 4: Decisions (10 pts)
    decisions = analysis.get('decisions', 0)
    if decisions >= 3:
        score += 10
        feedback_parts.append("Decision points present.")
    elif decisions >= 1:
        score += 5
        feedback_parts.append("Few decision points.")
    else:
        feedback_parts.append("No decision diamonds found.")

    # Criterion 5: Connections (10 pts)
    edges = analysis.get('edges', 0)
    if edges >= 18:
        score += 10
        feedback_parts.append("Flow connected well.")
    elif edges >= 10:
        score += 5
        feedback_parts.append("Partial connections.")
        
    # Criterion 6: Keywords (10 pts)
    # Ensures content matches domain
    keywords = analysis.get('keywords_found', [])
    if len(keywords) >= 8:
        score += 10
        feedback_parts.append("Domain vocabulary correct.")
    elif len(keywords) >= 5:
        score += 5
        feedback_parts.append("Partial domain vocabulary.")
        
    # Criterion 7: Multi-page (Veto Override) (10 pts)
    pages = analysis.get('page_count', 0)
    override_found = analysis.get('override_page_found', False)
    
    if pages >= 2 and override_found:
        score += 10
        feedback_parts.append("Veto Override page found.")
    elif pages >= 2:
        score += 5
        feedback_parts.append("Second page found (title mismatch).")
        
    # Criterion 8: Terminators (5 pts)
    if analysis.get('terminators', 0) >= 2:
        score += 5
        feedback_parts.append("Terminators present.")
        
    # Criterion 9: PNG Export (15 pts)
    if png_exists and png_size > 5000:
        score += 15
        feedback_parts.append("PNG export successful.")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG too small/empty.")
    else:
        feedback_parts.append("No PNG export.")

    # Final Check
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }