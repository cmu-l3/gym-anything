#!/usr/bin/env python3
import json
import base64
import datetime
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_agent_report(content):
    """
    Parses the agent's pipe-delimited report.
    Expected format per line: Event Name | YYYY-MM-DD | HH:MM
    Returns list of dicts: [{'name': str, 'date': str, 'time': str, 'raw': str}]
    """
    entries = []
    lines = content.strip().split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split('|')]
        entry = {'raw': line}
        if len(parts) >= 3:
            entry['name'] = parts[0]
            entry['date'] = parts[1]
            entry['time'] = parts[2]
        entries.append(entry)
    return entries

def check_time_match(agent_time_str, db_datetime_str, tolerance_minutes=5):
    """
    Compares agent time (HH:MM) with DB datetime string (YYYY-MM-DD HH:MM:SS).
    Handles potential timezone offsets implicitly by checking against UTC 
    and common offsets if needed, but primarily checks if the HH:MM matches
    the DB time (assuming Odoo UI displays server time or we match blindly).
    
    Task asks for what is shown in UI. 
    If DB is UTC, and UI is UTC (default in this env), they match.
    """
    try:
        # DB format: "2023-10-01 14:00:00"
        db_dt = datetime.datetime.strptime(db_datetime_str, "%Y-%m-%d %H:%M:%S")
        db_hm = db_dt.strftime("%H:%M")
        
        # Exact match check
        if agent_time_str == db_hm:
            return True, "Exact match"
            
        # Tolerance check (parsing agent time)
        agent_h, agent_m = map(int, agent_time_str.split(':'))
        agent_dt_dummy = db_dt.replace(hour=agent_h, minute=agent_m, second=0)
        
        diff = abs((db_dt - agent_dt_dummy).total_seconds())
        if diff <= tolerance_minutes * 60:
            return True, f"Within {tolerance_minutes} mins"
            
        return False, f"Expected {db_hm}, got {agent_time_str}"
        
    except Exception as e:
        return False, f"Error parsing time: {e}"

def verify_generate_attendee_schedule_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check File Existence & Timestamp (Anti-gaming)
    score = 0
    feedback = []
    
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not created"}
    
    score += 5
    feedback.append("File created")
    
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if file_mtime > task_start:
        score += 5
        feedback.append("File created during task")
    else:
        feedback.append("Warning: File timestamp suspicious")

    # 3. Decode and Parse Content
    try:
        content_b64 = result.get('output_content_b64', "")
        content = base64.b64decode(content_b64).decode('utf-8')
    except Exception:
        return {"passed": False, "score": score, "feedback": "Could not decode file content"}

    if not content.strip():
        return {"passed": False, "score": score, "feedback": "File is empty"}
        
    score += 10
    feedback.append("File is not empty")

    entries = parse_agent_report(content)
    if not entries:
         return {"passed": False, "score": score, "feedback": "No valid entries found (check format)"}
         
    # 4. Compare with Ground Truth
    gt_data = result.get('ground_truth', {})
    gt_events = gt_data.get('events', [])
    
    if not gt_events:
        feedback.append("Warning: No ground truth events found for Grace Patel (DB issue?)")
        # In this edge case, we can't verify accuracy properly.
        return {"passed": False, "score": score, "feedback": "System Error: Ground truth missing"}

    # Scoring Logic
    # We match each ground truth event to the BEST matching agent entry
    # Points: 
    # - Name match: 6 pts each (max 5 events -> 30)
    # - Date match: 5 pts each (max 5 events -> 25)
    # - Time match: 5 pts each (max 5 events -> 25)
    # Total accuracy points available: 80
    
    # Let's cap the evaluated events to the number of GT events (or 5, whichever is smaller for weighting)
    # But effectively we just sum up points for correct info found.
    
    found_events = 0
    correct_dates = 0
    correct_times = 0
    
    # Clone GT events to track which ones have been matched (avoid double counting)
    unmatched_gt = {e['id']: e for e in gt_events}
    
    for entry in entries:
        if 'name' not in entry: 
            continue
            
        agent_name = entry['name'].lower()
        
        # Find best match in unmatched GT
        best_match_id = None
        
        for eid, gt_event in unmatched_gt.items():
            if gt_event['name'].lower() in agent_name or agent_name in gt_event['name'].lower():
                best_match_id = eid
                break
        
        if best_match_id:
            found_events += 1
            gt = unmatched_gt.pop(best_match_id)
            
            # Check Date
            # GT 'start' is "YYYY-MM-DD HH:MM:SS"
            gt_date = gt['start'].split(' ')[0]
            if entry.get('date') == gt_date:
                correct_dates += 1
            else:
                feedback.append(f"Date mismatch for '{gt['name']}': Expected {gt_date}, got {entry.get('date')}")

            # Check Time
            # We use the helper
            if 'time' in entry:
                match, msg = check_time_match(entry['time'], gt['start'])
                if match:
                    correct_times += 1
                else:
                    feedback.append(f"Time mismatch for '{gt['name']}': {msg}")
    
    # Calculate Accuracy Scores
    # Normalize based on GT count. If GT has 5 events, finding all 5 = max points.
    num_gt = len(gt_events)
    if num_gt == 0: num_gt = 1 # prevent div/0
    
    # Weights for the remaining 80 points
    w_found = 30 / num_gt
    w_date = 25 / num_gt
    w_time = 25 / num_gt
    
    score += min(30, found_events * w_found)
    score += min(25, correct_dates * w_date)
    score += min(25, correct_times * w_time)
    
    score = int(score)
    
    feedback.append(f"Found {found_events}/{num_gt} events")
    feedback.append(f"Dates correct: {correct_dates}/{found_events}")
    feedback.append(f"Times correct: {correct_times}/{found_events}")

    passed = score >= 60 and found_events >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }