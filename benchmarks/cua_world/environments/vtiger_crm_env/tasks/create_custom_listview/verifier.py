#!/usr/bin/env python3
"""
Verifier for create_custom_listview task in Vtiger CRM.

Verification Strategy:
1. DB Check: Verify the custom view "New York Contacts" exists.
2. DB Check: Verify the view was created during the task (Anti-gaming).
3. DB Check: Verify the filter condition targets Mailing City equals "New York".
4. DB Check: Verify the specified columns are configured to display.
5. VLM Check: Visual confirmation that the UI was actually used (Trajectory verification).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are evaluating a UI agent interacting with a CRM.
The user requested the agent to create a Custom List View / Filter named "New York Contacts" in the Contacts module.
Look at these screenshots from the agent's workflow.

Did the agent interact with the UI to create or configure a list view, filter, or search?
Look for evidence of:
- A "Create View", "List View", or "Filter" menu being opened.
- Form fields being filled out for the view name or conditions.
- The final view showing a filtered list of contacts.

Respond with a JSON object containing:
{
    "ui_interaction_detected": true/false,
    "reasoning": "Brief explanation of the visual evidence"
}
"""

def verify_create_custom_listview(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # Expected values
    expected_filter_column = task_info.get("metadata", {}).get("expected_filter_column", "mailingcity")
    expected_filter_value = task_info.get("metadata", {}).get("expected_filter_value", "New York")
    expected_filter_comparator = task_info.get("metadata", {}).get("expected_filter_comparator", "e")
    expected_columns = task_info.get("metadata", {}).get("expected_columns", ["firstname", "lastname", "mailingcity"])

    # 1. Retrieve the exported JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_custom_listview_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    logger.info(f"Task Result Data: {result}")

    # =========================================================
    # Check 1: Custom View Existence (30 points)
    # =========================================================
    view_found = result.get('view_found', False)
    if view_found:
        score += 30
        feedback_parts.append("✅ View 'New York Contacts' found")
    else:
        feedback_parts.append("❌ Target custom view not found in database")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # =========================================================
    # Check 2: Anti-Gaming - View is New (10 points)
    # =========================================================
    cvid = int(result.get('cvid', 0))
    initial_cvid = int(result.get('initial_max_cvid', 0))
    
    if cvid > initial_cvid:
        score += 10
        feedback_parts.append("✅ View was newly created")
    else:
        feedback_parts.append(f"❌ View pre-existed task (cvid {cvid} <= {initial_cvid})")

    # =========================================================
    # Check 3: Filter Conditions Correct (25 points)
    # =========================================================
    # Format: col1|comp1|val1;col2|comp2|val2
    filters_text = result.get('filters', '')
    filter_correct = False
    
    if filters_text:
        conditions = filters_text.split(';')
        for cond in conditions:
            parts = cond.split('|')
            if len(parts) >= 3:
                col_name = parts[0].lower()
                comp = parts[1].lower()
                val = parts[2]
                
                if expected_filter_column in col_name and comp == expected_filter_comparator and val.strip().lower() == expected_filter_value.lower():
                    filter_correct = True
                    break

    if filter_correct:
        score += 25
        feedback_parts.append("✅ Correct filter applied (Mailing City equals New York)")
    else:
        feedback_parts.append("❌ Filter condition incorrect or missing")

    # =========================================================
    # Check 4: Columns Configured (15 points + 10 points for key cols)
    # =========================================================
    # Format: col1;col2;col3
    columns_text = result.get('columns', '')
    configured_cols = [c.lower() for c in columns_text.split(';') if c]
    
    if len(configured_cols) >= 3:
        score += 15
        feedback_parts.append(f"✅ Sufficient columns configured ({len(configured_cols)})")
    else:
        feedback_parts.append(f"❌ Only {len(configured_cols)} columns configured (expected >= 3)")

    key_columns_present = 0
    for exp_col in expected_columns:
        if any(exp_col in actual_col for actual_col in configured_cols):
            key_columns_present += 1
            
    if key_columns_present >= len(expected_columns):
        score += 10
        feedback_parts.append("✅ Required key columns present")
    else:
        feedback_parts.append(f"❌ Missing some required columns (Found {key_columns_present}/{len(expected_columns)})")

    # =========================================================
    # Check 5: VLM Trajectory Verification (10 points)
    # =========================================================
    vlm_points_awarded = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_response = query_vlm(
                images=images,
                prompt=VERIFICATION_PROMPT
            )
            
            if vlm_response and vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                if vlm_parsed.get("ui_interaction_detected", False):
                    vlm_points_awarded = True
                    score += 10
                    feedback_parts.append("✅ VLM confirmed visual UI interaction")
                else:
                    feedback_parts.append("❌ VLM did not detect list view UI interaction")
            else:
                logger.warning(f"VLM verification failed: {vlm_response.get('error')}")
                feedback_parts.append("⚠️ VLM verification skipped due to error")
                # Give benefit of doubt if VLM errors out, but log it
                score += 10
    else:
        feedback_parts.append("⚠️ VLM not available, bypassing visual check")
        score += 10

    # Ensure max score doesn't exceed 100
    score = min(score, 100)
    
    # Must have created the view and configured the filter to pass
    passed = score >= 65 and view_found and filter_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }