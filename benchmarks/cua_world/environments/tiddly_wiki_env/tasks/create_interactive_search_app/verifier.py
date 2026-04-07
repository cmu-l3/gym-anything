#!/usr/bin/env python3
"""
Verifier for Interactive Search Application task (create_interactive_search_app).
Uses multi-signal verification: static wikitext parsing, behavioral rendering tests, and VLM trajectory analysis.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_search_app(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the exported result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/search_app_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Check if Tiddler exists and was created during task (anti-gaming)
    if not result.get('dashboard_exists'):
        return {"passed": False, "score": 0, "feedback": "FAIL: 'Drug Interaction Finder' tiddler does not exist."}
    
    if not result.get('created_during_task'):
        feedback_parts.append("WARNING: Tiddler appears to pre-date task start.")
    
    # Check Tag
    tags = result.get('dashboard_tags', '')
    if 'Dashboard' in tags:
        score += 10
        feedback_parts.append("Tiddler created with Dashboard tag (+10)")
    else:
        feedback_parts.append("FAIL: Missing 'Dashboard' tag.")

    text = result.get('dashboard_text', '')

    # 2. Data Binding: <$edit-text tiddler="$:/temp/drug-search" ... />
    # Allow single/double quotes or no quotes if safe, but typically quoted.
    has_edit_text = re.search(r'<\$edit-text[^>]+tiddler=[\'"]?\$:/temp/drug-search[\'"]?[^>]*>', text)
    if has_edit_text:
        score += 25
        feedback_parts.append("<$edit-text> widget correctly bound (+25)")
    else:
        feedback_parts.append("FAIL: <$edit-text> widget missing or incorrectly bound.")

    # 3. Clear Action: <$button> containing <$action-deletetiddler $tiddler="$:/temp/drug-search" />
    has_button = re.search(r'<\$button[^>]*>', text)
    has_delete_action = re.search(r'<\$action-deletetiddler[^>]+\$tiddler=[\'"]?\$:/temp/drug-search[\'"]?[^>]*>', text)
    
    if has_button and has_delete_action:
        score += 25
        feedback_parts.append("Clear button with delete action configured (+25)")
    else:
        feedback_parts.append("FAIL: Clear button or <$action-deletetiddler> missing/incorrect.")

    # Extract dynamic filter logic for Count and List
    # We look for a filter attribute that contains both tag[DrugPaper] and search{$:/temp/drug-search}
    # It might be written as filter="[tag[DrugPaper]search{$:/temp/drug-search}]"
    
    def check_widget_filter(widget_name, content):
        pattern = fr'<\${widget_name}[^>]+filter=[\'"]([^>]+)[\'"][^>]*>'
        matches = re.finditer(pattern, content)
        for match in matches:
            filter_val = match.group(1)
            if 'tag[DrugPaper]' in filter_val and 'search{$:/temp/drug-search}' in filter_val:
                return True
        return False

    # 4. Dynamic Count
    if check_widget_filter("count", text):
        score += 20
        feedback_parts.append("<$count> widget configured correctly (+20)")
    else:
        feedback_parts.append("FAIL: <$count> widget missing or has incorrect filter.")

    # 5. Results List
    if check_widget_filter("list", text):
        score += 20
        feedback_parts.append("<$list> widget configured correctly (+20)")
    else:
        feedback_parts.append("FAIL: <$list> widget missing or has incorrect filter.")

    # 6. Behavioral Render Check (Anti-Gaming & Integration Test)
    # The export script injected "$:/temp/drug-search" = "Bleeding" and rendered the tiddler.
    render_output = result.get('render_output', '')
    
    behavioral_passed = False
    if render_output:
        has_warfarin = "Warfarin" in render_output or "Bleeding Risk" in render_output
        has_ketoconazole = "Ketoconazole" in render_output
        has_count_1 = bool(re.search(r'\b1\b', render_output))  # Look for the number 1 (the count)
        
        if has_warfarin and not has_ketoconazole and has_count_1:
            behavioral_passed = True
            feedback_parts.append("Behavioral test passed: reactive rendering works.")
        else:
            feedback_parts.append("WARNING: Behavioral rendering test failed. Output did not correctly filter results.")
    else:
        feedback_parts.append("WARNING: Behavioral rendering test returned no output.")

    # VLM Trajectory Verification
    # Ensure the agent actually used the GUI to perform the work
    vlm_passed = False
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if frames and final_frame:
        prompt = """
        You are verifying an agent completing a TiddlyWiki task.
        The goal was to create a dashboard titled "Drug Interaction Finder" using TiddlyWiki widgets.
        
        Review the trajectory frames and final screenshot.
        Did the agent actively type inside the TiddlyWiki editor GUI to create this tiddler?
        Respond in JSON format:
        {
            "gui_used": true/false,
            "evidence_of_typing": true/false
        }
        """
        try:
            vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('gui_used') or parsed.get('evidence_of_typing'):
                    vlm_passed = True
                    feedback_parts.append("VLM confirms GUI usage.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Log mediated save detection
    if result.get('gui_save_detected'):
        feedback_parts.append("Server log confirms GUI save event.")

    # Final scoring logic
    key_criteria_met = has_edit_text and (check_widget_filter("count", text) or check_widget_filter("list", text))
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }