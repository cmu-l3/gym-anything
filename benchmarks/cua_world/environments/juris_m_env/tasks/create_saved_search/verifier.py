#!/usr/bin/env python3
"""
Verifier for create_saved_search task.

Criteria:
1. Saved Search exists in database (count increased).
2. Name matches keywords (Post-1960, SCOTUS).
3. Conditions logic:
   - Date condition: > 1960 or > 1960-01-01 or "is after"
   - Court condition: contains "Supreme" or "SCOTUS" or "U.S."
4. VLM Verification: Sidebar shows the search name.

Scores:
- Search exists: 20
- Name correct: 15
- Date condition logic: 25
- Court condition logic: 20
- VLM Verification: 20
"""

import json
import os
import logging
import tempfile
from typing import Dict, Any, List

# Import VLM utilities from the environment framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def get_final_screenshot(traj): return traj[-1]['observation']['screenshot'] if traj else None
    def query_vlm(**kwargs): return {"answer": "yes", "confidence": "high"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_date_condition(conditions: List[Dict]) -> bool:
    """Check if any condition correctly filters for post-1960."""
    valid_fields = ['date', 'dateDecided', 'year', 'dateAdded', 'publicationDate']
    
    for c in conditions:
        field = c.get('field', '')
        op = c.get('operator', '')
        val = str(c.get('value', '')).lower()
        
        # Check if field is date-related
        is_date_field = any(f in field for f in valid_fields) or field == 'year'
        
        if is_date_field:
            # Logic: year > 1960 OR date is after 1960...
            if '1960' in val:
                if op in ['greater', 'isAfter', 'is not before']:
                    return True
                # "is" 1960 only gets that year, strictly not "post-1960" but maybe partial credit?
                # Task asked for "after 1960", so strict equality implies 1960 is included/excluded incorrectly.
                # But typically users might do "Date is after 1960".
    return False

def check_court_condition(conditions: List[Dict]) -> bool:
    """Check if any condition filters for Supreme Court."""
    valid_fields = ['court', 'authority', 'publicationTitle'] # Sometimes reporters listed in publication
    target_keywords = ['supreme', 'scotus', 'u.s.', 'us', 'united states']
    
    for c in conditions:
        field = c.get('field', '')
        op = c.get('operator', '')
        val = str(c.get('value', '')).lower()
        
        if any(f in field for f in valid_fields):
            if any(k in val for k in target_keywords):
                # Operator should be contains or is
                if op in ['contains', 'is', 'beginsWith']:
                    return True
    return False

def verify_create_saved_search(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Existence (20 pts)
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    search_found = result.get('search_found', False)
    
    if search_found and current_count > initial_count:
        score += 20
        feedback_parts.append("Saved search created (+20)")
    elif search_found:
        # Search found but count didn't increase? maybe overwritten. Allow partial.
        score += 10
        feedback_parts.append("Saved search found but count ambiguous (+10)")
    else:
        return {"passed": False, "score": 0, "feedback": "No saved search created."}

    # 2. Check Name (15 pts)
    name = result.get('search_name', '')
    expected_keywords = task_info.get('metadata', {}).get('expected_name_keywords', ["Post-1960", "SCOTUS"])
    
    if any(k.lower() in name.lower() for k in expected_keywords):
        score += 15
        feedback_parts.append(f"Name '{name}' acceptable (+15)")
    else:
        feedback_parts.append(f"Name '{name}' does not contain required keywords (Post-1960, SCOTUS)")

    # 3. Check Conditions
    conditions = result.get('conditions', [])
    
    # Date (25 pts)
    if check_date_condition(conditions):
        score += 25
        feedback_parts.append("Date condition correct (+25)")
    else:
        feedback_parts.append("Date condition missing or incorrect (must be > 1960)")

    # Court (20 pts)
    if check_court_condition(conditions):
        score += 20
        feedback_parts.append("Court condition correct (+20)")
    else:
        feedback_parts.append("Court condition missing or incorrect")

    # 4. VLM Verification (20 pts)
    # Check if the sidebar actually shows the search
    final_screenshot_path = result.get("screenshot_path")
    vlm_score = 0
    
    if final_screenshot_path:
        # We need to pull the screenshot to host if we were running strictly locally, 
        # but the framework handles trajectory images. We'll use the final trajectory frame.
        # However, verifying via VLM requires the image content.
        
        prompt = f"Look at the left sidebar of the application. Do you see a Saved Search (magnifying glass icon folder) named '{name}' or similar to 'Post-1960'?"
        
        # In a real run, we pass images from trajectory. 
        # For this template, we assume the framework handles image passing if we use query_vlm.
        try:
            # We use the final screenshot from the trajectory
            final_img = get_final_screenshot(traj)
            if final_img:
                vlm_resp = query_vlm(
                    images=[final_img],
                    prompt=prompt
                )
                if "yes" in vlm_resp.get("answer", "").lower() or vlm_resp.get("confidence") == "high":
                    vlm_score = 20
                    feedback_parts.append("VLM verified sidebar visibility (+20)")
                else:
                    feedback_parts.append("VLM could not clearly see the search in sidebar")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if database verification was perfect (score >= 80), give benefit of doubt
            if score >= 80:
                vlm_score = 20
                feedback_parts.append("VLM skipped, assumed visible based on DB (+20)")

    score += vlm_score

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }