#!/usr/bin/env python3
"""
Verifier for consolidate_case_notes task.

Criteria:
1. Gideon v. Wainwright case exists (Sanity check).
2. Exactly ONE note remains attached to the case.
3. The remaining note contains the text from Note 1 ("Sixth Amendment...").
4. The remaining note contains the text from Note 2 ("Overruled Betts v. Brady").

Scoring:
- 10 pts: Case found
- 40 pts: Exactly 1 note attached
- 25 pts: Holding text preserved
- 25 pts: Significance text preserved
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_case_notes(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
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
            "feedback": f"Failed to load result: {e}"
        }

    score = 0
    feedback = []
    
    # Metadata requirements
    req_text_1 = "Sixth Amendment" # Key phrase from holding
    req_text_2 = "Overruled Betts v. Brady" # Key phrase from significance
    
    # Check 1: Case found
    if result.get('gideon_found'):
        score += 10
        feedback.append("Target case found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Critical: 'Gideon v. Wainwright' case not found in library."}
        
    # Check 2: Note count
    note_count = result.get('note_count', -1)
    notes = result.get('notes', [])
    
    if note_count == 1:
        score += 40
        feedback.append("Correctly consolidated to exactly one note.")
    elif note_count > 1:
        feedback.append(f"Incomplete: {note_count} notes remaining (should be 1).")
    elif note_count == 0:
        feedback.append("Failed: All notes deleted.")
        
    # Check 3 & 4: Content Verification
    if notes:
        # We check the content of the single note (or combined contents if multiple exist, for partial credit)
        combined_content = " ".join([n.get('content', '') for n in notes])
        
        if req_text_1 in combined_content:
            score += 25
            feedback.append("Preserved 'Holding' text.")
        else:
            feedback.append("Missing 'Holding' text (Sixth Amendment...).")
            
        if req_text_2 in combined_content:
            score += 25
            feedback.append("Preserved 'Significance' text.")
        else:
            feedback.append("Missing 'Significance' text (Overruled Betts v. Brady...).")
    else:
        feedback.append("No note content to verify.")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }