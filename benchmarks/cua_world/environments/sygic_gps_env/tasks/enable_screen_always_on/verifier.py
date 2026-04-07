#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import re
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_screen_always_on(traj, env_info, task_info):
    """
    Verify that the agent enabled 'Keep screen on' in Sygic GPS.
    
    Verification Strategy:
    1. Config File Check (Primary): Analyze SharedPreferences XMLs for 'screen on' keys set to true.
    2. System State Check (Secondary): Check dumpsys for FLAG_KEEP_SCREEN_ON or wake locks.
    3. VLM Verification (Tertiary): Analyze trajectory to verify UI navigation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Create temp dir for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        # =================================================================
        # 1. Fetch Artifacts
        # =================================================================
        local_artifacts = os.path.join(temp_dir, "artifacts")
        os.makedirs(local_artifacts, exist_ok=True)
        
        # Try to pull the whole artifacts folder
        # Note: Depending on implementation, copy_from_env might copy a directory or single file.
        # We'll try to copy specific expected files.
        
        try:
            # Copy result JSON
            copy_from_env("/sdcard/task_artifacts/task_result.json", os.path.join(local_artifacts, "task_result.json"))
            
            # Copy dumpsys logs
            copy_from_env("/sdcard/task_artifacts/dumpsys_window.txt", os.path.join(local_artifacts, "dumpsys_window.txt"))
            copy_from_env("/sdcard/task_artifacts/dumpsys_power.txt", os.path.join(local_artifacts, "dumpsys_power.txt"))
            
            # Copy prefs (Recursive copy might not be supported, so we might need to list or assume names)
            # Since we don't know exact filenames, we'll try to copy the directory or key files if possible.
            # Assuming copy_from_env supports directory copy:
            copy_from_env("/sdcard/task_artifacts/final_prefs", os.path.join(local_artifacts, "prefs"))
        except Exception as e:
            logger.warning(f"Error copying artifacts: {e}")

        score = 0
        feedback = []
        passed = False
        
        # =================================================================
        # 2. Analyze SharedPreferences (30 Points)
        # =================================================================
        prefs_dir = os.path.join(local_artifacts, "prefs")
        setting_found = False
        
        # Keywords to look for in XML keys
        target_keys = ["screen", "display", "awake", "lock", "sleep"]
        
        if os.path.exists(prefs_dir):
            for filename in os.listdir(prefs_dir):
                if filename.endswith(".xml"):
                    try:
                        tree = ET.parse(os.path.join(prefs_dir, filename))
                        root = tree.getroot()
                        
                        for child in root:
                            key = child.get("name", "").lower()
                            value = child.get("value", "").lower()
                            
                            # Check booleans inside tags like <boolean name="..." value="..." />
                            if child.tag == "boolean":
                                if any(k in key for k in target_keys) and value == "true":
                                    setting_found = True
                                    feedback.append(f"Found enabled setting: '{key}' in {filename}")
                                    break
                                    
                            # Check strings inside tags like <string>...</string>
                            elif child.tag == "string":
                                text = child.text.lower() if child.text else ""
                                if any(k in key for k in target_keys) and (text == "true" or text == "on" or text == "1"):
                                    setting_found = True
                                    feedback.append(f"Found enabled setting: '{key}' in {filename}")
                                    break
                    except Exception as e:
                        logger.warning(f"Failed to parse {filename}: {e}")
                
                if setting_found:
                    break
        
        if setting_found:
            score += 30
        else:
            feedback.append("Could not confirm setting change in config files (might be binary or database)")

        # =================================================================
        # 3. Analyze System State (Wake Locks) (30 Points)
        # =================================================================
        wake_lock_active = False
        
        # Check Window Manager flags
        window_dump_path = os.path.join(local_artifacts, "dumpsys_window.txt")
        if os.path.exists(window_dump_path):
            with open(window_dump_path, 'r') as f:
                content = f.read()
                # FLAG_KEEP_SCREEN_ON value is 0x00000080
                if "FLAG_KEEP_SCREEN_ON" in content or "screenOn=true" in content:
                    wake_lock_active = True
                    feedback.append("System Window Manager reports FLAG_KEEP_SCREEN_ON active")
        
        # Check Power Manager if window check failed
        if not wake_lock_active:
            power_dump_path = os.path.join(local_artifacts, "dumpsys_power.txt")
            if os.path.exists(power_dump_path):
                with open(power_dump_path, 'r') as f:
                    content = f.read()
                    if "SCREEN_BRIGHT_WAKE_LOCK" in content and "com.sygic.aura" in content:
                        wake_lock_active = True
                        feedback.append("System Power Manager reports active Wake Lock for Sygic")

        if wake_lock_active:
            score += 30
        else:
            feedback.append("No active system wake lock detected (App might not be in nav mode or setting failed)")

        # =================================================================
        # 4. VLM Trajectory Verification (40 Points)
        # =================================================================
        # Use VLM to verify the agent actually navigated the menus
        
        frames = sample_trajectory_frames(traj, n=6)
        
        vlm_prompt = """
        You are verifying a task in a GPS navigation app.
        The user goal is to ENABLE "Keep screen on" (or "Prevent screen lock").
        
        Review these screenshots from the agent's session.
        1. Did the agent open a 'Settings' menu?
        2. Did the agent find a section related to 'Display', 'View', or 'Power'?
        3. Is there visual evidence of toggling a switch related to 'Screen on' / 'Lock'?
        4. Does the final screenshot show the agent returned to the map?
        
        Respond in JSON:
        {
            "settings_opened": boolean,
            "display_section_found": boolean,
            "toggle_interaction": boolean,
            "returned_to_map": boolean,
            "confidence": 0.0 to 1.0
        }
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_score = 0
        
        if vlm_result and isinstance(vlm_result, dict):
            parsed = vlm_result.get("result", {})
            if isinstance(parsed, str):
                try:
                    # Attempt to parse if returned as string
                    import json
                    # extract json block
                    match = re.search(r'\{.*\}', parsed, re.DOTALL)
                    if match:
                        parsed = json.loads(match.group(0))
                except:
                    parsed = {}

            if parsed.get("settings_opened"): vlm_score += 10
            if parsed.get("display_section_found"): vlm_score += 10
            if parsed.get("toggle_interaction"): vlm_score += 10
            if parsed.get("returned_to_map"): vlm_score += 10
            
            feedback.append(f"VLM Analysis: {parsed}")
        else:
            feedback.append("VLM verification failed or returned invalid format")
            
        score += vlm_score

        # =================================================================
        # Final Decision
        # =================================================================
        # Pass if:
        # 1. Config OR Wake Lock confirmed (Technical proof)
        # 2. AND Score >= 60
        
        technical_proof = setting_found or wake_lock_active
        passed = technical_proof and (score >= 60)
        
        if not technical_proof:
            feedback.append("FAILED: Could not verify setting change via config files or system flags.")

        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback)
        }