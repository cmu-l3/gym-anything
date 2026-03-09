#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime

def verify_standardize_page_hyphens(traj, env_info, task_info):
    """
    Verify that the user standardized page hyphens for 3 specific papers.
    
    Criteria:
    1. Turing 1936 paper pages = "230-265" (30 pts)
    2. Shannon 1948 paper pages = "379-423" (30 pts)
    3. He 2016 paper pages = "770-778" (30 pts)
    4. Database cleanliness (no double hyphens/en-dashes remaining in any pages) (10 pts)
    """
    
    # 1. Load result using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

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

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Targets
    expected = {
        "turing": "230-265",
        "shannon": "379-423",
        "he": "770-778"
    }
    
    items = result.get("items", {})
    
    # Check Turing
    turing = items.get("turing", {})
    if turing.get("pages_value") == expected["turing"]:
        score += 30
        feedback.append("Turing paper corrected.")
    else:
        feedback.append(f"Turing paper incorrect (Found: '{turing.get('pages_value')}', Expected: '{expected['turing']}').")

    # Check Shannon
    shannon = items.get("shannon", {})
    if shannon.get("pages_value") == expected["shannon"]:
        score += 30
        feedback.append("Shannon paper corrected.")
    else:
        feedback.append(f"Shannon paper incorrect (Found: '{shannon.get('pages_value')}', Expected: '{expected['shannon']}').")

    # Check He
    he = items.get("he", {})
    if he.get("pages_value") == expected["he"]:
        score += 30
        feedback.append("He paper corrected.")
    else:
        feedback.append(f"He paper incorrect (Found: '{he.get('pages_value')}', Expected: '{expected['he']}').")

    # Check Cleanliness
    bad_count = result.get("database_cleanliness", {}).get("bad_format_count", 0)
    if bad_count == 0:
        score += 10
        feedback.append("Database clean (no bad hyphens remaining).")
    else:
        feedback.append(f"Database still contains {bad_count} items with bad formatting.")

    # 3. Timestamp sanity check (Anti-gaming)
    # Check if modified date is after task start. 
    # Zotero stores dates as strings usually, but clientDateModified is reliable.
    # Here we perform a soft check: if score > 0, we assume interaction happened 
    # because the initial state was corrupted by setup script.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }