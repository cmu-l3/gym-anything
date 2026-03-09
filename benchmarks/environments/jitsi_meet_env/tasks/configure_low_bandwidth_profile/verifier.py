#!/usr/bin/env python3
import json
import os
import re
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

def verify_low_bandwidth_profile(traj, env_info, task_info):
    """
    Verify that Jitsi Meet was configured for low bandwidth.
    
    Criteria:
    1. config.js: startAudioOnly == true (30 pts)
    2. config.js: constraints.video.height.ideal/max == 360 (30 pts)
    3. Service Restarted: Web container uptime < task time (20 pts)
    4. Visual Verification: Evidence screenshot shows audio-only state (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    score = 0
    feedback = []
    
    # Read Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # =========================================================
    # 1 & 2. Analyze Config File
    # =========================================================
    config_correct = False
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix=".js")
    try:
        copy_from_env(result["config_file_path"], temp_config.name)
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
            
        # Check startAudioOnly: true
        # Matches "startAudioOnly: true" or "startAudioOnly : true" etc.
        if re.search(r'startAudioOnly\s*:\s*true', config_content):
            score += 30
            feedback.append("Config: startAudioOnly enabled (30/30)")
        else:
            feedback.append("Config: startAudioOnly NOT enabled (0/30)")

        # Check resolution constraints
        # Look for video constraint block
        # We look for ideal: 360 and max: 360 within the constraints object
        # This is a heuristic regex check
        constraints_pattern = r'constraints\s*[:=]\s*\{[^}]*video\s*:\s*\{[^}]*height\s*:\s*\{[^}]*\}'
        
        # Simplified check: just look for the keys in the file, assuming they were added to constraints
        # A tighter check would parse the JS, but regex is usually sufficient for simple edits
        ideal_360 = re.search(r'ideal\s*:\s*360', config_content)
        max_360 = re.search(r'max\s*:\s*360', config_content)
        
        if ideal_360 and max_360:
            score += 30
            feedback.append("Config: Resolution constraints set to 360p (30/30)")
        elif ideal_360 or max_360:
            score += 15
            feedback.append("Config: Partial resolution constraints found (15/30)")
        else:
            feedback.append("Config: Resolution constraints missing or incorrect (0/30)")
            
    except Exception as e:
        feedback.append(f"Config analysis failed: {e}")
    finally:
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)

    # =========================================================
    # 3. Verify Service Restart
    # =========================================================
    if result.get("container_restarted", False):
        score += 20
        feedback.append("System: Web container restarted successfully (20/20)")
    else:
        feedback.append("System: Web container was NOT restarted (0/20)")

    # =========================================================
    # 4. Visual Verification (VLM)
    # =========================================================
    evidence_exists = result.get("evidence_exists", False)
    vlm_score = 0
    
    if evidence_exists:
        # Get evidence image
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        try:
            copy_from_env(result["evidence_file_path"], temp_img.name)
            
            # Use VLM to check for Audio Only state
            # Prompts check for: Avatar visible (instead of video), Mic mute/unmute, Camera disabled icon
            prompt = """
            Analyze this screenshot of a Jitsi Meet meeting.
            Does the participant appear to be in 'Audio Only' mode?
            Look for:
            1. An avatar or initial displayed in the center instead of a camera feed.
            2. The camera/video button in the toolbar appearing disabled, crossed out, or red.
            3. No live video feed visible.
            
            Return JSON: {"audio_only": boolean, "reason": string}
            """
            
            vlm_res = query_vlm(prompt=prompt, image=temp_img.name)
            
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("audio_only", False):
                    vlm_score = 20
                    feedback.append("Visual: Evidence shows Audio Only mode (20/20)")
                else:
                    feedback.append(f"Visual: Evidence does NOT show Audio Only mode. Reason: {parsed.get('reason')} (0/20)")
            else:
                feedback.append("Visual: VLM analysis failed (0/20)")
                
        except Exception as e:
            feedback.append(f"Visual analysis error: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        feedback.append("Visual: No evidence screenshot found (0/20)")

    score += vlm_score

    # Final Pass Logic
    passed = score >= 80  # Requires Config + Restart + (Evidence OR Config Perfection)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }