#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_install_roof_solar_panels(traj, env_info, task_info):
    """
    Verify that solar panels were installed on the roof.
    
    Strategy:
    1. File Check (30 pts): Confirm 'solar_project.dplan' was saved and modified during task.
    2. VLM Verification (70 pts): 
       - Check trajectory for navigation to Object/Exterior library.
       - Check final screenshot for solar panels on the roof.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. File-based Verification
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: We copy from the path where export_result.ps1 saved it
        # Windows path 'C:\Users\Docker\Documents\task_result.json' maps to 
        # a specific location in the container, usually handled by copy_from_env 
        # handling absolute paths or relative to workdir. 
        # Assuming copy_from_env handles the path mapping or we use the linux mount path.
        # Based on env.json, Documents is usually at /home/ga/Documents or similar for Linux,
        # but for Windows envs, copy_from_env usually expects the path inside the guest.
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
        if result.get('output_exists'):
            score += 10
            feedback.append("Project file saved.")
            
            if result.get('file_created_during_task'):
                score += 20
                feedback.append("Project file modified during task session.")
            else:
                feedback.append("Project file was NOT modified during this session (anti-gaming fail).")
        else:
            feedback.append("Project file 'solar_project.dplan' not found.")
            
    except Exception as e:
        feedback.append(f"Failed to verify file: {str(e)}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | No screenshots available"}

    prompt = """
    You are verifying a home design task. The user was asked to install solar panels on the roof of a house.
    
    Look at the sequence of images, especially the final one.
    1. Do you see a house with a roof?
    2. Are there solar panels (dark rectangular arrays) visible ON THE ROOF?
    3. Are there at least 4 panels arranged together?
    4. Did the user navigate to a library/object selection screen during the process?
    
    Return JSON:
    {
        "house_visible": true/false,
        "solar_panels_on_roof": true/false,
        "panel_count_approx": number,
        "library_navigation_visible": true/false,
        "explanation": "..."
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_result and 'parsed' in vlm_result:
        parsed = vlm_result['parsed']
        
        if parsed.get('house_visible'):
            # Basic context check
            pass
            
        if parsed.get('solar_panels_on_roof'):
            score += 40
            feedback.append("VLM confirmed solar panels on roof.")
            
            # Bonus for quantity
            count = parsed.get('panel_count_approx', 0)
            if count >= 4:
                score += 20
                feedback.append(f"VLM detected sufficient panels ({count}).")
            elif count > 0:
                score += 10
                feedback.append(f"VLM detected some panels ({count}), but fewer than requested (4).")
        else:
            feedback.append("VLM did NOT detect solar panels on the roof.")
            
        if parsed.get('library_navigation_visible'):
            score += 10
            feedback.append("VLM observed object library navigation.")
            
    else:
        feedback.append("VLM verification failed or returned invalid format.")

    # Final logic
    passed = score >= 70  # Needs significant VLM success + file save
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }