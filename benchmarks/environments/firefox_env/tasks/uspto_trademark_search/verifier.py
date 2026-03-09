#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_uspto_trademark_search(traj, env_info, task_info):
    """
    Verifies the USPTO Trademark Search task.
    
    Scoring Criteria (100 pts total):
    1. Browser History (20 pts): Visited uspto.gov search pages.
    2. Bookmarks (15 pts): 'Trademark Research' folder exists (5) + contains >=3 USPTO links (10).
    3. Report File (15 pts): Exists, Valid JSON, Created during task.
    4. Data Accuracy (50 pts):
       - Rust entry (15 pts): Correct Owner, Reg Number/Status plausible.
       - Kubernetes entry (15 pts): Correct Owner, Reg Number/Status plausible.
       - Android entry (15 pts): Correct Owner, Reg Number/Status plausible.
       - Formatting (5 pts): Dates in YYYY-MM-DD.
       
    Pass Threshold: 65 points.
    """
    
    # 1. Setup & Read Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Evaluate Browser Activity (35 pts)
    # History
    visits = result.get("uspto_visits", 0)
    if visits >= 1:
        score += 20
        feedback.append(f"History Check: Visited USPTO ({visits} pages) [20/20]")
    else:
        feedback.append("History Check: No USPTO visits found [0/20]")
        
    # Bookmarks
    bf_exists = result.get("bookmark_folder_exists", False)
    bm_count = result.get("uspto_bookmarks_count", 0)
    
    if bf_exists:
        score += 5
        feedback.append("Bookmark Check: Folder exists [5/5]")
        if bm_count >= 3:
            score += 10
            feedback.append(f"Bookmark Check: {bm_count} USPTO bookmarks found [10/10]")
        else:
            feedback.append(f"Bookmark Check: Only {bm_count}/3 bookmarks found [0/10]")
    else:
        feedback.append("Bookmark Check: 'Trademark Research' folder not found [0/15]")

    # 3. Evaluate Report Existence (15 pts)
    report_exists = result.get("report_exists", False)
    report_fresh = result.get("report_fresh", False)
    report_content = result.get("report_content", {})
    
    if report_exists and report_fresh and isinstance(report_content, dict) and "error" not in report_content:
        score += 15
        feedback.append("File Check: JSON report exists and is valid [15/15]")
    elif report_exists:
        score += 5
        feedback.append("File Check: Report exists but is stale or invalid JSON [5/15]")
    else:
        feedback.append("File Check: Report file not found [0/15]")
        # Early exit if no data to check
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 4. Evaluate Data Accuracy (50 pts)
    # Helper to check entries
    def check_entry(entry_key, expected_owners, expected_reg_start):
        entry = report_content.get(entry_key, {})
        if not entry:
            return 0, f"Missing '{entry_key}' entry"
            
        points = 0
        logs = []
        
        # Check Owner (Case insensitive partial match)
        owner = str(entry.get("owner", "")).lower()
        owner_match = any(k.lower() in owner for k in expected_owners)
        if owner_match:
            points += 10
            logs.append("Owner Correct")
        else:
            logs.append(f"Owner Incorrect (Got: {entry.get('owner')})")
            
        # Check Registration Number (Approximate check for valid US format or exact match)
        reg = str(entry.get("registration_number", "")).strip()
        # Allow exact match OR if owner was correct, allow any 7-digit number (flexibility for different classes)
        if reg == expected_reg_start or (owner_match and len(reg) == 7 and reg.isdigit()):
            points += 5
            logs.append("Reg# Valid")
        else:
            logs.append(f"Reg# Mismatch (Got: {reg})")
            
        return points, f"{entry_key.title()}: {', '.join(logs)}"

    # Check Rust
    p, msg = check_entry("rust", ["Rust Foundation", "Mozilla"], "6694602")
    score += p
    feedback.append(f"Data - {msg} [{p}/15]")

    # Check Kubernetes
    p, msg = check_entry("kubernetes", ["Linux Foundation"], "5307567")
    score += p
    feedback.append(f"Data - {msg} [{p}/15]")

    # Check Android
    p, msg = check_entry("android", ["Google"], "3594803")
    score += p
    feedback.append(f"Data - {msg} [{p}/15]")

    # Check Formatting (Dates)
    dates_valid = True
    for k in ["rust", "kubernetes", "android"]:
        date = report_content.get(k, {}).get("registration_date", "")
        # Simple regex check for YYYY-MM-DD
        import re
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(date)):
            dates_valid = False
            break
            
    if dates_valid:
        score += 5
        feedback.append("Formatting: Dates are ISO 8601 [5/5]")
    else:
        feedback.append("Formatting: Dates not in YYYY-MM-DD format [0/5]")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }