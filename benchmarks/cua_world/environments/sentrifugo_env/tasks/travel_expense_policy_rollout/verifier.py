#!/usr/bin/env python3
"""
Verifier for travel_expense_policy_rollout task.

Evaluates multi-step configuration of Sentrifugo Expenses Module:
1. DB Check: 4 Expense Categories (10 pts each)
2. DB Check: 2 Payment Methods (10 pts each)
3. DB Check: Test Expense Request Title (15 pts) & Amount (15 pts)
4. VLM Check: Trajectory frames confirm attachment of the PDF receipt (10 pts)

Total points: 100
Pass Threshold: 70
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_te_policy_rollout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Error: copy_from_env function not available."}

    # Extract task metadata defaults
    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []

    # 1. Read programmatic DB results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported JSON result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported JSON result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Evaluate Programmatic Criteria
    categories = result.get('categories', {})
    if categories.get('intl_airfare'):
        score += 10; feedback_parts.append("Cat: Intl Airfare (10/10)")
    if categories.get('domestic_lodging'):
        score += 10; feedback_parts.append("Cat: Lodging (10/10)")
    if categories.get('client_entertainment'):
        score += 10; feedback_parts.append("Cat: Client Ent. (10/10)")
    if categories.get('conference_registration'):
        score += 10; feedback_parts.append("Cat: Conf Reg (10/10)")

    payment_methods = result.get('payment_methods', {})
    if payment_methods.get('corporate_amex'):
        score += 10; feedback_parts.append("Pay: Corp AMEX (10/10)")
    if payment_methods.get('personal_credit_card'):
        score += 10; feedback_parts.append("Pay: Personal CC (10/10)")

    request_info = result.get('expense_request', {})
    if request_info.get('title_found'):
        score += 15; feedback_parts.append("Req: Title Found (15/15)")
    else:
        feedback_parts.append("Req: Title Missing (0/15)")
        
    if request_info.get('amount_found'):
        score += 15; feedback_parts.append("Req: Amount Found (15/15)")

    # 3. Evaluate File Upload via VLM Trajectory Check
    # Only run VLM if the agent successfully got as far as creating the request
    # This saves compute if the agent failed completely early on
    if request_info.get('title_found') or request_info.get('amount_found'):
        vlm_success = False
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            query_vlm = env_info.get('query_vlm')
            if query_vlm:
                frames = sample_trajectory_frames(traj, n=6)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                prompt = (
                    "Review these screenshots of an agent navigating an HR management system. "
                    "The agent's goal was to upload an expense receipt named 'Tokyo_Flight_Receipt.pdf'. "
                    "Do these trajectory frames show clear evidence that the agent interacted with a file picker, "
                    "upload dialog, or attachment indicator specifically handling the 'Tokyo_Flight_Receipt.pdf' file? "
                    "Respond in valid JSON format only, like this: {\"pdf_attached\": true/false, \"reason\": \"your reason\"}"
                )
                
                vlm_result = query_vlm(prompt=prompt, images=images)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("pdf_attached") is True:
                        vlm_success = True
                        score += 10
                        feedback_parts.append("VLM: PDF Attachment Verified (10/10)")
                    else:
                        feedback_parts.append("VLM: PDF Attachment NOT seen in trajectory (0/10)")
                else:
                    feedback_parts.append("VLM: Error querying VLM")
            else:
                feedback_parts.append("VLM: query_vlm not available")
        except ImportError:
            feedback_parts.append("VLM: gym_anything.vlm import failed")
        except Exception as e:
            feedback_parts.append(f"VLM Exception: {e}")
    else:
        feedback_parts.append("VLM: Skipped (Request not submitted)")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }