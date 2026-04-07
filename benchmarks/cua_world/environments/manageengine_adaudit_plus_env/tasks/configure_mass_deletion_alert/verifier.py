#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_mass_deletion_alert(traj, env_info, task_info):
    """
    Verifies the configuration of the Mass File Deletion alert profile.
    
    Criteria:
    1. Evidence screenshot exists and was created during task (20 pts)
    2. VLM confirms 'Mass File Deletion Incident' profile name (20 pts)
    3. VLM confirms Threshold configuration (>50 in 1 min) (30 pts)
    4. VLM confirms Exclusion of 'BackupSvc' (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_evidence_path = metadata.get('evidence_path', 'C:\\workspace\\mass_deletion_alert_evidence.png')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Check File Evidence
    if result_data.get('evidence_exists') and result_data.get('evidence_created_during_task'):
        score += 20
        feedback_parts.append("Evidence screenshot created.")
    else:
        feedback_parts.append("Evidence screenshot missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": "Failed: No evidence screenshot provided."}

    # 3. Retrieve Screenshot for VLM
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(expected_evidence_path, temp_img.name)
        
        # VLM Verification
        prompt = """
        Analyze this screenshot from ManageEngine ADAudit Plus.
        I am looking for a specific Alert Profile configuration.
        
        Check for the following 3 specific details:
        1. Profile Name: Is there a profile named "Mass File Deletion Incident"?
        2. Threshold: Is there a threshold setting showing "50" events within "1" minute (or 60 seconds)?
        3. Filter/Exclusion: Is there a filter or criteria that excludes the user "BackupSvc" (e.g., "User Name != BackupSvc" or "Except BackupSvc")?
        
        Return JSON format:
        {
            "profile_name_match": true/false,
            "threshold_match": true/false,
            "exclusion_match": true/false,
            "severity_critical": true/false,
            "reasoning": "Explain what you see regarding these settings"
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, image=temp_img.name)
        
        if vlm_result.get('success'):
            analysis = vlm_result.get('parsed', {})
            
            # Profile Name (20 pts)
            if analysis.get('profile_name_match'):
                score += 20
                feedback_parts.append("Profile name verified.")
            else:
                feedback_parts.append("Profile name 'Mass File Deletion Incident' not found.")
                
            # Threshold (30 pts)
            if analysis.get('threshold_match'):
                score += 30
                feedback_parts.append("Threshold (50/1min) verified.")
            else:
                feedback_parts.append("Threshold configuration incorrect or not visible.")
                
            # Exclusion (30 pts)
            if analysis.get('exclusion_match'):
                score += 30
                feedback_parts.append("Exclusion of 'BackupSvc' verified.")
            else:
                feedback_parts.append("Exclusion of 'BackupSvc' not found.")
                
        else:
            feedback_parts.append("VLM analysis failed.")
            
    except Exception as e:
        feedback_parts.append(f"Error processing screenshot: {str(e)}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    # Final Evaluation
    passed = score >= 70  # Requires at least evidence + 2/3 configuration items
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }