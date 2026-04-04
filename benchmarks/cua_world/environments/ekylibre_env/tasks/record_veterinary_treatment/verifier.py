#!/usr/bin/env python3
import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_veterinary_treatment(traj, env_info, task_info):
    """
    Verify that the veterinary treatment was recorded correctly.
    
    Primary Verification: Database check via Rails export.
    Secondary Verification: VLM check of the process.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_animal = metadata.get('target_animal_name', 'Marguerite')
    expected_product = metadata.get('product_name', 'Curamycin')
    expected_quantity = metadata.get('quantity', 50.0)

    # 1. Retrieve DB Export Results
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_result = result_data.get('db_result', {})
    
    score = 0
    feedback_parts = []
    
    # 2. Score Database Criteria
    found_record = db_result.get('correct_record', None)
    
    if found_record:
        score += 30
        feedback_parts.append("Intervention record created successfully.")
        
        # Check Animal
        targets = found_record.get('targets', [])
        if any(expected_animal.lower() in t.lower() for t in targets):
            score += 25
            feedback_parts.append(f"Correct target animal '{expected_animal}' found.")
        else:
            feedback_parts.append(f"Target animal mismatch. Found: {targets}")

        # Check Product
        inputs = found_record.get('inputs', [])
        product_match = next((i for i in inputs if expected_product.lower() in i.get('name', '').lower()), None)
        
        if product_match:
            score += 25
            feedback_parts.append(f"Correct product '{expected_product}' found.")
            
            # Check Quantity
            qty = product_match.get('quantity', 0)
            # Allow slight float tolerance
            if abs(qty - expected_quantity) < 1.0:
                score += 10
                feedback_parts.append(f"Correct quantity {qty}.")
            else:
                feedback_parts.append(f"Quantity mismatch. Expected {expected_quantity}, got {qty}.")
        else:
            feedback_parts.append(f"Product '{expected_product}' not found in inputs.")
            
    else:
        feedback_parts.append("No matching intervention record found in database.")

    # 3. VLM Verification (Trajectory Analysis)
    # We use this to confirm the user actually interacted with the UI naturally
    # even if DB check passed, or to give partial credit if DB check failed but UI looked right.
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames and final_shot:
        vlm_prompt = f"""
        Review these screenshots of a farm management software (Ekylibre).
        The user is trying to: Record a veterinary treatment for a cow named '{expected_animal}' with '{expected_product}'.
        
        Look for:
        1. A form for 'Intervention' or 'Sanitary'/'Health'.
        2. The name '{expected_animal}' in a Target or Animal field.
        3. The product '{expected_product}' in an Input or Product field.
        4. A save action or success message.
        
        Rate confidence 0-10 that the task was attempted correctly.
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_shot], prompt=vlm_prompt).get('result', '').lower()
            
            # Simple heuristic score based on VLM response
            if "high confidence" in vlm_response or "correctly" in vlm_response:
                vlm_score = 10
            elif "medium" in vlm_response:
                vlm_score = 5
            else:
                vlm_score = 0
            
            score += vlm_score
            if vlm_score > 0:
                feedback_parts.append("Visual verification confirms workflow.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Final logic
    passed = score >= 80  # Requires Record + Animal + Product + Quantity (approx)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }