#!/usr/bin/env python3
"""
Verifier for Add Immunization Lot task in OpenEMR

Verifies that a vaccine lot record was correctly added to the inventory system.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Lot record exists with correct lot number: 30 points
- Correct lot number match: 15 points
- Correct manufacturer: 15 points
- Correct expiration date: 15 points
- Quantity recorded (any positive value): 10 points
- Correct quantity (50): 5 points
- Created during task (anti-gaming): 10 points
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_immunization_lot(traj, env_info, task_info):
    """
    Verify that an immunization lot record was correctly added.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_lot = metadata.get('expected_lot_number', 'FL2024-8847')
    expected_ndc = metadata.get('expected_ndc', '49281-0421-50')
    expected_manufacturer = metadata.get('expected_manufacturer', 'Sanofi Pasteur')
    expected_expiration = metadata.get('expected_expiration', '2025-06-30')
    expected_quantity = metadata.get('expected_quantity', 50)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/immunization_lot_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "lot_record_exists": False,
            "correct_lot_number": False,
            "correct_manufacturer": False,
            "correct_expiration": False,
            "quantity_recorded": False,
            "correct_quantity": False,
            "created_during_task": False
        }
        
        # Extract data from result
        lot_found = result.get('lot_record_found', False)
        lot_record = result.get('lot_record', {})
        drug_found = result.get('drug_record_found', False)
        drug_record = result.get('drug_record', {})
        new_drug_added = result.get('new_drug_added', False)
        new_inventory_added = result.get('new_inventory_added', False)
        initial_drug_count = result.get('initial_drug_count', 0)
        current_drug_count = result.get('current_drug_count', 0)
        initial_inventory_count = result.get('initial_inventory_count', 0)
        current_inventory_count = result.get('current_inventory_count', 0)
        
        logger.info(f"Lot found: {lot_found}, Drug found: {drug_found}")
        logger.info(f"Lot record: {lot_record}")
        logger.info(f"Drug record: {drug_record}")
        logger.info(f"New records: drug={new_drug_added}, inventory={new_inventory_added}")
        
        # CRITERION 1: Lot record exists (30 points)
        if lot_found:
            score += 30
            subscores["lot_record_exists"] = True
            feedback_parts.append("✅ Lot record found in inventory")
        elif drug_found:
            # Partial credit if drug was added but lot not properly linked
            score += 15
            feedback_parts.append("⚠️ Drug record found but lot not in inventory table (partial credit)")
        elif new_drug_added or new_inventory_added:
            # Some credit for adding something
            score += 10
            feedback_parts.append("⚠️ New record added but expected lot not found")
        else:
            feedback_parts.append("❌ No lot record found in inventory")
        
        # CRITERION 2: Correct lot number (15 points)
        actual_lot = lot_record.get('lot_number', '').strip()
        if actual_lot:
            if actual_lot.upper() == expected_lot.upper():
                score += 15
                subscores["correct_lot_number"] = True
                feedback_parts.append(f"✅ Correct lot number: {actual_lot}")
            else:
                feedback_parts.append(f"❌ Lot number mismatch: expected '{expected_lot}', got '{actual_lot}'")
        else:
            feedback_parts.append("❌ Lot number not recorded")
        
        # CRITERION 3: Correct manufacturer (15 points)
        actual_manufacturer = lot_record.get('manufacturer', '').strip()
        if actual_manufacturer:
            # Flexible matching - check if expected manufacturer is contained
            if (expected_manufacturer.lower() in actual_manufacturer.lower() or 
                actual_manufacturer.lower() in expected_manufacturer.lower() or
                'sanofi' in actual_manufacturer.lower()):
                score += 15
                subscores["correct_manufacturer"] = True
                feedback_parts.append(f"✅ Correct manufacturer: {actual_manufacturer}")
            else:
                # Partial credit for having any manufacturer
                score += 5
                feedback_parts.append(f"⚠️ Manufacturer differs: expected '{expected_manufacturer}', got '{actual_manufacturer}'")
        else:
            feedback_parts.append("❌ Manufacturer not recorded")
        
        # CRITERION 4: Correct expiration date (15 points)
        actual_expiration = lot_record.get('expiration', '').strip()
        if actual_expiration:
            # Normalize date format for comparison
            exp_match = False
            try:
                # Try different date formats
                for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d-%m-%Y', '%Y/%m/%d']:
                    try:
                        actual_date = datetime.strptime(actual_expiration, fmt).date()
                        expected_date = datetime.strptime(expected_expiration, '%Y-%m-%d').date()
                        if actual_date == expected_date:
                            exp_match = True
                            break
                    except ValueError:
                        continue
                
                if not exp_match and expected_expiration in actual_expiration:
                    exp_match = True
                    
            except Exception as e:
                logger.warning(f"Date parsing error: {e}")
                if expected_expiration in actual_expiration:
                    exp_match = True
            
            if exp_match:
                score += 15
                subscores["correct_expiration"] = True
                feedback_parts.append(f"✅ Correct expiration: {actual_expiration}")
            else:
                # Partial credit for recording any expiration
                score += 5
                feedback_parts.append(f"⚠️ Expiration differs: expected '{expected_expiration}', got '{actual_expiration}'")
        else:
            feedback_parts.append("❌ Expiration date not recorded")
        
        # CRITERION 5: Quantity recorded (10 points)
        actual_quantity_str = lot_record.get('quantity', '').strip()
        if actual_quantity_str:
            try:
                actual_quantity = float(actual_quantity_str)
                if actual_quantity > 0:
                    score += 10
                    subscores["quantity_recorded"] = True
                    feedback_parts.append(f"✅ Quantity recorded: {actual_quantity}")
                    
                    # CRITERION 6: Correct quantity (5 points)
                    if abs(actual_quantity - expected_quantity) < 1:
                        score += 5
                        subscores["correct_quantity"] = True
                        feedback_parts.append(f"✅ Correct quantity: {int(actual_quantity)}")
                    else:
                        feedback_parts.append(f"⚠️ Quantity differs: expected {expected_quantity}, got {int(actual_quantity)}")
                else:
                    feedback_parts.append("⚠️ Quantity is zero or negative")
            except ValueError:
                feedback_parts.append(f"⚠️ Could not parse quantity: {actual_quantity_str}")
        else:
            feedback_parts.append("❌ Quantity not recorded")
        
        # CRITERION 7: Created during task (anti-gaming) (10 points)
        if new_inventory_added or new_drug_added:
            score += 10
            subscores["created_during_task"] = True
            new_count_msg = []
            if new_drug_added:
                new_count_msg.append(f"drugs: {initial_drug_count}→{current_drug_count}")
            if new_inventory_added:
                new_count_msg.append(f"inventory: {initial_inventory_count}→{current_inventory_count}")
            feedback_parts.append(f"✅ Record created during task ({', '.join(new_count_msg)})")
        else:
            feedback_parts.append("❌ No new records detected (possible pre-existing data or nothing added)")
        
        # VLM verification for trajectory (optional bonus verification)
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj.get('frames'):
            try:
                # Sample trajectory frames
                frames = traj.get('frames', [])
                n_frames = len(frames)
                if n_frames > 0:
                    # Sample 5 frames across trajectory
                    sample_indices = [int(i * (n_frames - 1) / 4) for i in range(5)] if n_frames >= 5 else list(range(n_frames))
                    sampled_frames = [frames[i] for i in sample_indices if i < n_frames]
                    
                    vlm_prompt = """You are verifying if an agent successfully added a vaccine lot to OpenEMR's inventory system.

Look at these screenshots showing the agent's actions and determine:
1. Did the agent navigate to an inventory or drug management area?
2. Did the agent fill out a form with drug/vaccine details?
3. Was there evidence of saving or submitting a record?
4. Did the agent appear to complete the task?

Respond in JSON format:
{
    "navigated_to_inventory": true/false,
    "filled_form": true/false,
    "saved_record": true/false,
    "task_appeared_complete": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
                    vlm_result = query_vlm(prompt=vlm_prompt, images=sampled_frames)
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('task_appeared_complete') and parsed.get('confidence') in ['medium', 'high']:
                            feedback_parts.append("✅ VLM: Task completion confirmed via trajectory")
                        elif parsed.get('filled_form'):
                            feedback_parts.append("⚠️ VLM: Form interaction detected but completion uncertain")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
        
        # Determine pass/fail
        # Must have lot record found AND be created during task for full pass
        key_criteria_met = subscores["lot_record_exists"] and subscores["created_during_task"]
        passed = score >= 60 and key_criteria_met
        
        # Alternative pass: high score even without perfect lot match
        if score >= 75:
            passed = True
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "lot_record": lot_record,
                "drug_record": drug_record,
                "expected_lot": expected_lot,
                "expected_manufacturer": expected_manufacturer,
                "expected_expiration": expected_expiration,
                "expected_quantity": expected_quantity
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - export_result.sh may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Invalid JSON in result file: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {}
        }