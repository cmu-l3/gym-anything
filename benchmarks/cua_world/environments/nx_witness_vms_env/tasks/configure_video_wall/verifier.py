#!/usr/bin/env python3
"""
Verifier for configure_video_wall task.

Verifies:
1. Video Wall 'Distribution Hub SOC' exists.
2. Video Wall has 4 items with correct names and layout links.
3. 4 specific Layouts exist with correct camera assignments.
4. Report file exists and contains summary.
5. Anti-gaming: Resources created during task time.
"""

import json
import os
import sys
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_video_wall(traj, env_info, task_info):
    """
    Verify the video wall configuration task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Extract Data
    video_walls = result.get('video_walls', [])
    layouts = result.get('layouts', [])
    report_b64 = result.get('report_content_b64', "")
    report_content = base64.b64decode(report_b64).decode('utf-8').lower() if report_b64 else ""
    
    score = 0
    feedback = []
    
    # =========================================================
    # CRITERION 1: Video Wall Exists (15 pts)
    # =========================================================
    target_vw_name = "distribution hub soc"
    target_vw = None
    for vw in video_walls:
        if target_vw_name in vw.get('name', '').lower():
            target_vw = vw
            break
            
    if target_vw:
        score += 15
        feedback.append("Video Wall 'Distribution Hub SOC' created.")
    else:
        feedback.append("Video Wall 'Distribution Hub SOC' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # =========================================================
    # CRITERION 2: Video Wall Configuration (Items & Autorun)
    # =========================================================
    items = target_vw.get('items', [])
    item_count = len(items)
    
    # Check Item Count (15 pts)
    if item_count == 4:
        score += 15
        feedback.append("Video Wall has 4 items.")
    else:
        feedback.append(f"Video Wall has {item_count} items (expected 4).")

    # Check Autorun (5 pts)
    if target_vw.get('autorun', False):
        score += 5
        feedback.append("Autorun enabled.")
    else:
        feedback.append("Autorun NOT enabled.")

    # Check Item Names (10 pts)
    expected_names = ['parking view', 'entrance view', 'server room view', 'overview']
    found_names = [i.get('name', '').lower() for i in items]
    matches = sum(1 for e in expected_names if any(e in n for n in found_names))
    
    if matches == 4:
        score += 10
        feedback.append("All item names correct.")
    elif matches >= 2:
        score += 5
        feedback.append(f"Partial item names correct ({matches}/4).")
    else:
        feedback.append("Item names incorrect.")

    # =========================================================
    # CRITERION 3: SOC Layouts Created (15 pts)
    # =========================================================
    soc_layouts = [l for l in layouts if l.get('name', '').startswith('SOC -')]
    
    if len(soc_layouts) >= 4:
        score += 15
        feedback.append("4 SOC Layouts created.")
    elif len(soc_layouts) >= 2:
        score += 7
        feedback.append(f"Partial SOC Layouts created ({len(soc_layouts)}).")
    else:
        feedback.append("Insufficient SOC Layouts found.")

    # =========================================================
    # CRITERION 4: Layout Content & Linkage (25 pts total)
    # =========================================================
    # Map layout IDs to their items
    layout_map = {l['id']: l.get('items', []) for l in layouts}
    
    # Check Linkage (5 pts)
    # Verify that Video Wall items point to valid layouts in our system
    linked_layouts_valid = True
    for item in items:
        lid = item.get('layoutId')
        if not lid or lid not in layout_map:
            linked_layouts_valid = False
            break
            
    if linked_layouts_valid and item_count > 0:
        score += 5
        feedback.append("Video Wall items linked to valid layouts.")
    else:
        feedback.append("Video Wall items have invalid layout links.")

    # Check Layout Content (Cameras) (20 pts split)
    # We expect 'SOC - Overview' to have 3 items, others to have >=1
    overview_layout = next((l for l in soc_layouts if 'overview' in l.get('name','').lower()), None)
    
    # Overview check (10 pts)
    if overview_layout and len(overview_layout.get('items', [])) >= 3:
        score += 10
        feedback.append("Overview layout has 3+ cameras.")
    elif overview_layout and len(overview_layout.get('items', [])) >= 1:
        score += 5
        feedback.append("Overview layout has cameras but fewer than 3.")
    else:
        feedback.append("Overview layout missing or empty.")

    # Others check (10 pts)
    # Check if at least 3 other SOC layouts have content
    others_with_content = sum(1 for l in soc_layouts if l != overview_layout and len(l.get('items', [])) > 0)
    if others_with_content >= 3:
        score += 10
        feedback.append("Individual camera layouts populated.")
    elif others_with_content >= 1:
        score += 5
        feedback.append("Some individual layouts populated.")

    # =========================================================
    # CRITERION 5: Report File (10 pts)
    # =========================================================
    if result.get('report_exists', False) and len(report_content) > 10:
        # Check content
        required_terms = ['distribution hub soc', 'parking', 'entrance']
        term_matches = sum(1 for t in required_terms if t in report_content)
        
        if term_matches >= 2:
            score += 10
            feedback.append("Report file exists and valid.")
        else:
            score += 5
            feedback.append("Report file exists but content weak.")
    else:
        feedback.append("Report file missing.")

    # =========================================================
    # ANTI-GAMING CHECK
    # =========================================================
    # Verify resources were actually created during task (count delta)
    initial_vw = int(result.get('initial_vw_count', 0))
    current_vw = len(video_walls)
    
    if current_vw <= initial_vw:
        feedback.append("WARNING: No new Video Wall count increase detected.")
        # We don't fail immediately but penalize if score implies success
        if score > 80:
             score -= 20
             feedback.append("Penalty: Pre-existing state suspected.")

    # Final Result
    passed = (score >= 60) and (target_vw is not None) and (len(soc_layouts) >= 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }