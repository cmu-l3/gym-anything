#!/usr/bin/env python3
"""
Verifier for add_bottom_navigation task.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_add_bottom_navigation(traj, env_info, task_info):
    """
    Verify the addition of Bottom Navigation Component.
    
    Scoring:
    - Dependencies added: 10 pts
    - Fragment classes exist (3): 15 pts
    - Layout files exist (3): 10 pts
    - Navigation graph valid (3 destinations): 15 pts
    - Menu file valid (3 items): 10 pts
    - Activity layout (NavHost + BottomNav): 15 pts
    - MainActivity wiring: 10 pts
    - Build Success: 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    score = 0
    feedback = []

    # 1. Check Dependencies (10 pts)
    bg_content = result.get('build_gradle_content', '')
    has_nav_frag = 'navigation-fragment-ktx' in bg_content
    has_nav_ui = 'navigation-ui-ktx' in bg_content
    
    if has_nav_frag and has_nav_ui:
        score += 10
        feedback.append("Dependencies added (10/10)")
    elif has_nav_frag or has_nav_ui:
        score += 5
        feedback.append("Partial dependencies added (5/10)")
    else:
        feedback.append("Missing navigation dependencies (0/10)")

    # 2. Check Fragments (15 pts)
    frags = [result.get('frag_home_exists'), result.get('frag_dash_exists'), result.get('frag_sett_exists')]
    frag_count = sum(1 for f in frags if f)
    score += frag_count * 5
    feedback.append(f"Fragments created: {frag_count}/3 ({frag_count*5}/15)")

    # 3. Check Layouts (10 pts)
    layouts = [result.get('lay_home_exists'), result.get('lay_dash_exists'), result.get('lay_sett_exists')]
    lay_count = sum(1 for l in layouts if l)
    if lay_count == 3:
        score += 10
    else:
        score += int(lay_count * 3.33)
    feedback.append(f"Fragment layouts created: {lay_count}/3")

    # 4. Navigation Graph (15 pts)
    nav_content = result.get('nav_graph_content', '')
    dest_count = len(re.findall(r'<fragment', nav_content))
    if dest_count >= 3:
        score += 15
        feedback.append("Navigation graph has 3+ destinations (15/15)")
    elif dest_count > 0:
        score += 5
        feedback.append(f"Navigation graph incomplete ({dest_count} destinations) (5/15)")
    else:
        feedback.append("Navigation graph missing/empty (0/15)")

    # 5. Menu (10 pts)
    menu_content = result.get('menu_content', '')
    item_count = len(re.findall(r'<item', menu_content))
    if item_count >= 3:
        score += 10
        feedback.append("Bottom nav menu has 3+ items (10/10)")
    else:
        feedback.append(f"Bottom nav menu has {item_count} items (0/10)")

    # 6. Activity Layout (15 pts)
    act_xml = result.get('activity_main_content', '')
    has_nav_host = 'androidx.fragment.app.FragmentContainerView' in act_xml or 'fragment' in act_xml
    has_bottom_nav = 'com.google.android.material.bottomnavigation.BottomNavigationView' in act_xml
    
    if has_nav_host and has_bottom_nav:
        score += 15
        feedback.append("Activity layout correct (15/15)")
    elif has_nav_host or has_bottom_nav:
        score += 7
        feedback.append("Activity layout partially correct (7/15)")
    else:
        feedback.append("Activity layout missing components (0/15)")

    # 7. MainActivity Wiring (10 pts)
    act_kt = result.get('main_activity_content', '')
    if 'setupWithNavController' in act_kt:
        score += 10
        feedback.append("MainActivity wiring found (10/10)")
    else:
        feedback.append("MainActivity setupWithNavController missing (0/10)")

    # 8. Build Success (15 pts)
    if result.get('build_success', False):
        score += 15
        feedback.append("Build successful (15/15)")
    else:
        feedback.append("Build failed or not attempted (0/15)")

    passed = score >= 70 and dest_count >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }