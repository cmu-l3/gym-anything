#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ev_charging(traj, env_info, task_info):
    """
    Verifies that Sygic GPS is configured for EV with specific connectors.
    
    Strategy:
    1. VLM Analysis (Primary): Check screenshots for "EV Mode", "CCS", "Type 2" enabled, "CHAdeMO" disabled.
    2. File Analysis (Secondary): Check extracted prefs for confirmation of settings changes.
    """
    
    # 1. Setup and retrieve artifacts
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Define paths in container (Android /sdcard/...)
    # Note: env.json mounts `examples/sygic_gps_env/tasks` to `/sdcard/tasks`
    # The export script writes to `/sdcard/tasks/configure_ev_charging/artifacts/`
    artifact_base = "/sdcard/tasks/configure_ev_charging/artifacts"
    
    score = 0
    feedback = []
    
    # Temporary directory for analysis
    with tempfile.TemporaryDirectory() as tmpdir:
        local_json = os.path.join(tmpdir, "task_result.json")
        local_ev_dump = os.path.join(tmpdir, "ev_prefs_dump.txt")
        local_conn_dump = os.path.join(tmpdir, "connector_prefs_dump.txt")
        
        # Copy JSON result
        try:
            copy_from_env(f"{artifact_base}/task_result.json", local_json)
            with open(local_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device."}

        # Check App Running (Basic sanity)
        if result_data.get("app_running", False):
            score += 10
            feedback.append("App was running.")
        else:
            feedback.append("App was NOT running at end of task.")

        # Copy Prefs Dumps
        ev_prefs_content = ""
        conn_prefs_content = ""
        try:
            copy_from_env(f"{artifact_base}/ev_prefs_dump.txt", local_ev_dump)
            copy_from_env(f"{artifact_base}/connector_prefs_dump.txt", local_conn_dump)
            with open(local_ev_dump, 'r') as f: ev_prefs_content = f.read().lower()
            with open(local_conn_dump, 'r') as f: conn_prefs_content = f.read().lower()
        except Exception as e:
            logger.warning(f"Could not retrieve prefs dumps: {e}")

        # ---------------------------------------------------------
        # VLM VERIFICATION (Primary Signal)
        # ---------------------------------------------------------
        
        # Get screenshots
        # We use the final screenshot captured by the script, OR the framework's final state
        # Framework trajectory is preferred for history
        
        final_img = get_final_screenshot(traj)
        traj_frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """
        You are verifying a task in Sygic GPS Navigation.
        The user was asked to:
        1. Enable "EV Mode" (Electric Vehicle mode).
        2. Configure filters to ENABLE "CCS (Combo 2)" and "Type 2".
        3. DISABLE "CHAdeMO".
        
        Review the screenshots (chronological order) and the final screen.
        
        Check for:
        1. Is there evidence of 'EV Mode' being active or selected? (e.g., 'Electric' fuel type, 'EV' settings).
        2. Is the 'Connector type' or 'Charging' filter screen visible?
        3. Are 'CCS' and 'Type 2' checked/toggled ON?
        4. Is 'CHAdeMO' unchecked/toggled OFF?
        
        Return JSON:
        {
            "ev_mode_detected": boolean,
            "connector_screen_seen": boolean,
            "ccs_enabled": boolean,
            "type2_enabled": boolean,
            "chademo_disabled": boolean,
            "confidence": "high/medium/low",
            "reasoning": "string"
        }
        """
        
        vlm_res = query_vlm(
            images=traj_frames + [final_img],
            prompt=prompt
        )
        
        vlm_data = vlm_res.get("parsed", {})
        
        # Score VLM findings
        if vlm_data.get("ev_mode_detected"):
            score += 20
            feedback.append("VLM: EV Mode detected.")
            
        if vlm_data.get("connector_screen_seen"):
            score += 10
            feedback.append("VLM: Connector settings screen visited.")
            
        if vlm_data.get("ccs_enabled"):
            score += 20
            feedback.append("VLM: CCS connector enabled.")
            
        if vlm_data.get("type2_enabled"):
            score += 20
            feedback.append("VLM: Type 2 connector enabled.")
            
        if vlm_data.get("chademo_disabled"):
            score += 10
            feedback.append("VLM: CHAdeMO connector disabled.")

        # ---------------------------------------------------------
        # PREFS VERIFICATION (Secondary Signal)
        # ---------------------------------------------------------
        # If VLM is unsure, prefs might save us. Or valid prefs reinforce VLM.
        
        prefs_score = 0
        
        # Check EV Mode keywords
        if "electric" in ev_prefs_content or "ev" in ev_prefs_content:
            prefs_score += 5
            feedback.append("Prefs: 'Electric' setting found in config.")

        # Check Connectors
        # We look for "true" or "1" near the connector names if possible, but simple existence 
        # of the key often implies it was modified/set. 
        # Sygic often stores enabled lists.
        if "ccs" in conn_prefs_content or "combo" in conn_prefs_content:
            prefs_score += 5
            feedback.append("Prefs: CCS configuration found.")
            
        # Add prefs score (capped at 10 extra points)
        score = min(100, score + prefs_score)

    # ---------------------------------------------------------
    # FINAL VERDICT
    # ---------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": vlm_data
    }