#!/usr/bin/env python3
"""
Verifier for Database Prefix Security Migration task (migrate_db_prefix_security).

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. wp-config.php updated to use 'sec24_' (15 pts)
  2. Database tables renamed to 'sec24_' prefix (10 pts)
  3. Old 'wp_' tables successfully removed (5 pts)
  4. 'sec24_user_roles' exists in sec24_options table (10 pts)
  5. 'sec24_capabilities' exists in sec24_usermeta table (10 pts)
  6. Site is functional (WP-CLI loads users correctly) (20 pts) - CRITICAL

VLM checks (30 points) — using TRAJECTORY frames:
  7. Process verification (15 pts): Frames show agent editing files, executing SQL, or using a plugin to migrate DB.
  8. Final state verification (10 pts): WordPress admin is visible (no DB error).
  9. Cross-validation (5 pts): Programmatic state matches VLM evidence.

Pass threshold: 70 points AND site MUST be functional (WP_CLI_WORKS).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images."""
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent migrating a WordPress database prefix to improve security.

The agent might accomplish this by:
1. Editing the wp-config.php file in a terminal or editor.
2. Executing SQL queries via terminal, a script, or a tool like phpMyAdmin.
3. Using a WordPress security/migration plugin from the admin panel.

Assess:
1. WORKFLOW_COMPLETED: Did the agent attempt to rename database tables and edit wp-config.php?
2. DB_MODIFICATION_VISIBLE: Can you see database tables or configuration files being modified?
3. MEANINGFUL_PROGRESSION: Do the frames show a logical progression of completing this migration task?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "db_modification_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress site after a database migration task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface or frontend visible and functioning normally?
2. DATABASE_ERROR: Is there a "Error establishing a database connection" or white screen visible?
3. SUCCESS_INDICATORS: Does the site appear to be operating cleanly (no obvious PHP errors or broken styles)?

Respond in JSON format:
{
    "admin_visible": true/false,
    "database_error": true/false,
    "success_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_migrate_db_prefix_security(traj, env_info, task_info):
    """
    Verify that the database prefix was successfully migrated to 'sec24_'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # 1. Load the exported JSON result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/migrate_db_prefix_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False, "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    # ================================================================
    # PROGRAMMATIC CHECKS (Total: 70 points)
    # ================================================================
    
    config_prefix = result.get("config_prefix", "")
    wp_table_count = result.get("wp_table_count", 0)
    sec24_table_count = result.get("sec24_table_count", 0)
    options_migrated = result.get("options_migrated_count", 0) > 0
    usermeta_migrated = result.get("usermeta_migrated_count", 0) > 0
    site_functional = result.get("site_functional", False)

    # 1. Config updated (15 pts)
    if config_prefix == "sec24_":
        score += 15
        feedback_parts.append("wp-config.php prefix is 'sec24_'")
        details["config_correct"] = True
    else:
        feedback_parts.append(f"wp-config.php prefix is '{config_prefix}' (Expected: 'sec24_')")
        details["config_correct"] = False

    # 2. New tables exist (10 pts)
    if sec24_table_count >= 12: # Standard WP install has 12 core tables
        score += 10
        feedback_parts.append(f"New 'sec24_' tables exist ({sec24_table_count})")
        details["new_tables_exist"] = True
    else:
        feedback_parts.append(f"Missing 'sec24_' tables (Found {sec24_table_count})")
        details["new_tables_exist"] = False

    # 3. Old tables removed (5 pts)
    if wp_table_count == 0:
        score += 5
        feedback_parts.append("Old 'wp_' tables cleanly removed")
        details["old_tables_removed"] = True
    else:
        feedback_parts.append(f"Old 'wp_' tables still exist ({wp_table_count})")
        details["old_tables_removed"] = False

    # 4. Options migrated (10 pts)
    if options_migrated:
        score += 10
        feedback_parts.append("Options table keys migrated")
        details["options_migrated"] = True
    else:
        feedback_parts.append("Options table keys NOT migrated (sec24_user_roles missing)")
        details["options_migrated"] = False

    # 5. Usermeta migrated (10 pts)
    if usermeta_migrated:
        score += 10
        feedback_parts.append("Usermeta keys migrated")
        details["usermeta_migrated"] = True
    else:
        feedback_parts.append("Usermeta keys NOT migrated (sec24_capabilities missing)")
        details["usermeta_migrated"] = False

    # 6. Site functional (20 pts)
    if site_functional:
        score += 20
        feedback_parts.append("Site functional (WP-CLI checks passed)")
        details["site_functional"] = True
    else:
        feedback_parts.append("CRITICAL: Site broken (WP-CLI capability check failed)")
        details["site_functional"] = False

    # ================================================================
    # VLM CHECKS (Total: 30 points)
    # ================================================================
    
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            # Process verification (15 pts)
            process_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            if process_res:
                if process_res.get('workflow_completed'):
                    vlm_score += 10
                    details['vlm_workflow'] = True
                if process_res.get('db_modification_visible'):
                    vlm_score += 5
                    details['vlm_db_modification'] = True

            # Final state verification (10 pts)
            final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            if final_res:
                if not final_res.get('database_error') and final_res.get('success_indicators'):
                    vlm_score += 10
                    details['vlm_no_db_error'] = True
                    
            # Cross validation (5 pts)
            if site_functional and details.get('vlm_no_db_error'):
                vlm_score += 5
                details['vlm_cross_validated'] = True
                
            score += vlm_score
            feedback_parts.append(f"VLM Score: {vlm_score}/30")
        except Exception as e:
            logger.warning(f"VLM execution failed: {e}")
            # Give proportional fallback score if VLM fails but programmatic passes perfectly
            if site_functional and sec24_table_count >= 12 and options_migrated and usermeta_migrated:
                score += 30
                feedback_parts.append("VLM failed, awarded fallback points for perfect programmatic execution")
    else:
        # No VLM available
        if site_functional and sec24_table_count >= 12 and options_migrated and usermeta_migrated:
            score += 30
            feedback_parts.append("VLM unavailable, awarded fallback points for perfect programmatic execution")

    # ================================================================
    # FINAL EVALUATION
    # ================================================================
    
    # Must achieve at least 70 total points, and crucially, the site must be functional
    # (If the site is broken, it's a failed migration regardless of how many tables were renamed)
    passed = score >= 70 and site_functional and details.get("config_correct", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }