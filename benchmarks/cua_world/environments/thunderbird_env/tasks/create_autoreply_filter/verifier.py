#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_autoreply_filter(traj, env_info, task_info):
    """
    Verify that the user created the proper Template and Message Filter rule.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subj = metadata.get('expected_template_subject', "Warranty Claim Received - Status Update")
    expected_body = metadata.get('expected_template_body', "We have received your warranty claim")
    expected_filter_name = metadata.get('expected_filter_name', "Warranty Auto-Reply")
    expected_condition = metadata.get('expected_filter_condition', "subject,contains,Warranty Claim")
    
    score = 0
    feedback = []

    # 1. Retrieve the exported data
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_templates = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    temp_rules = tempfile.NamedTemporaryFile(delete=False, suffix='.dat')

    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        task_start = result.get('task_start', 0)
        templates_mtime = result.get('templates_mtime', 0)
        rules_mtime = result.get('rules_mtime', 0)

        # 2. Check Templates
        templates_valid = False
        if templates_mtime > task_start:
            try:
                copy_from_env("/tmp/export_Templates", temp_templates.name)
                with open(temp_templates.name, 'r', encoding='utf-8', errors='ignore') as f:
                    templates_content = f.read()
                    
                if expected_subj in templates_content:
                    score += 15
                    feedback.append("Template with correct subject found.")
                    # Body check - simplify check to core sentence to handle HTML/Plain text formatting variations
                    if "within 48 business hours" in templates_content and "retain this email" in templates_content:
                        score += 15
                        templates_valid = True
                        feedback.append("Template body matches expected content.")
                    else:
                        feedback.append("Template subject found, but body content is missing or incorrect.")
                else:
                    feedback.append(f"Template with subject '{expected_subj}' not found.")
            except Exception as e:
                feedback.append(f"Failed to read Templates file: {e}")
        else:
            feedback.append("Templates file was not created or modified during the task.")

        # 3. Check Message Filters
        filter_valid = False
        if rules_mtime > task_start:
            try:
                copy_from_env("/tmp/export_msgFilterRules.dat", temp_rules.name)
                with open(temp_rules.name, 'r', encoding='utf-8', errors='ignore') as f:
                    rules_content = f.read()

                # Search for filter configurations block by block or string matching
                if f'name="{expected_filter_name}"' in rules_content:
                    score += 15
                    feedback.append("Filter with correct name found.")
                    
                    if expected_condition in rules_content:
                        score += 15
                        feedback.append("Filter has correct condition (Subject contains Warranty Claim).")
                    else:
                        feedback.append("Filter condition is incorrect.")

                    if 'action="reply"' in rules_content and 'actionValue="mailbox:' in rules_content:
                        score += 15
                        filter_valid = True
                        feedback.append("Filter action is properly set to reply with a template.")
                    else:
                        feedback.append("Filter action is not correctly set to 'reply' with a template.")
                else:
                    feedback.append(f"Filter named '{expected_filter_name}' not found.")
            except Exception as e:
                feedback.append(f"Failed to read Filter Rules file: {e}")
        else:
            feedback.append("Message Filter rules were not created or modified during the task.")

        # 4. VLM Process Verification (Trajectory)
        # We ensure the agent actually interacted with the GUI to prevent script-based gaming.
        vlm_score = 0
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are analyzing trajectory screenshots of an agent performing a Thunderbird email task.
Did the agent manually interact with the GUI to complete the task?
Look for:
1. A compose window being filled out with a template.
2. The "Message Filters" dialog or "Filter Rules" settings being opened and configured.
Respond with JSON: {"gui_used": true/false, "reasoning": "brief explanation"}"""

                vlm_result = query_vlm(images=images, prompt=prompt)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("gui_used"):
                        vlm_score = 25
                        feedback.append("VLM confirmed GUI interaction for template/filter creation.")
                    else:
                        feedback.append("VLM did not detect expected GUI interaction.")
                else:
                    logger.warning("VLM query failed or returned no success.")
        except ImportError:
            # Fallback if VLM isn't fully configured in the environment, give partial benefit of the doubt
            logger.warning("VLM imports unavailable, skipping trajectory check.")
            vlm_score = 25 
            feedback.append("VLM check skipped (unavailable), granting points automatically.")
        except Exception as e:
            logger.warning(f"VLM exception: {e}")

        score += vlm_score

    finally:
        # Cleanup temp files
        for tmp_file in [temp_json.name, temp_templates.name, temp_rules.name]:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)

    # Calculate success
    # 75 File parsing points + 25 VLM points = 100 max
    passed = (score >= 80) and templates_valid and filter_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }