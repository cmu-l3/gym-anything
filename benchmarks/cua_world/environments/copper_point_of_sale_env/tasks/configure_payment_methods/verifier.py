#!/usr/bin/env python3
import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_payment_methods(traj, env_info, task_info):
    """
    Verify the payment method configuration task.
    
    Strategy:
    1. VLM Verification (Primary): 
       - Check trajectory for navigation to settings.
       - Check for "Store Credit" being typed or appearing in the list.
       - Check for final state showing the Payment Methods list with the correct items.
    
    2. Registry/File Verification (Secondary/Anti-gaming):
       - Check if registry/config was modified during task window.
       - (Optional) Attempt to parse registry dump if keys are readable text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container might need handling, but copy_from_env usually handles absolute paths.
        # If copy_from_env expects a linux-style path mapping for the container, we might need to adjust.
        # Assuming the framework handles "C:\tmp\..." or we use the unix-path equivalent if strictly required.
        # For 'dockur/windows', paths are usually passed as is or via mounted volume.
        # Let's try the Windows path. If it fails, we fall back to VLM only.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Anti-Gaming: Check for activity (Files/Registry modified)
    # We check if any file in AppData or Registry was modified after task_start
    task_start = float(result_data.get('task_start', 0))
    modified = False
    
    # Check file list
    for file_info in result_data.get('files', []):
        # Parse Windows DateTime string if needed, or rely on simple check if available
        # PowerShell JSON export of DateTime can be tricky. 
        # Assuming 'LastWriteTime' is ISO-like or we skip precise parsing and rely on VLM for main score.
        # Let's check registry dump existence as basic proof of script run
        pass
        
    if result_data.get('registry_dump'):
        score += 10
        feedback_parts.append("Configuration data detected.")
    
    # 3. VLM Verification (CRITICAL)
    # We need to verify the user actually added "Store Credit" and enabled the right ones.
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for the VLM
    prompt = """
    You are verifying a Point of Sale configuration task.
    The user was asked to:
    1. Go to Options/Settings > Payment Methods.
    2. Ensure 'Cash', 'Credit Card', and 'Check' are enabled.
    3. Add a NEW payment method called 'Store Credit'.
    
    Look at the sequence of screenshots.
    
    Q1: Did the user navigate to a Settings or Options screen regarding "Payments"?
    Q2: Is "Store Credit" visible in the list of payment methods in any frame (especially later ones)?
    Q3: Are "Cash", "Credit Card", and "Check" visible/enabled?
    Q4: Did the user save the settings (clicked OK/Save)?
    
    Return JSON:
    {
      "settings_opened": boolean,
      "store_credit_added": boolean,
      "standard_methods_confirmed": boolean,
      "saved": boolean,
      "confidence": number (0-1)
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_result and isinstance(vlm_result, dict):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('settings_opened'):
            score += 20
            feedback_parts.append("Opened payment settings.")
        else:
            feedback_parts.append("Did not see payment settings opened.")
            
        if parsed.get('store_credit_added'):
            score += 40
            feedback_parts.append("Added 'Store Credit' method.")
        else:
            feedback_parts.append("'Store Credit' NOT found in screenshots.")
            
        if parsed.get('standard_methods_confirmed'):
            score += 20
            feedback_parts.append("Standard payment methods verified.")
            
        if parsed.get('saved'):
            score += 10
            feedback_parts.append("Settings saved.")
    else:
        feedback_parts.append("VLM verification failed to process images.")
    
    # Final Score Calculation
    passed = score >= 60 and ("Added 'Store Credit' method." in feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }