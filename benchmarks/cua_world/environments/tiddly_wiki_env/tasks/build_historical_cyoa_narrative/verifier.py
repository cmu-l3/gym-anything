#!/usr/bin/env python3
"""Verifier for build_historical_cyoa_narrative task."""

import json
import tempfile
import os
import re


def _check_trajectory_for_gui_interaction(traj):
    """Analyze agent trajectory for evidence of browser GUI interaction.
    Returns (has_mouse_clicks, has_keyboard_input, click_count) tuple.
    """
    mouse_clicks = 0
    keyboard_actions = 0

    if not traj:
        return False, False, 0

    for step in traj:
        action = step.get('action', '') if isinstance(step, dict) else str(step)
        action_lower = action.lower() if isinstance(action, str) else ''

        if any(kw in action_lower for kw in [
            'click', 'mouse_move', 'mouse_click', 'left_click', 'right_click',
            'double_click', 'xdotool mousemove', 'xdotool click',
            'pyautogui.click', 'pyautogui.moveto',
        ]):
            mouse_clicks += 1

        if any(kw in action_lower for kw in [
            'type', 'key', 'xdotool type', 'xdotool key',
            'pyautogui.write', 'pyautogui.press', 'pyautogui.hotkey',
            'keyboard',
        ]):
            keyboard_actions += 1

    return mouse_clicks > 0, keyboard_actions > 0, mouse_clicks


def verify_cyoa_narrative(traj, env_info, task_info):
    """Verify the CYOA narrative setup in TiddlyWiki."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cyoa_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Story Nodes Created and Tagged (Max 25 pts: 5 pts per node)
    nodes = {
        "endurance": result.get("node_endurance", {}),
        "crushed": result.get("node_crushed", {}),
        "ocean": result.get("node_ocean", {}),
        "march": result.get("node_march", {}),
        "patience": result.get("node_patience", {})
    }

    nodes_created = 0
    nodes_tagged = 0
    for name, data in nodes.items():
        if data.get("exists", False):
            nodes_created += 1
            if "StoryNode" in data.get("tags", ""):
                nodes_tagged += 1

    score += nodes_tagged * 5
    if nodes_tagged == 5:
        feedback_parts.append("All 5 StoryNodes created and tagged correctly")
    else:
        feedback_parts.append(f"{nodes_created}/5 nodes created, {nodes_tagged}/5 tagged properly")

    # 2. Check Aliased Links (Max 45 points)
    # Define flexible regex patterns that tolerate whitespace variations
    def check_link(text, display_regex, target_title):
        if not text:
            return False
        # Matches [[Display Text|Target Title]]
        pattern = r'\[\[\s*' + display_regex + r'\s*\|\s*' + re.escape(target_title) + r'\s*\]\]'
        return bool(re.search(pattern, text, re.IGNORECASE))

    endurance_text = nodes["endurance"].get("text", "")
    crushed_text = nodes["crushed"].get("text", "")
    ocean_text = nodes["ocean"].get("text", "")
    march_text = nodes["march"].get("text", "")

    # Link: Endurance -> Ocean (10 pts)
    if check_link(endurance_text, r'Order the men onto the ice', 'Ocean Camp'):
        score += 10
        feedback_parts.append("Link: Endurance -> Ocean verified")
    else:
        feedback_parts.append("FAIL: Link Endurance -> Ocean missing or incorrect")

    # Link: Endurance -> Crushed (10 pts)
    if check_link(endurance_text, r'Remain aboard the trapped vessel', 'Ship Crushed'):
        score += 10
        feedback_parts.append("Link: Endurance -> Crushed verified")
    else:
        feedback_parts.append("FAIL: Link Endurance -> Crushed missing or incorrect")

    # Link: Crushed -> Ocean (10 pts)
    if check_link(crushed_text, r'Evacuate immediately to the ice', 'Ocean Camp'):
        score += 10
        feedback_parts.append("Link: Crushed -> Ocean verified")
    else:
        feedback_parts.append("FAIL: Link Crushed -> Ocean missing or incorrect")

    # Links: Ocean -> March / Ocean -> Patience (10 pts total, 5 each)
    ocean_links_score = 0
    if check_link(ocean_text, r'March toward Paulet Island', 'Paulet Island March'):
        ocean_links_score += 5
    if check_link(ocean_text, r'Establish a semi-permanent camp', 'Patience Camp'):
        ocean_links_score += 5
    score += ocean_links_score
    if ocean_links_score == 10:
        feedback_parts.append("Links from Ocean Camp verified")
    elif ocean_links_score == 5:
        feedback_parts.append("Partial links from Ocean Camp found")
    else:
        feedback_parts.append("FAIL: Links from Ocean Camp missing")

    # Link: March -> Patience (5 pts)
    if check_link(march_text, r'Abandon the march and make camp', 'Patience Camp'):
        score += 5
        feedback_parts.append("Link: March -> Patience verified")
    else:
        feedback_parts.append("FAIL: Link March -> Patience missing or incorrect")

    # 3. Historical Content Check (Max 10 pts)
    # Check if they included some of the descriptive text, not just the links
    content_matches = 0
    if "beset" in endurance_text.lower(): content_matches += 1
    if "terrifying" in crushed_text.lower(): content_matches += 1
    if "abandon" in ocean_text.lower(): content_matches += 1
    if "exhausted" in march_text.lower(): content_matches += 1
    if "wait" in nodes["patience"].get("text", "").lower(): content_matches += 1

    if content_matches >= 4:
        score += 10
        feedback_parts.append("Historical content text verified")
    elif content_matches >= 2:
        score += 5
        feedback_parts.append("Partial historical content found")
    else:
        feedback_parts.append("FAIL: Missing required historical narrative text")

    # 4. Default Tiddler Configured (Max 20 pts)
    default_text = result.get("default_tiddlers", "").strip()
    if default_text == "[[Endurance Expedition]]" or default_text == "Endurance Expedition":
        score += 20
        feedback_parts.append("Default tiddler configured correctly")
    elif "Endurance Expedition" in default_text and "GettingStarted" not in default_text:
        score += 15
        feedback_parts.append("Default tiddler configured with minor formatting differences")
    else:
        feedback_parts.append(f"FAIL: Default tiddlers incorrect ('{default_text}')")

    # Check for anti-gaming: Ensure agent used the GUI and didn't just dump files
    gui_save = result.get('gui_save_detected', False)
    has_clicks, has_keys, _ = _check_trajectory_for_gui_interaction(traj)

    if not gui_save and not (has_clicks and has_keys):
        feedback_parts.append("WARNING: No GUI interactions detected. Possible programmatic bypassing.")
        score = int(score * 0.8)  # 20% penalty for purely programmatic bypassing of UI expectations

    key_criteria_met = (nodes_created >= 4) and ("Endurance Expedition" in default_text)
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }