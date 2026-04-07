#!/usr/bin/env python3
"""
Verifier for asset_allocation_onboarding task.

Verifies:
1. Asset Categories ("Laptops", "Mobile Devices") were created.
2. The four assets were created with correct serial numbers/asset codes.
3. The four assets were mapped/allocated to the correct employee IDs.

Includes VLM-based trajectory verification to ensure UI navigation occurred
and prevent pure SQL injection gaming.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_category_exists(categories, expected_name):
    """Check if a category exists and is active in the dump."""
    for c in categories:
        for k, v in c.items():
            if k and 'name' in k.lower() and v and str(v).strip().lower() == expected_name.lower():
                # Check active status if the column exists
                is_active = c.get('isactive', c.get('status', '1'))
                if str(is_active) in ['1', 'true', 'active', 'yes']:
                    return True
    return False


def find_asset(assets, expected_serial):
    """Find an asset loosely by searching all its dictionary values for the serial string."""
    for a in assets:
        for k, v in a.items():
            if v and expected_serial.lower() in str(v).strip().lower():
                return a
    return None


def is_allocated_to(asset, allocations, users_map, expected_empid):
    """
    Check if the asset is allocated to the expected employee.
    Resolves DB internal user IDs to EmployeeIDs via the users_map.
    Checks the asset table directly, or the allocations table as a fallback.
    """
    # Find the primary DB ID for the expected employee
    expected_db_id = None
    for db_id, empid in users_map.items():
        if empid == expected_empid:
            expected_db_id = db_id
            break

    # 1. Check direct columns on the asset itself (e.g., allocated_to, user_id)
    for k, v in asset.items():
        if v and (str(v).strip() == str(expected_db_id) or str(v).strip() == expected_empid):
            return True

    # 2. Check a separate allocations table if Sentrifugo stored it there
    asset_id = asset.get('id')
    if asset_id and allocations:
        for alloc in allocations:
            if str(alloc.get('asset_id')) == str(asset_id) or str(alloc.get('assetid')) == str(asset_id):
                for k, v in alloc.items():
                    if v and (str(v).strip() == str(expected_db_id) or str(v).strip() == expected_empid):
                        return True

    return False


def verify_asset_allocation_onboarding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - framework error."}

    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    expected_categories = metadata.get('expected_categories', ["Laptops", "Mobile Devices"])
    expected_assets = metadata.get('expected_assets', [])
    pass_threshold = metadata.get('pass_threshold', 70)

    # Copy and parse result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    categories = result.get('categories', [])
    assets = result.get('assets', [])
    allocations = result.get('allocations', [])
    users = result.get('users', [])

    # Map internal DB user IDs to EMP IDs
    users_map = {}
    for u in users:
        uid = str(u.get('id', ''))
        empid = str(u.get('employeeId', ''))
        if uid and empid:
            users_map[uid] = empid

    score = 0
    feedback_parts = []

    # 1. Grade Categories (10 pts each, total 20)
    for cat_name in expected_categories:
        if check_category_exists(categories, cat_name):
            score += 10
            feedback_parts.append(f"Category '{cat_name}' found (+10).")
        else:
            feedback_parts.append(f"Category '{cat_name}' MISSING (0).")

    # 2. Grade Assets & Allocations (20 pts each, total 80)
    for expected_asset in expected_assets:
        serial = expected_asset['serial']
        target_empid = expected_asset['employeeId']
        asset_name = expected_asset.get('name', 'Asset')

        found_asset = find_asset(assets, serial)
        if not found_asset:
            feedback_parts.append(f"{asset_name} ({serial}) MISSING (0).")
            continue

        # Check if allocated correctly
        if is_allocated_to(found_asset, allocations, users_map, target_empid):
            score += 20
            feedback_parts.append(f"{asset_name} ({serial}) correctly mapped to {target_empid} (+20).")
        else:
            # Asset was created, but not allocated properly
            score += 5  # Partial credit for at least entering the asset
            feedback_parts.append(f"{asset_name} ({serial}) created but NOT correctly mapped to {target_empid} (+5).")

    # 3. VLM Trajectory Verification (Anti-Gaming)
    vlm_feedback = ""
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "Review these screenshots from a user's session operating the Sentrifugo HRMS web interface. "
                    "Does the trajectory show evidence that the user interacted with the UI to configure Asset "
                    "Categories (like Laptops/Mobile Devices) or log and allocate physical IT equipment? "
                    "Please respond with JSON matching this format: {\"used_ui\": true/false, \"reason\": \"...\"}"
                )
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                
                if vlm_resp and vlm_resp.get('parsed'):
                    used_ui = vlm_resp['parsed'].get('used_ui', True)
                    if not used_ui:
                        # Massive penalty for pure SQL injection or lack of UI usage
                        score = 0
                        vlm_feedback = " VLM Anti-Gaming Check FAILED: No evidence of UI usage for asset management."
                        logger.warning(f"VLM Anti-Gaming triggered: {vlm_resp['parsed'].get('reason')}")
                    else:
                        vlm_feedback = " VLM confirmed UI usage."
        except Exception as e:
            logger.warning(f"VLM trajectory verification encountered an error: {e}")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + vlm_feedback,
        "details": {
            "categories_found": len(categories),
            "assets_found": len(assets),
            "users_mapped": len(users_map)
        }
    }