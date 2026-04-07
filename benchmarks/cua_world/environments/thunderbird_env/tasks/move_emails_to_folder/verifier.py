#!/usr/bin/env python3
"""
Verifier for move_emails_to_folder task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. Anti-gaming file modification timestamps check
2. Programmatic analysis of Budget_Reviews mbox (File checks: sizes and internal subjects/senders)
3. Programmatic analysis of Inbox mbox (Checking that targets are deleted/moved)
4. Trajectory VLM checks (Validating visual work flow to ensure manual process vs hidden scripting)
"""
import json
import tempfile
import os
import mailbox
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_mbox(mbox_path):
    """Safely parse mbox file directly."""
    if not os.path.exists(mbox_path):
        return []
    messages = []
    try:
        mbox = mailbox.mbox(mbox_path)
        for message in mbox:
            messages.append(message)
        mbox.close()
    except Exception as e:
        logger.error(f"Error parsing mbox: {e}")
    return messages

def email_is_active(msg):
    """Check X-Mozilla-Status to determine if an email is marked as deleted by Thunderbird."""
    status = msg.get('X-Mozilla-Status', '0000')
    try:
        status_int = int(status, 16)
        # 0x0008 or 0x0009 indicates deleted/expunged
        if status_int & 0x0008:
            return False
    except (ValueError, TypeError):
        pass
    return True

def verify_emails_moved(traj, env_info, task_info):
    # Enforce standard execution copy mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subjects = metadata.get('expected_subjects', [
        "Q3 Budget Review - Marketing Department",
        "Q3 Budget Review - Engineering Costs",
        "Q3 Budget Review - Sales Projections",
        "Q3 Budget Review - Operations Summary",
        "Q3 Budget Review - HR and Recruiting"
    ])
    expected_sender = metadata.get('expected_sender', 'sarah.chen@acmefinancial.com').lower()

    # Provide temporary destinations
    task_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    budget_mbox_file = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    inbox_mbox_file = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')

    score = 0
    feedback_parts = []
    
    try:
        # Retrieve needed artifacts
        copy_from_env("/tmp/task_result.json", task_result_file.name)
        with open(task_result_file.name, 'r') as f:
            result = json.load(f)
            
        copy_from_env("/tmp/result_budget_reviews_mbox", budget_mbox_file.name)
        copy_from_env("/tmp/result_inbox_mbox", inbox_mbox_file.name)
        
        # 1. Anti-gaming check (file must have been modified during the agent's work cycle)
        modified_during_task = result.get('file_modified_during_task', False)
        budget_mbox_size = result.get('budget_mbox_size', 0)
        
        if budget_mbox_size == 0:
            return {"passed": False, "score": 0, "feedback": "Budget_Reviews folder is empty (0 bytes). Do Nothing detected."}
            
        if modified_during_task:
            score += 10
            feedback_parts.append("Budget_Reviews folder modified during task (+10)")
        else:
            feedback_parts.append("Warning: Folder not modified during task time window (+0)")

        # 2. Parse Budget_Reviews mbox for accurate success targets
        budget_messages = parse_mbox(budget_mbox_file.name)
        found_subjects = set()
        correct_senders = 0
        active_in_budget = 0
        
        for msg in budget_messages:
            if not email_is_active(msg):
                continue
            active_in_budget += 1
            subject = msg.get('Subject', '').strip()
            from_addr = msg.get('From', '').lower()
            
            # Record matching subjects found in destination
            for expected in expected_subjects:
                if expected.lower() in subject.lower():
                    found_subjects.add(expected)
                    break
                    
            # Record accurate senders
            if expected_sender in from_addr:
                correct_senders += 1

        for expected in expected_subjects:
            if expected in found_subjects:
                score += 10
                feedback_parts.append(f"Found: {expected.split(' - ')[-1]} (+10)")
            else:
                feedback_parts.append(f"Missing: {expected.split(' - ')[-1]}")
                
        if correct_senders == len(found_subjects) and correct_senders > 0:
            score += 10
            feedback_parts.append("All moved emails have correct sender (+10)")
            
        # Check that no non-target emails were accidentally moved
        if active_in_budget == len(expected_subjects) and len(found_subjects) == len(expected_subjects):
            score += 10
            feedback_parts.append("Budget_Reviews contains EXACTLY the target emails (+10)")
        elif active_in_budget > len(expected_subjects):
            feedback_parts.append(f"Budget_Reviews contains {active_in_budget} emails (expected {len(expected_subjects)}). Extra emails moved (+0).")
            
        # 3. Parse Inbox mbox to ensure the targets were actually cleared/moved
        inbox_messages = parse_mbox(inbox_mbox_file.name)
        inbox_active_targets = 0
        
        for msg in inbox_messages:
            if not email_is_active(msg):
                continue
            subject = msg.get('Subject', '').strip()
            from_addr = msg.get('From', '').lower()
            
            is_target = False
            for expected in expected_subjects:
                if expected.lower() in subject.lower() and expected_sender in from_addr:
                    is_target = True
                    break
            
            if is_target:
                inbox_active_targets += 1
                
        if inbox_active_targets == 0:
            score += 20
            feedback_parts.append("Inbox no longer contains the target emails (+20)")
        else:
            feedback_parts.append(f"Inbox still contains {inbox_active_targets} active target emails.")

        # 4. Trajectory checking (VLM Validation)
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_prompt = (
                    "You are verifying an agent moving emails in Mozilla Thunderbird. "
                    "Look at these sequential screenshots covering the agent's full episode. "
                    "Do you see the agent selecting multiple emails containing 'Q3 Budget Review' "
                    "and attempting to move them (via drag-and-drop or context menu) to the 'Budget_Reviews' folder? "
                    "Respond with valid JSON mapping to booleans: {\"emails_selected\": true/false, \"move_action_seen\": true/false}"
                )
                vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("emails_selected") and parsed.get("move_action_seen"):
                        score += 10
                        feedback_parts.append("VLM verified visual selection and move workflow (+10)")
                    elif parsed.get("emails_selected"):
                        score += 5
                        feedback_parts.append("VLM verified email selection (+5)")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed or unavailable: {e}")
            pass

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification encountered system error: {str(e)}"}
    finally:
        # Guarantee cleanup of unlinked resources
        for tmp_f in [task_result_file, budget_mbox_file, inbox_mbox_file]:
            if os.path.exists(tmp_f.name):
                try:
                    os.unlink(tmp_f.name)
                except Exception:
                    pass

    # Safety clamp maximum score strictly to 100
    final_score = min(100, score)
    
    # Core Success Rule: Minimum points earned, minimum 3 distinct targets moved, and original Inbox strictly cleared of targets
    passed = len(found_subjects) >= 3 and inbox_active_targets == 0 and final_score >= 60
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }