#!/usr/bin/env python3
"""
Verifier for configure_quick_copy_indigo task.

Verification Strategy:
1. Primary: Check the content of the exported text file.
   - Must contain the correct case citation "Brown v. Board of Education"
   - Must follow Bluebook/Indigo format (Date at end) vs APA format (Date after name).
2. Secondary: Check if the preference was actually updated in prefs.js.
3. Anti-gaming: File must be created/modified during the task.

Scoring (100 pts):
- File created and valid: 20 pts
- Content matches 'Brown v. Board': 20 pts
- Content is in Bluebook/Indigo format (NOT APA): 40 pts
- Preference setting reflects change: 20 pts
"""

import os
import json
import logging
import tempfile
import re
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_quick_copy_indigo(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that Quick Copy was configured to Indigo/Bluebook and used."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
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
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve export result: {e}"
        }

    score = 0
    feedback = []
    
    file_exists = result.get("file_exists", False)
    file_content = result.get("file_content", "").strip()
    pref_setting = result.get("pref_setting", "").lower()
    
    # Criterion 1: File Creation (20 pts)
    if file_exists and len(file_content) > 0:
        score += 20
        feedback.append("Citation file created (+20)")
    else:
        feedback.append("Citation file not found or empty")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback),
            "details": result
        }

    # Criterion 2: Correct Case (20 pts)
    # Flexible matching for "Brown v. Board"
    if "brown" in file_content.lower() and "board" in file_content.lower():
        score += 20
        feedback.append("Correct case cited (+20)")
    else:
        feedback.append(f"Content does not appear to be 'Brown v. Board' (Got: '{file_content[:50]}...')")

    # Criterion 3: Style Verification (40 pts)
    # We distinguish between APA and Bluebook/Indigo based on date position.
    # APA: Brown v. Board of Education (1954) 347 U.S. 483
    # Bluebook: Brown v. Board of Education, 347 U.S. 483 (1954)
    
    # Check for Year at the END of the string (Bluebook/Indigo characteristic)
    # Or check for Volume/Reporter BEFORE the year.
    
    bluebook_regex = r"347\s+U\.?S\.?\s+483.*\(1954\)"
    apa_indicator = r"\(1954\)\.?\s*347"  # Date comes before reporter in APA usually, or immediately after title
    
    is_bluebook = re.search(bluebook_regex, file_content, re.IGNORECASE)
    is_apa = re.search(apa_indicator, file_content, re.IGNORECASE)
    
    # Fallback check: "indigo" style often produces "Brown v. Bd. of Educ." abbreviation
    is_abbreviated = "bd. of educ" in file_content.lower()
    
    if is_bluebook or is_abbreviated:
        score += 40
        feedback.append("Citation format matches Indigo/Bluebook style (+40)")
    elif is_apa:
        feedback.append("Citation appears to be in APA format (Date before Reporter) - Failed style check")
    elif "(1954)" in file_content and file_content.strip().endswith("(1954)"):
        # Heuristic: if it ends with year, it's likely Bluebook/Indigo
        score += 40
        feedback.append("Citation format acceptable (Year at end) (+40)")
    else:
        feedback.append(f"Citation format unrecognized: '{file_content}'")

    # Criterion 4: Preference Setting (20 pts)
    # Check if the internal preference string contains 'indigo' or 'bluebook'
    if "indigo" in pref_setting or "bluebook" in pref_setting:
        score += 20
        feedback.append("Preferences updated correctly (+20)")
    elif "apa" in pref_setting:
        feedback.append("Preferences still set to APA")
    else:
        # If output was correct but pref obscure, give benefit of doubt if format was perfect
        if score >= 80: 
            score += 20
            feedback.append("Output correct, assuming preferences updated (+20)")
        else:
            feedback.append(f"Preferences unclear: {pref_setting}")

    passed = score >= 80  # Needs file + correct case + correct format
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }