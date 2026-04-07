#!/usr/bin/env python3
"""Verifier for create_data_entry_form task."""

import json
import tempfile
import os
import re
import base64
import logging
import sys
from pathlib import Path

# Try importing VLM functions
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    pass # Will be handled gracefully

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_VERIFICATION_PROMPT = """You are analyzing the final state of a TiddlyWiki task where the user created a "Bird Sighting Entry Form".

Look at the screenshot and assess:
1. Is there a visible form with input fields for data entry (e.g., text boxes, textareas)?
2. Are there multiple distinct input fields visible (such as Species, Location, Count, Date, Habitat)?
3. Is there a submit or create button visible below or near the fields?
4. Is there a list of existing "Recent Sightings" visible below the form (e.g., you might see bird names like Red-tailed Hawk, Great Blue Heron)?

Respond in JSON format:
{
    "form_visible": true/false,
    "multiple_fields_visible": true/false,
    "submit_button_visible": true/false,
    "sightings_list_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief explanation of what you see"
}
"""

def verify_create_form(traj, env_info, task_info):
    """Verify that the Bird Sighting data entry form was created correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 1. Tiddler Exists (8 points)
    if not result.get('tiddler_exists'):
        return {"passed": False, "score": 0, "feedback": "FAIL: 'Bird Sighting Entry Form' tiddler not found"}
    
    score += 8
    feedback_parts.append("Tiddler exists")

    # Decode tiddler text
    tiddler_text_b64 = result.get('tiddler_text_b64', '')
    try:
        tiddler_text = base64.b64decode(tiddler_text_b64).decode('utf-8')
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to decode tiddler text: {e}"}

    text_lower = tiddler_text.lower()

    # 2. Edit-text widgets (12 points)
    edit_widget_count = len(re.findall(r'<\$edit-text', text_lower))
    if edit_widget_count >= 5:
        score += 12
        feedback_parts.append(f"Has edit widgets ({edit_widget_count})")
    elif edit_widget_count >= 3:
        score += 8
        feedback_parts.append(f"Has some edit widgets ({edit_widget_count})")
    elif edit_widget_count > 0:
        score += 4
        feedback_parts.append(f"Has few edit widgets ({edit_widget_count})")
    else:
        feedback_parts.append("FAIL: No <$edit-text> widgets found")

    # 3. Field bindings (Species, Location, Count, Date, Habitat) (27 points)
    if re.search(r'species', text_lower):
        score += 6
        feedback_parts.append("Species field")
    if re.search(r'location', text_lower):
        score += 6
        feedback_parts.append("Location field")
    if re.search(r'count', text_lower):
        score += 5
        feedback_parts.append("Count field")
    if re.search(r'date', text_lower):
        score += 5
        feedback_parts.append("Date field")
    if re.search(r'habitat', text_lower):
        score += 5
        feedback_parts.append("Habitat field")

    # 4. Notes / textarea (5 points)
    if re.search(r'tag=["\']?textarea["\']?', text_lower) or re.search(r'notes', text_lower):
        score += 5
        feedback_parts.append("Textarea/Notes")

    # 5. Button widget (8 points)
    if '<$button' in text_lower:
        score += 8
        feedback_parts.append("Button widget")
    else:
        feedback_parts.append("FAIL: No <$button>")

    # 6. Create action (10 points)
    if re.search(r'<\$action-createtiddler', text_lower) or re.search(r'<\$action-sendmessage[^>]+tm-new-tiddler', text_lower):
        score += 10
        feedback_parts.append("Create action")
    else:
        feedback_parts.append("FAIL: No create action")

    # 7. BirdSighting tag assigned (8 points)
    if re.search(r'tags=.*?birdsighting', text_lower) or re.search(r'birdsighting', text_lower):
        score += 8
        feedback_parts.append("BirdSighting tag assigned")

    # 8. Clear/reset mechanism (7 points)
    if re.search(r'<\$action-setfield[^>]+text=""', text_lower) or re.search(r'<\$action-deletetiddler', text_lower):
        score += 7
        feedback_parts.append("Clear/reset mechanism")
    
    # 9. Filter listing (8 points)
    if re.search(r'tag\[birdsighting\]', text_lower):
        score += 8
        feedback_parts.append("Filter for BirdSighting")

    # 10. List widget (7 points)
    if '<$list' in text_lower:
        score += 7
        feedback_parts.append("List widget")

    # VLM Verification for UI rendering
    vlm_score = 0
    if 'get_final_screenshot' in globals() and 'query_vlm' in globals():
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_result = query_vlm(prompt=VLM_VERIFICATION_PROMPT, image=final_screenshot)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("form_visible"): vlm_score += 1
                    if parsed.get("multiple_fields_visible"): vlm_score += 1
                    if parsed.get("submit_button_visible"): vlm_score += 1
                    if parsed.get("sightings_list_visible"): vlm_score += 1
                    
                    if vlm_score > 0:
                        feedback_parts.append(f"VLM Visual Check: {vlm_score}/4 features visible")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    # Check server log interaction
    if result.get("gui_save_detected"):
        feedback_parts.append("GUI save detected")

    # Pass logic: Must have the tiddler, at least 3 edit widgets, a button, and a create action
    key_criteria = (
        result.get('tiddler_exists', False) and 
        edit_widget_count >= 3 and 
        ('<$button' in text_lower) and 
        (re.search(r'<\$action-createtiddler', text_lower) or re.search(r'<\$action-sendmessage[^>]+tm-new-tiddler', text_lower))
    )

    passed = score >= 60 and key_criteria

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }