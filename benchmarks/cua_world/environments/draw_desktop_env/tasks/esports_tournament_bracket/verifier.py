#!/usr/bin/env python3
"""
Verifier for esports_tournament_bracket task.
"""

import json
import os
import tempfile

def verify_esports_bracket(traj, env_info, task_info):
    """
    Verifies the Esports Tournament Bracket task.
    Checks:
    1. Output files exist (.drawio, .png)
    2. Structure (shapes arranged in columns/layers)
    3. Logic (Correct winners advanced to final stages)
    4. Style (Champion box is gold)
    """
    
    # Use copy_from_env to retrieve the analysis done by export_result.sh
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
            
    # Calculate Score
    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get("files_exist") and result.get("file_modified_correctly"):
        score += 10
        feedback.append("Draw.io file saved.")
    elif result.get("files_exist"):
        score += 5
        feedback.append("Draw.io file exists but timestamp is old.")
    else:
        feedback.append("Draw.io file not found.")
        
    if result.get("png_exists"):
        score += 10
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")
        
    # 2. Structure (20 pts)
    struct_score = result.get("structure_score", 0)
    if struct_score > 0:
        score += 20
        feedback.append("Bracket structure detected (columns).")
    else:
        feedback.append("Clear bracket column structure not detected.")
        
    # 3. Logic (40 pts)
    # Logic score from export script (max 100 in script, mapped to 40 here)
    # Logic score components in script:
    # - Champ found in last col: 40
    # - Semifinalists found: 30
    # - Edges count: 30
    
    raw_logic = result.get("logic_score", 0)
    final_logic_pts = int((raw_logic / 100) * 40)
    score += final_logic_pts
    
    if final_logic_pts >= 40:
        feedback.append("Tournament logic correct (Winners advanced properly).")
    elif final_logic_pts > 0:
        feedback.append(f"Partial tournament logic correct ({final_logic_pts}/40).")
    else:
        feedback.append("Tournament logic incorrect (Winners not found in diagram).")
        
    # 4. Style (20 pts)
    if result.get("style_score", 0) > 0:
        score += 20
        feedback.append("Champion highlighting (Gold) applied.")
    else:
        feedback.append("Champion box not highlighted in Gold.")
        
    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result.get("details", {})
    }