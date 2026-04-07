#!/usr/bin/env python3
"""
Verifier for configure_osint_search_engines task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_osint_config(traj, env_info, task_info):
    """
    Verifies that the agent configured 3 OSINT search engines, tested them, and wrote a report.
    
    Scoring Breakdown (100 pts total):
    - Report Exists & Created during task: 10 pts
    - Report Content (Mentions all tools): 9 pts (3 pts each)
    - Configuration (DB check): 36 pts (12 pts each for correct keyword+url match)
    - Verification (History check): 30 pts (10 pts each for visiting the sites)
    - Report Quality (> 200 bytes): 15 pts
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Data
    configs = result.get("configs", {})
    history = result.get("history", {})
    report = result.get("report", {})
    
    score = 0
    feedback_parts = []
    
    # 3. Report Verification (25 pts max)
    if report.get("exists") and report.get("created_during_task"):
        score += 10
        feedback_parts.append("Report created.")
        
        # Content checks
        mentions = 0
        if report.get("mentions_wayback"): mentions += 1
        if report.get("mentions_crt"): mentions += 1
        if report.get("mentions_shodan"): mentions += 1
        
        score += (mentions * 3)
        if mentions < 3:
            feedback_parts.append(f"Report missing mention of {3 - mentions} tools.")
            
        if report.get("size", 0) > 200:
            score += 15
            feedback_parts.append("Report is comprehensive.")
        else:
            feedback_parts.append("Report is too short.")
    else:
        feedback_parts.append("No valid report found.")

    # 4. Search Engine Configuration Verification (36 pts max)
    # Expected patterns
    # Wayback: url contains 'web.archive.org' and keyword 'wayback'
    # crt: url contains 'crt.sh' and keyword 'crt'
    # shodan: url contains 'shodan.io' and keyword 'shodan'
    
    for tool in ['wayback', 'crt', 'shodan']:
        cfg = configs.get(tool, {})
        if cfg.get("found"):
            # Check URL pattern
            url = cfg.get("url", "").lower()
            if tool == 'wayback' and 'web.archive.org' in url:
                score += 12
            elif tool == 'crt' and 'crt.sh' in url:
                score += 12
            elif tool == 'shodan' and 'shodan.io' in url:
                score += 12
            else:
                # Keyword found but URL wrong
                score += 5 
                feedback_parts.append(f"Keyword '{tool}' found but URL seems incorrect.")
        else:
            feedback_parts.append(f"Search engine keyword '{tool}' NOT found.")
            
    # 5. Usage Verification (History Check) (30 pts max)
    # Did they actually use it?
    for tool in ['wayback', 'crt', 'shodan']:
        hist = history.get(tool, {})
        if hist.get("visited"):
            score += 10
        else:
            feedback_parts.append(f"No evidence of testing '{tool}' (site not in history).")

    # 6. Final Score Calculation
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }