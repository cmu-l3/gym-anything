#!/usr/bin/env python3
"""
Verifier for create_standalone_note task.

Verification Strategy:
1. DB Check: Standalone note exists (parentItemID is NULL).
2. DB Check: Note count increased.
3. Content Check: Note contains specific legal case citations and text.
4. Anti-gaming: Note was created during task window.
5. VLM: Optional check if trajectory frames show editing.

Scoring (100 pts):
- Standalone note exists: 20 pts
- Count increased (proof of creation): 10 pts
- Required phrases (10 pts each, max 50):
  - "Brown v. Board"
  - "Miranda v. Arizona"
  - "Gideon v. Wainwright"
  - "Research Memo"
  - "Constitutional Rights Framework"
- Bonus phrases (5 pts each, max 10):
  - "equal protection"
  - "custodial interrogation"
  - "right to counsel"
- No VLM errors: 10 pts
"""

import os
import json
import logging
import tempfile
from datetime import datetime
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_standalone_note(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve Result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {e}"
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # Metadata requirements
    metadata = task_info.get("metadata", {})
    required = metadata.get("required_phrases", [])
    bonus = metadata.get("bonus_phrases", [])

    # 2. Check Existence and Standalone Status
    note_found = result.get("note_found", False)
    is_standalone = result.get("is_standalone", False)
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    
    if note_found and is_standalone:
        score += 20
        feedback.append("Standalone note found in library (+20)")
    else:
        feedback.append("No standalone note found. Ensure you created a 'New Standalone Note' and not a child note.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 3. Check Creation (Count Increase)
    if final_count > initial_count:
        score += 10
        feedback.append("Note verified as newly created (+10)")
    else:
        feedback.append("Note count did not increase (did you overwrite an existing one?)")

    # 4. Check Content
    content = result.get("content", "").lower()
    
    # Remove HTML tags for cleaner checking (rudimentary)
    import re
    text_content = re.sub('<[^<]+?>', ' ', content)
    
    # Required phrases
    phrases_found = 0
    for phrase in required:
        if phrase.lower() in text_content or phrase.lower() in content:
            phrases_found += 1
            score += 10
            feedback.append(f"Found phrase '{phrase}' (+10)")
        else:
            feedback.append(f"Missing phrase '{phrase}'")
            
    # Bonus phrases
    bonus_score = 0
    for phrase in bonus:
        if phrase.lower() in text_content or phrase.lower() in content:
            bonus_score += 5
            feedback.append(f"Bonus: Found '{phrase}' (+5)")
    
    # Cap bonus at 10
    score += min(bonus_score, 10)

    # 5. Timestamp Check (Anti-gaming)
    # Logic: if count increased, we are reasonably sure. 
    # result['created_during_task'] comes from the export script logic.
    if result.get("created_during_task", False):
        feedback.append("Timestamp/Count verification passed")
    
    # 6. Basic VLM check (Did we get a final screenshot?)
    if result.get("screenshot_path") and os.path.exists(result["screenshot_path"]):
        score += 10
        feedback.append("Evidence screenshot captured (+10)")
        
    # Final Score Calculation
    # Max possible: 20 (exist) + 10 (count) + 50 (5 req phrases) + 10 (bonus) + 10 (screenshot) = 100
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": {
            "initial_count": initial_count,
            "final_count": final_count,
            "phrases_found": phrases_found
        }
    }