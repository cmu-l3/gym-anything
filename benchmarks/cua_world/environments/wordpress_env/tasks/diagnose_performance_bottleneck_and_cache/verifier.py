#!/usr/bin/env python3
"""
Verifier for diagnose_performance_bottleneck_and_cache task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. Rogue plugin deactivated or deleted (20 pts) - REQUIRED
  2. Essential plugin (wordpress-importer) kept active (10 pts)
  3. WP Super Cache installed and active (15 pts) - REQUIRED
  4. WP_CACHE constant enabled in wp-config via settings (15 pts)
  5. Performance target met (< 1.5s load time) (10 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  6. Process verification (15 pts): Frames show agent investigating plugins,
     deactivating the rogue one, and installing/configuring WP Super Cache.
  7. Final state verification (10 pts): Final frame shows cache settings page or clean plugins list.
  8. Cross-validation (5 pts): DB/files agree with VLM.

Pass threshold: 70 points AND rogue plugin disabled AND WP Super Cache active.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent troubleshooting a slow WordPress site.

The agent should progress through:
1. Navigating to the Plugins page to investigate
2. Deactivating a suspicious plugin (WP Social Share Pro)
3. Navigating to Add New Plugin and searching for/installing 'WP Super Cache'
4. Activating WP Super Cache
5. Visiting the WP Super Cache Settings page to enable caching

Assess:
1. WORKFLOW_COMPLETED: Did the agent deactivate a plugin and install a caching plugin?
2. DEACTIVATION_OBSERVED: Is there evidence of deactivating "WP Social Share Pro"?
3. CACHE_CONFIG_OBSERVED: Are the WP Super Cache settings visible with the user enabling caching?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes across these steps?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "deactivation_observed": true/false,
    "cache_config_observed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress performance troubleshooting task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. CACHE_SETTINGS_VISIBLE: Is the WP Super Cache settings page or Plugins list visible?
3. SUCCESS_INDICATORS: Are there success messages visible (e.g. "Caching enabled", "Plugin deactivated", "Plugin activated")?
4. ERROR_INDICATORS: Are there any error messages visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "cache_settings_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_performance_and_cache(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/perf_task_result.json", temp_result.name)
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

    rogue = result.get('rogue_plugin', {})
    essential = result.get('essential_plugin', {})
    cache = result.get('cache_plugin', {})
    config = result.get('config', {})
    perf = result.get('performance', {})

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    rogue_disabled = False
    cache_active = False

    # 1. Rogue plugin deactivated/deleted (20 pts)
    if not rogue.get('active', True):
        score += 20
        rogue_disabled = True
        status = "deleted" if not rogue.get('installed', False) else "deactivated"
        feedback_parts.append(f"Rogue plugin successfully {status}")
    else:
        feedback_parts.append("FAIL: Rogue plugin is still active")

    # 2. Essential plugin kept active (10 pts)
    if essential.get('active', False):
        score += 10
        feedback_parts.append("Essential plugin retained")
    else:
        feedback_parts.append("FAIL: Essential plugin was disabled (blind deactivation)")

    # 3. Cache plugin active (15 pts)
    if cache.get('active', False):
        score += 15
        cache_active = True
        feedback_parts.append("WP Super Cache is active")
    else:
        feedback_parts.append("FAIL: WP Super Cache is not active")

    # 4. Cache Configured (15 pts)
    if config.get('wp_cache_enabled', False):
        score += 15
        feedback_parts.append("Caching successfully enabled in config")
    else:
        feedback_parts.append("FAIL: Caching not fully enabled (WP_CACHE is missing)")

    # 5. Performance target met (10 pts)
    if perf.get('target_met', False):
        score += 10
        feedback_parts.append(f"Performance target met ({perf.get('load_time_seconds', 0)}s)")
    else:
        feedback_parts.append(f"FAIL: Site still slow ({perf.get('load_time_seconds', 0)}s)")

    details['programmatic_score'] = score

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0

    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)

            # Trajectory Process (15 points)
            process_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            if process_res:
                if process_res.get("workflow_completed", False):
                    vlm_score += 5
                if process_res.get("deactivation_observed", False):
                    vlm_score += 5
                if process_res.get("cache_config_observed", False):
                    vlm_score += 5
                details['vlm_process'] = process_res

            # Final State (10 points)
            final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            if final_res:
                if final_res.get("admin_visible", False):
                    vlm_score += 5
                if final_res.get("cache_settings_visible", False) or final_res.get("success_indicators", False):
                    vlm_score += 5
                details['vlm_final'] = final_res

            # Cross-validation (5 points)
            if rogue_disabled and cache_active and process_res and process_res.get("meaningful_progression", False):
                vlm_score += 5

            score += vlm_score
            details['vlm_score'] = vlm_score
            feedback_parts.append(f"VLM verified workflow (+{vlm_score} pts)")

        except Exception as e:
            logger.warning(f"VLM checks failed: {e}")
            feedback_parts.append("VLM verification skipped/failed")
    else:
        # If VLM is not available, scale programmatic score to 100
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("VLM unavailable - programmatic score scaled")

    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    passed = score >= 70 and rogue_disabled and cache_active

    if passed:
        feedback = f"SUCCESS: { ' | '.join(feedback_parts) }"
    else:
        feedback = f"FAILED: { ' | '.join(feedback_parts) }"

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "details": details
    }