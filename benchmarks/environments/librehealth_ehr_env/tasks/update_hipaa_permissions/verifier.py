#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_hipaa_permissions(traj, env_info, task_info):
    """
    Verify that the agent updated HIPAA permissions correctly.
    
    Criteria:
    1. Database reflects correct values: Voice=0 (No), Mail=0 (No), SMS=1 (Yes).
    2. Record was actually modified during the task (anti-gaming).
    3. Trajectory analysis confirms interaction with Demographics/HIPAA section.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract Values
    # Note: SQL returns might be strings "1"/"0" or ints
    final_voice = str(result.get("final_voice", "")).strip()
    final_mail = str(result.get("final_mail", "")).strip()
    final_sms = str(result.get("final_sms", "")).strip()
    record_modified = result.get("record_modified_during_task", False)

    # CRITERION 1: Record Modification (Anti-Gaming) (10 pts)
    if record_modified:
        score += 10
        feedback.append("Patient record was updated.")
    else:
        feedback.append("Patient record was NOT updated during the task.")

    # CRITERION 2: Voice Permission (No/0) (30 pts)
    # Accepts "0" or empty string (falsey in DB)
    if final_voice in ["0", "", "No"]:
        score += 30
        feedback.append("Voice permission correctly set to No.")
    else:
        feedback.append(f"Voice permission incorrect (Found: {final_voice}, Expected: 0/No).")

    # CRITERION 3: Mail Permission (No/0) (30 pts)
    if final_mail in ["0", "", "No"]:
        score += 30
        feedback.append("Mail permission correctly set to No.")
    else:
        feedback.append(f"Mail permission incorrect (Found: {final_mail}, Expected: 0/No).")

    # CRITERION 4: SMS Permission (Yes/1) (30 pts)
    if final_sms in ["1", "Yes", "Cell Only"]: 
        # "Cell Only" is sometimes an option in newer OpenEMR versions for voice, 
        # but for SMS usually it's boolean. We accept "1".
        score += 30
        feedback.append("SMS permission correctly set to Yes.")
    else:
        feedback.append(f"SMS permission incorrect (Found: {final_sms}, Expected: 1/Yes).")

    # VLM VERIFICATION (Trajectory Check)
    # If the score is high but we want to ensure they didn't just SQL inject (unlikely in this env but good practice)
    # or to give partial credit/feedback on navigation.
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Review these screenshots of an Electronic Health Record system interaction. "
            "Does the agent interact with a 'Demographics' section or a tab labeled 'HIPAA' or 'Choices'? "
            "Is there a form visible with checkboxes or yes/no options for communication preferences? "
            "Return JSON: {\"demographics_accessed\": bool, \"choices_tab_seen\": bool}"
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('demographics_accessed') or parsed.get('choices_tab_seen'):
                feedback.append("VLM confirms visual navigation to settings.")
            else:
                feedback.append("VLM could not confirm visual navigation to settings.")
        except Exception:
            pass # VLM failure shouldn't fail the task if DB is correct

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }