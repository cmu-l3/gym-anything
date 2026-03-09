#!/usr/bin/env python3
"""
Verifier for configure_av_coaching_profile task.

Verifies:
1. Noise Suppression enabled (via VLM on evidence screenshot)
2. Self-view hidden (via VLM on final screenshot)
3. Workflow navigation (via VLM on trajectory frames)
4. Anti-gaming (timestamps, file existence)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_av_configuration(traj, env_info, task_info):
    """
    Verify Jitsi Meet audio/video configuration.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # CRITERION 1: File Existence & Anti-Gaming (20 Points)
    # ------------------------------------------------------------------
    
    # Noise Suppression Evidence
    if result.get('noise_evidence_exists') and result.get('noise_evidence_created_during_task'):
        score += 10
        feedback.append("Noise suppression evidence file created.")
    else:
        feedback.append("Missing or stale noise suppression evidence file.")

    # Final View Evidence
    if result.get('final_view_exists') and result.get('final_view_created_during_task'):
        score += 10
        feedback.append("Final meeting view file created.")
    else:
        feedback.append("Missing or stale final view file.")

    # Do-Nothing Check
    if not result.get('state_changed_from_initial'):
        feedback.append("WARNING: Final screenshot looks identical to initial state.")
    
    # ------------------------------------------------------------------
    # CRITERION 2: VLM Verification of Settings (80 Points)
    # ------------------------------------------------------------------
    
    # We need to copy the images out of the container to analyze them
    noise_img_path = None
    final_img_path = None
    
    if result.get('noise_evidence_exists'):
        try:
            t = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/noise_suppression_evidence.png", t.name)
            noise_img_path = t.name
        except:
            pass

    if result.get('final_view_exists'):
        try:
            t = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/av_config_final.png", t.name)
            final_img_path = t.name
        except:
            pass

    # A. Verify Noise Suppression (35 Points)
    if noise_img_path:
        ns_prompt = """
        Examine this screenshot of Jitsi Meet settings.
        1. Look for a "Noise suppression" or "Noise cancellation" option.
        2. Is the checkbox checked, the toggle colored/active, or is there text indicating it is "On" or "Enabled"?
        
        Return JSON: {"found_option": bool, "is_enabled": bool}
        """
        ns_res = query_vlm(image=noise_img_path, prompt=ns_prompt)
        
        if ns_res.get('success'):
            parsed = ns_res.get('parsed', {})
            if parsed.get('found_option') and parsed.get('is_enabled'):
                score += 35
                feedback.append("VLM confirmed Noise Suppression is ENABLED.")
            elif parsed.get('found_option'):
                feedback.append("VLM found Noise Suppression option but it appears DISABLED.")
            else:
                feedback.append("VLM could not find Noise Suppression settings in the evidence screenshot.")
        else:
            feedback.append("VLM failed to analyze noise evidence.")
            
        os.unlink(noise_img_path)
    else:
        feedback.append("Skipping Noise Suppression VLM check (no image).")

    # B. Verify Self-View Hidden (35 Points)
    # If agent didn't save final view, use the system backup or trajectory final frame
    if not final_img_path:
        # Fallback to trajectory final frame
        final_img_path = get_final_screenshot(traj)
    
    if final_img_path:
        sv_prompt = """
        Examine this screenshot of a Jitsi Meet video call.
        1. Typically, a user sees their own camera preview in a small tile (Self View), usually in a corner or filmstrip.
        2. Is the "Self View" camera tile HIDDEN?
        
        Note: If you only see the main meeting area and other participants (or empty room message) but NO small picture-in-picture of the local user, then Self View is hidden.
        
        Return JSON: {"self_view_hidden": bool}
        """
        # Note: If passing path string vs PIL object, ensure wrapper handles it. 
        # Here we assume query_vlm handles file paths or we loaded it. 
        # If get_final_screenshot returned an object, query_vlm handles it.
        
        sv_res = query_vlm(image=final_img_path, prompt=sv_prompt)
        
        if sv_res.get('success'):
            if sv_res.get('parsed', {}).get('self_view_hidden'):
                score += 35
                feedback.append("VLM confirmed Self View is HIDDEN.")
            else:
                feedback.append("VLM detected Self View is still VISIBLE.")
        
        # clean up if it was a temp file
        if isinstance(final_img_path, str) and os.path.exists(final_img_path) and "tmp" in final_img_path:
            try:
                os.unlink(final_img_path)
            except:
                pass

    # C. Trajectory Workflow Verification (10 Points)
    # Did they actually open menus?
    frames = sample_trajectory_frames(traj, n=5)
    if frames:
        traj_prompt = """
        Look at this sequence of screenshots from Jitsi Meet.
        Did the user open any settings menus, overflow menus (three dots), or audio/video configuration panels?
        
        Return JSON: {"menus_opened": bool}
        """
        traj_res = query_vlm(images=frames, prompt=traj_prompt)
        if traj_res.get('success') and traj_res.get('parsed', {}).get('menus_opened'):
            score += 10
            feedback.append("Trajectory confirms menu navigation.")
        else:
            feedback.append("Trajectory does not clearly show settings menus being accessed.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 60  # Require at least one feature verified + files created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }