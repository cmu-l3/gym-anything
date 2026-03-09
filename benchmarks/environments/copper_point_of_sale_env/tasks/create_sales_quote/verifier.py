#!/usr/bin/env python3
"""
Verifier for Create Sales Quote task (Copper POS).
Uses VLM trajectory analysis + File modification timestamps.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_quote(traj, env_info, task_info):
    """
    Verifies that a sales quote was created with specific items and customer.
    
    Strategy:
    1. File System: Check if Copper POS data files were modified (proves SAVE action).
    2. VLM Trajectory:
       - Confirm 'Quote' or 'Estimate' workflow (not Sale).
       - Confirm Customer 'Greenfield Office Solutions'.
       - Confirm Line Items (Paper x20, Pen x10, Folder x8).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve Result JSON from Environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\tasks\\create_sales_quote\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Metadata Expectations
    metadata = task_info.get('metadata', {})
    expected_customer = metadata.get('customer_name', "Greenfield Office Solutions")
    expected_items = metadata.get('items', [])
    
    score = 0
    feedback_parts = []
    
    # --- CRITERION A: Data Persistence (20 pts) ---
    # We verify that the application actually wrote data to disk during the task
    if result_data.get("data_files_modified", False):
        score += 20
        feedback_parts.append("Data saved successfully (files modified).")
    else:
        feedback_parts.append("Warning: No data modification detected (Quote might not be saved).")

    # --- CRITERION B: App State (10 pts) ---
    if result_data.get("app_was_running", False):
        score += 10
    else:
        feedback_parts.append("Application was closed at end of task.")

    # --- CRITERION C: VLM Verification (70 pts) ---
    # We use a trajectory sampling to catch the moment the items were entered
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame]
    
    # Construct VLM Prompt
    item_checklist = "\n".join([f"- {item['name']} (Qty: {item['qty']})" for item in expected_items])
    
    prompt = f"""
    Analyze these screenshots of NCH Copper Point of Sale. The user is tasked with creating a SALES QUOTE (not a Sale).
    
    Please verify the following strictly:
    1. **Customer**: Is the customer set to '{expected_customer}'?
    2. **Transaction Type**: Is this clearly a 'Quote', 'Estimate', or 'Order' (look for header text)? It should NOT be a finalized 'Sale' receipt unless it's a printed quote.
    3. **Line Items**: Check for these specific items and quantities:
       {item_checklist}
    4. **Saved State**: Does the final screen imply the action was completed/saved (e.g., cleared screen after save, or success dialog)?
    
    Return a JSON object with:
    {{
        "customer_match": boolean,
        "is_quote_workflow": boolean,
        "items_correct": boolean,
        "quantities_correct": boolean,
        "saved_successfully": boolean,
        "reasoning": "string"
    }}
    """
    
    # This calls the injected VLM function provided by the framework (simulated here)
    # In a real run, `query_vlm` would be available in the global scope or passed in `env_info`
    # For this file generation, we assume standard usage of `query_vlm` if available, 
    # but since I cannot import it here, I will structure the logic assuming the output is processed.
    
    # NOTE: In the actual implementation, you would call:
    # vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    # Placeholder for logic flow:
    # Assuming vlm_result is obtained. We return the prompt string in feedback if we can't execute.
    # To make this file valid python that passes the 'exec', I will define a dummy check or rely on `env_info` having a VLM client.
    
    # Using the standard gym_anything VLM pattern if available in env_info, otherwise failing gracefully or stubbing.
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        vlm_resp = query_vlm(images=all_images, prompt=prompt)
        # Parse JSON from VLM
        try:
            # Handle potential string wrapping
            import re
            json_match = re.search(r'\{.*\}', vlm_resp, re.DOTALL)
            if json_match:
                vlm_data = json.loads(json_match.group(0))
            else:
                vlm_data = {}
            
            # Score VLM components
            if vlm_data.get("customer_match"):
                score += 15
                feedback_parts.append("Customer verified.")
            else:
                feedback_parts.append(f"Customer mismatch (Expected {expected_customer}).")
                
            if vlm_data.get("is_quote_workflow"):
                score += 15
                feedback_parts.append("Correctly identified as Quote workflow.")
            else:
                feedback_parts.append("Wrong workflow (possibly processed as Sale).")
                
            if vlm_data.get("items_correct") and vlm_data.get("quantities_correct"):
                score += 30
                feedback_parts.append("Items and quantities verified.")
            elif vlm_data.get("items_correct"):
                score += 15
                feedback_parts.append("Items correct but quantities wrong.")
            else:
                feedback_parts.append("Items mismatch.")
                
            if vlm_data.get("saved_successfully"):
                score += 10
                feedback_parts.append("Visual confirmation of save.")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing VLM response: {e}")
    else:
        # Fallback if no VLM (should not happen in prod)
        feedback_parts.append("VLM verification skipped (client not found).")
        score = 0 # Fail safe

    # Logic for Pass/Fail
    # Must have data modification OR strong visual save confirmation + Items/Customer Correct
    passed = (score >= 70) and result_data.get("data_files_modified", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }