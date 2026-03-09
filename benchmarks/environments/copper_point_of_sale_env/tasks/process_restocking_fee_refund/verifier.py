#!/usr/bin/env python3
"""
Verifier for process_restocking_fee_refund task in Copper POS.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_restocking_fee_refund(traj, env_info, task_info):
    """
    Verify the restocking fee refund task.
    
    Primary Verification (VLM):
    - Did the agent create the item?
    - Did the agent process a refund?
    - CRITICAL: Did the agent manually enter ~492.99?
    
    Secondary Verification (System):
    - Was the app running?
    - Were data files modified?
    """
    
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # 2. Load metadata
    metadata = task_info.get('metadata', {})
    expected_refund = metadata.get('expected_refund_amount', 492.99)
    
    # 3. Read system result from container
    # Note: Path is C:\workspace\task_result.json in Windows, usually mapped or accessible via copy_from_env
    # The copy_from_env might expect a unix-style path even for Windows containers depending on the implementation,
    # or a specific format. Assuming standard access:
    
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Try Windows path first, then fallback
        try:
            copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        except:
            copy_from_env("/workspace/task_result.json", temp_file.name)
            
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        # We continue, as VLM is primary, but we penalize for missing system evidence
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 4. Score Calculation
    score = 0
    feedback_parts = []
    
    # System Checks (20 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("App was running.")
    else:
        feedback_parts.append("App not running.")
        
    if result.get('data_files_modified', False):
        score += 10
        feedback_parts.append("Data files modified.")
    else:
        feedback_parts.append("No data saved.")

    # VLM Checks (80 pts)
    # We need to query the VLM using the trajectory
    # Since we can't directly import gym_anything here in the output text, 
    # we assume the standard `query_vlm` function is available or we mock the check logic.
    # In a real implementation, this would use `env_info['api'].query_vlm(...)` or similar.
    # Here we define the prompt and logic that the framework would execute.
    
    # NOTE: In the 'Example 5' verifier, the VLM query is implemented inside the verifier.
    # We will assume a `query_vlm` callable is passed in env_info or we return a spec for it.
    # If not available, we can't fully verify.
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        feedback_parts.append("VLM verification unavailable.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}
        
    # Get frames
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    
    # VLM Prompt 1: Refund Calculation (CRITICAL)
    calc_prompt = f"""
    Review these screenshots of a Point of Sale interaction.
    The user is supposed to process a refund for a 'Dell UltraSharp Monitor'.
    The original price was 579.99.
    The user must MANUALLY edit the refund amount to exactly {expected_refund} (deducting a fee).
    
    Look for a 'Refund' or 'Return' dialog box or screen.
    
    Question: Is there any screenshot showing the Refund Amount field being edited to a value close to {expected_refund}?
    Also, look for the text 'Open box' or '15% fee' in any notes field.
    
    Return JSON:
    {{
        "refund_amount_edited": boolean,
        "seen_value": number or null,
        "notes_added": boolean,
        "transaction_completed": boolean
    }}
    """
    
    try:
        vlm_resp = query_vlm(images=frames, prompt=calc_prompt)
        vlm_data = vlm_resp.get('parsed', {})
        
        # Score VLM results
        if vlm_data.get('refund_amount_edited'):
            val = vlm_data.get('seen_value')
            if val and abs(float(val) - expected_refund) < 1.0:
                score += 40
                feedback_parts.append(f"VLM verified correct refund amount ({val}).")
            else:
                score += 20
                feedback_parts.append(f"VLM saw refund edit, but value {val} unclear/incorrect.")
        else:
            feedback_parts.append("VLM did not see manual refund amount edit.")
            
        if vlm_data.get('notes_added'):
            score += 10
            feedback_parts.append("VLM verified notes added.")
            
        if vlm_data.get('transaction_completed'):
            score += 10
            feedback_parts.append("VLM verified transaction completion.")
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append("Error during VLM analysis.")

    # VLM Prompt 2: Final State
    final_prompt = """
    Is the 'Transactions' list visible in this screenshot?
    Does it show a recent refund transaction (negative amount or red text)?
    """
    try:
        final_resp = query_vlm(images=[final_frame], prompt=final_prompt)
        if "yes" in final_resp.get('text', '').lower():
            score += 20
            feedback_parts.append("Final state shows transactions.")
    except:
        pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }