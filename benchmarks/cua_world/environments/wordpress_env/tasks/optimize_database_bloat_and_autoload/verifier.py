#!/usr/bin/env python3
"""
Verifier for optimize_database_bloat_and_autoload task.

Verification Strategy:
1. Site Health / Anti-Gaming (20 pts) - The site must return HTTP 200. If this fails, the agent likely broke core tables.
2. Orphaned Meta Removed (20 pts) - 0 orphaned rows in wp_postmeta.
3. Autoload Trap Fixed (20 pts) - _legacy_theme_cache_data exists but autoload is 'no'.
4. Transients Cleared (15 pts) - 0 rows containing '_transient_' in wp_options.
5. Revisions Deleted (15 pts) - 0 rows with post_type 'revision' in wp_posts.
6. Abandoned Table Dropped (10 pts) - wp_abandoned_plugin_logs no longer exists.

Pass threshold: 70 points AND Site Health criterion successfully met.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_database_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract results from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load verification results from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract values
    site_status = result.get('site_http_status', 'error')
    orphan_count = result.get('orphan_count', -1)
    transient_count = result.get('transient_count', -1)
    autoload_exists = result.get('autoload_exists', 0)
    autoload_val = result.get('autoload_val', 'none')
    revision_count = result.get('revision_count', -1)
    table_exists = result.get('abandoned_table_exists', -1)

    # 1. Site Health (Anti-gaming)
    site_healthy = False
    if str(site_status) == "200":
        site_healthy = True
        score += 20
        feedback_parts.append("Site is healthy (HTTP 200)")
    else:
        feedback_parts.append(f"CRITICAL: Site returned HTTP {site_status}. Core tables may have been corrupted.")
        # If the site is completely broken, we return immediately with failure.
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Orphaned Meta
    if orphan_count == 0:
        score += 20
        feedback_parts.append("Orphaned meta removed")
    elif orphan_count > 0:
        feedback_parts.append(f"Orphaned meta remaining: {orphan_count}")
    else:
        feedback_parts.append("Failed to verify orphaned meta")

    # 3. Autoload Trap
    if autoload_exists > 0:
        val_lower = str(autoload_val).strip().lower()
        if val_lower in ['no', 'off', '0']:
            score += 20
            feedback_parts.append("Autoload trap fixed (set to no)")
        else:
            feedback_parts.append(f"Autoload trap still active (value: {val_lower})")
    else:
        feedback_parts.append("Autoload trap failed (option was incorrectly DELETED completely)")

    # 4. Transients
    if transient_count == 0:
        score += 15
        feedback_parts.append("Transients cleared")
    elif transient_count > 0:
        feedback_parts.append(f"Transients remaining: {transient_count}")
    else:
        feedback_parts.append("Failed to verify transients")

    # 5. Revisions
    if revision_count == 0:
        score += 15
        feedback_parts.append("Revisions deleted")
    elif revision_count > 0:
        feedback_parts.append(f"Revisions remaining: {revision_count}")
    else:
        feedback_parts.append("Failed to verify revisions")

    # 6. Abandoned Table
    if table_exists == 0:
        score += 10
        feedback_parts.append("Abandoned table dropped")
    elif table_exists > 0:
        feedback_parts.append("Abandoned table still exists")
    else:
        feedback_parts.append("Failed to verify abandoned table")

    passed = score >= 70 and site_healthy

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }