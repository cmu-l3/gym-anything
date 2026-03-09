#!/usr/bin/env python3
"""
Verifier for import_database_dump task.

Criteria:
1. Database 'acmecorp_chinook' must exist and have tables (10 pts)
2. Core tables (Artist, Track) must have correct row counts (+/- 5%) (30 pts)
3. Specific data integrity check (ArtistId 1 == AC/DC) (20 pts)
4. Anti-gaming: Tables must have been created/modified during task (20 pts)
5. VLM: Visual verification of workflow (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_database_dump(traj, env_info, task_info):
    """
    Verify the database import task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tables = metadata.get('expected_tables', 11)
    
    # Load result JSON
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
    
    # ------------------------------------------------------------------
    # 1. Database Existence & Structure (10 pts)
    # ------------------------------------------------------------------
    db_exists = result.get('db_exists', False)
    final_table_count = result.get('final_table_count', 0)
    
    if db_exists and final_table_count >= 1:
        score += 10
        feedback_parts.append(f"Database exists with {final_table_count} tables")
    else:
        feedback_parts.append("Database empty or missing")
        return {"passed": False, "score": 0, "feedback": "Failed: Database not populated"}

    # ------------------------------------------------------------------
    # 2. Data Volume Integrity (30 pts)
    # ------------------------------------------------------------------
    row_counts = result.get('row_counts', {})
    
    # Artist count (Exp: ~275)
    artists = row_counts.get('Artist', 0)
    if 260 <= artists <= 290:
        score += 10
        feedback_parts.append(f"Artist count correct ({artists})")
    else:
        feedback_parts.append(f"Artist count mismatch ({artists})")
        
    # Track count (Exp: ~3503)
    tracks = row_counts.get('Track', 0)
    if 3300 <= tracks <= 3700:
        score += 10
        feedback_parts.append(f"Track count correct ({tracks})")
    else:
        feedback_parts.append(f"Track count mismatch ({tracks})")
        
    # Table completeness
    if final_table_count >= expected_tables:
        score += 10
        feedback_parts.append("All tables present")
    elif final_table_count >= 5:
        score += 5
        feedback_parts.append("Some tables present")

    # ------------------------------------------------------------------
    # 3. Data Content Integrity (20 pts)
    # ------------------------------------------------------------------
    check_value = result.get('check_value', "")
    expected_value = metadata.get('check_value_expected', "AC/DC")
    
    if check_value == expected_value:
        score += 20
        feedback_parts.append("Data integrity verified (AC/DC)")
    elif check_value and expected_value.lower() in check_value.lower():
        score += 15
        feedback_parts.append("Data integrity partially verified")
    else:
        feedback_parts.append(f"Data integrity check failed (Got: '{check_value}')")

    # ------------------------------------------------------------------
    # 4. Anti-Gaming: Activity Check (20 pts)
    # ------------------------------------------------------------------
    modified_during_task = result.get('tables_modified_during_task', False)
    
    if modified_during_task:
        score += 20
        feedback_parts.append("Tables modified during task window")
    else:
        feedback_parts.append("WARNING: No recent table modifications detected")

    # ------------------------------------------------------------------
    # 5. VLM Verification (20 pts)
    # ------------------------------------------------------------------
    # Verify the visual workflow using trajectory frames
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of a user interacting with Virtualmin database management.\n"
            "1. Did the user navigate to 'Edit Databases' or database list?\n"
            "2. Did the user upload/execute a SQL file or use an 'Import' feature?\n"
            "3. Are there any visible error messages?\n"
            "Respond with JSON: {\"workflow_visible\": bool, \"errors\": bool, \"score\": int 0-20}"
        )
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_data = vlm_result.get('parsed', {})
        
        if vlm_data.get('workflow_visible', False):
            score += 20
            feedback_parts.append("Visual workflow verified")
        else:
            # Fallback if VLM is unsure but data is correct
            if score >= 60:
                score += 10
                feedback_parts.append("Workflow unclear but data correct")
            else:
                feedback_parts.append("Workflow not verified")
    else:
        feedback_parts.append("No screenshots available for VLM")

    # Final check
    passed = score >= 70 and modified_during_task and (final_table_count > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }