#!/usr/bin/env python3
import json
import os
import tempfile
import logging

# Logger setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_epa_refrigerant_compliance(traj, env_info, task_info):
    """
    Verifies the EPA Refrigerant Compliance Research task.
    
    Criteria:
    1. Output JSON file exists and is valid JSON.
    2. AIM Act phasedown percentages are reasonably correct.
    3. Refrigerant list contains R-410A and at least 3 alternatives.
    4. GWP values and Safety Classes are correct for listed refrigerants.
    5. Section 608 requirements are correctly identified.
    6. Browser history shows visits to EPA.gov.
    7. Bookmark folder 'HVAC Regulatory Research' exists with >3 items.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    phasedown_targets = metadata.get('phasedown_targets', {"2024": 40, "2029": 70, "2036": 85})
    
    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback = []
    
    # Data extraction
    file_exists = result_data.get('file_exists', False)
    file_content = result_data.get('file_content') # This is the JSON content of the user's file
    history = result_data.get('history', [])
    bookmarks = result_data.get('bookmarks', [])
    task_start = result_data.get('task_start', 0)
    file_mtime = result_data.get('file_mtime', 0)

    # --- CRITERION 1: File Existence & Validity (10 pts) ---
    if file_exists and file_content:
        # Check anti-gaming timestamp
        if file_mtime > task_start:
            score += 10
            feedback.append("Output file created successfully.")
        else:
            feedback.append("Output file exists but timestamp suggests it wasn't created during this session.")
    else:
        feedback.append("Output file not found or invalid JSON.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # --- CRITERION 2: Browser Evidence (History & Bookmarks) (25 pts) ---
    
    # History Check (10 pts)
    epa_visits = sum(1 for url in history if "epa.gov" in url)
    industry_visits = sum(1 for url in history if any(d in url for d in ["ahri", "honeywell", "daikin", "chemours", "opteon", "ashrae"]))
    
    if epa_visits >= 3:
        score += 5
        feedback.append(f"Good EPA research detected ({epa_visits} visits).")
    elif epa_visits > 0:
        score += 2
        feedback.append("Minimal EPA research detected.")
    else:
        feedback.append("No EPA.gov visits found.")
        
    if industry_visits > 0:
        score += 5
        feedback.append("Industry source visited.")
    else:
        feedback.append("No industry/manufacturer sources found in history.")

    # Bookmark Check (15 pts)
    # Filter bookmarks by folder name 'HVAC Regulatory Research'
    # Note: SQLite query returned folder_name
    relevant_bookmarks = [b for b in bookmarks if "HVAC Regulatory Research" in b.get("folder_name", "")]
    
    if len(relevant_bookmarks) >= 4:
        score += 15
        feedback.append(f"Bookmark folder correctly populated ({len(relevant_bookmarks)} items).")
    elif len(relevant_bookmarks) > 0:
        score += 5
        feedback.append(f"Bookmark folder exists but has insufficient items ({len(relevant_bookmarks)}/4).")
    else:
        # Check if they just made bookmarks without the specific folder
        if len(bookmarks) >= 4:
             score += 2
             feedback.append("Bookmarks created, but not in the required 'HVAC Regulatory Research' folder.")
        else:
             feedback.append("Required bookmarks missing.")

    # --- CRITERION 3: Content Accuracy (65 pts) ---
    
    # A. AIM Act Phasedown (15 pts)
    aim_data = file_content.get("aim_act", {})
    # Allow small variance in interpreting "reduction" vs "remaining"
    # Target is reduction: 2024=40%, 2029=70%, 2036=85%
    p24 = aim_data.get("phasedown_2024_pct")
    p29 = aim_data.get("phasedown_2029_pct")
    p36 = aim_data.get("phasedown_2036_pct")
    
    correct_phases = 0
    # 2024: 40% reduction (accept 35-45)
    if isinstance(p24, (int, float)) and 35 <= p24 <= 45: correct_phases += 1
    # 2029: 70% reduction (accept 60-75, sometimes cited as steps)
    if isinstance(p29, (int, float)) and 60 <= p29 <= 75: correct_phases += 1
    # 2036: 85% reduction (accept 80-90)
    if isinstance(p36, (int, float)) and 80 <= p36 <= 90: correct_phases += 1
    
    score += (correct_phases * 5)
    feedback.append(f"AIM Act Phasedown data: {correct_phases}/3 targets correct.")

    # B. Refrigerant Data (35 pts)
    refs = file_content.get("refrigerants", {})
    # Must have R-410A + 3 others = 4 total
    if len(refs) >= 4:
        score += 10
        feedback.append(f"Documented {len(refs)} refrigerants (Goal: 4+).")
    else:
        score += (len(refs) * 2)
        feedback.append(f"Insufficient number of refrigerants: {len(refs)}/4.")

    # Validate specific data points
    valid_ref_entries = 0
    for name, data in refs.items():
        gwp = data.get("gwp")
        safety = data.get("ashrae_safety_class")
        
        # Basic type check
        if not isinstance(gwp, (int, float)) or not isinstance(safety, str):
            continue
            
        is_valid = False
        name_upper = name.upper()
        
        # Check against broad heuristics if exact match not found
        if "410A" in name_upper:
            if 1800 < gwp < 2300 and safety == "A1": is_valid = True
        elif "32" in name_upper:
            if 600 < gwp < 800 and "A2L" in safety: is_valid = True
        elif "454B" in name_upper:
            if 400 < gwp < 550 and "A2L" in safety: is_valid = True
        elif "290" in name_upper: # Propane
            if gwp < 20 and "A3" in safety: is_valid = True
        elif "1234YF" in name_upper:
            if gwp < 10 and "A2L" in safety: is_valid = True
        elif "134A" in name_upper:
            if 1300 < gwp < 1500 and safety == "A1": is_valid = True
        else:
            # Generic sanity check for unknown refrigerants
            # If they provided a number and a valid-looking safety class, give partial credit
            if 0 < gwp < 15000 and safety in ["A1", "A2", "A2L", "A3", "B1", "B2L", "B3"]:
                is_valid = True

        if is_valid:
            valid_ref_entries += 1

    # Cap accuracy score at 25
    accuracy_score = min(25, valid_ref_entries * 6.25) 
    score += accuracy_score
    feedback.append(f"Refrigerant data accuracy score: {accuracy_score:.1f}/25")

    # C. Section 608 (15 pts)
    sec608 = file_content.get("section_608", {})
    s608_score = 0
    if sec608.get("certification_required") is True: s608_score += 5
    if sec608.get("venting_prohibited") is True: s608_score += 5
    if sec608.get("recordkeeping_required") is True: s608_score += 5
    
    score += s608_score
    feedback.append(f"Section 608 checks: {s608_score}/15 pts.")

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": "\n".join(feedback)
    }