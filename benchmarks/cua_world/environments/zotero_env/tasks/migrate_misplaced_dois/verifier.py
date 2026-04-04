#!/usr/bin/env python3
"""
Verifier for migrate_misplaced_dois task.

Scoring:
- 20 pts per paper for correct DOI in DOI field (3 papers = 60 pts)
- 10 pts per paper for cleared Extra field (3 papers = 30 pts)
- 10 pts for no "DOI:" prefix errors in DOI field
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_migrate_misplaced_dois(traj, env_info, task_info):
    """Verify metadata migration."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback_parts = []
    
    items = result.get("items", [])
    if not items:
        return {"passed": False, "score": 0, "feedback": "No items found in result"}

    prefix_error_detected = False

    for item in items:
        title = item.get("title", "Unknown")
        
        if not item.get("found"):
            feedback_parts.append(f"Paper '{title}' not found in DB")
            continue

        expected_doi = item.get("expected_doi", "").strip()
        current_doi = item.get("current_doi", "")
        current_extra = item.get("current_extra", "")

        # Check DOI
        if current_doi:
            current_doi = current_doi.strip()
            if current_doi == expected_doi:
                score += 20
                feedback_parts.append(f"✓ '{title[:20]}...' DOI fixed")
            elif expected_doi in current_doi and "DOI" in current_doi.upper():
                # User copied "DOI: " prefix
                score += 5
                prefix_error_detected = True
                feedback_parts.append(f"⚠ '{title[:20]}...' has DOI prefix error")
            else:
                feedback_parts.append(f"✗ '{title[:20]}...' wrong DOI")
        else:
            feedback_parts.append(f"✗ '{title[:20]}...' DOI empty")

        # Check Extra
        if not current_extra: # Empty or None
            score += 10
            feedback_parts.append(f"✓ '{title[:20]}...' Extra cleared")
        else:
            if "DOI" in current_extra:
                 feedback_parts.append(f"✗ '{title[:20]}...' Extra still has DOI")
            else:
                 # Maybe they left other notes? Task said "delete text from extra field"
                 # Strict check: should be empty
                 feedback_parts.append(f"✗ '{title[:20]}...' Extra not empty")

    # Bonus: Clean formatting (No "DOI:" prefix in any DOI field)
    # Only award if at least one DOI was actually filled
    filled_dois = [i for i in items if i.get("current_doi")]
    if filled_dois and not prefix_error_detected:
        score += 10
        feedback_parts.append("✓ Formatting clean (no prefixes)")

    # Threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }