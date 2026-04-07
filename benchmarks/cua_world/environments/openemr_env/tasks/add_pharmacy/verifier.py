#!/usr/bin/env python3
"""
Verifier for Add Pharmacy task in OpenEMR

Verifies that a new pharmacy was correctly added to the system with:
- Correct name (containing CVS and 8472)
- Correct address (2150 Commonwealth Avenue)
- Correct location (Boston, MA 02135)
- Phone and fax numbers present
- Created during the task execution (anti-gaming)

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_pharmacy(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the pharmacy was correctly added to OpenEMR.
    
    Scoring (100 points total):
    - Pharmacy record exists with CVS/8472 in name: 25 points
    - Name fully correct (both CVS and 8472): 15 points  
    - Address correct (2150 Commonwealth): 15 points
    - City/State/Zip correct (Boston, MA, 02135): 15 points
    - Phone number present: 10 points
    - Fax number present: 10 points
    - Newly created during task (anti-gaming): 10 points
    
    Passing threshold: 70 points with pharmacy existing
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name_contains = metadata.get('expected_name_contains', ['CVS', '8472'])
    expected_address = metadata.get('address', '2150 Commonwealth Avenue')
    expected_city = metadata.get('city', 'Boston')
    expected_state = metadata.get('state', 'MA')
    expected_zip = metadata.get('zip', '02135')
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/add_pharmacy_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not read verification data: {str(e)}"
            }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "pharmacy_exists": False,
        "name_correct": False,
        "address_correct": False,
        "location_correct": False,
        "phone_present": False,
        "fax_present": False,
        "newly_created": False
    }
    
    # Extract data from result
    pharmacy_found = result.get('pharmacy_found', False)
    pharmacy = result.get('pharmacy', {})
    validation = result.get('validation', {})
    counts = result.get('pharmacy_counts', {})
    
    initial_count = counts.get('initial', 0)
    current_count = counts.get('current', 0)
    newly_created = counts.get('newly_created', False)
    
    logger.info(f"Pharmacy found: {pharmacy_found}")
    logger.info(f"Pharmacy data: {pharmacy}")
    logger.info(f"Validation: {validation}")
    logger.info(f"Counts: initial={initial_count}, current={current_count}")
    
    # =========================================================================
    # CRITERION 1: Pharmacy record exists (25 points)
    # =========================================================================
    if pharmacy_found:
        name = pharmacy.get('name', '')
        name_has_cvs = validation.get('name_has_cvs', False)
        name_has_8472 = validation.get('name_has_8472', False)
        
        if name_has_cvs or name_has_8472:
            score += 25
            subscores["pharmacy_exists"] = True
            feedback_parts.append(f"✅ Pharmacy record found: '{name}'")
        else:
            # Pharmacy exists but doesn't match expected name
            score += 10  # Partial credit
            feedback_parts.append(f"⚠️ Pharmacy found but name doesn't match: '{name}' (expected CVS #8472)")
    else:
        feedback_parts.append("❌ No matching pharmacy found in database")
        # Check if any pharmacy was added at all
        if current_count > initial_count:
            feedback_parts.append(f"   Note: {current_count - initial_count} pharmacy(ies) were added, but none match expected criteria")
        
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # =========================================================================
    # CRITERION 2: Name fully correct (15 points)
    # =========================================================================
    name_has_cvs = validation.get('name_has_cvs', False)
    name_has_8472 = validation.get('name_has_8472', False)
    
    if name_has_cvs and name_has_8472:
        score += 15
        subscores["name_correct"] = True
        feedback_parts.append("✅ Name correct: contains both 'CVS' and '8472'")
    elif name_has_cvs:
        score += 8
        feedback_parts.append("⚠️ Name partial: contains 'CVS' but missing '8472'")
    elif name_has_8472:
        score += 8
        feedback_parts.append("⚠️ Name partial: contains '8472' but missing 'CVS'")
    else:
        feedback_parts.append("❌ Name incorrect: should contain 'CVS' and '8472'")
    
    # =========================================================================
    # CRITERION 3: Address correct (15 points)
    # =========================================================================
    address_matches = validation.get('address_matches', False)
    actual_address = pharmacy.get('address', '')
    
    if address_matches:
        score += 15
        subscores["address_correct"] = True
        feedback_parts.append(f"✅ Address correct: '{actual_address}'")
    else:
        # Check for partial match
        if actual_address:
            address_lower = actual_address.lower()
            has_number = '2150' in actual_address
            has_street = 'commonwealth' in address_lower
            
            if has_number and has_street:
                score += 15
                subscores["address_correct"] = True
                feedback_parts.append(f"✅ Address correct: '{actual_address}'")
            elif has_number or has_street:
                score += 8
                feedback_parts.append(f"⚠️ Address partial: '{actual_address}' (expected: {expected_address})")
            else:
                feedback_parts.append(f"❌ Address incorrect: '{actual_address}' (expected: {expected_address})")
        else:
            feedback_parts.append(f"❌ Address missing (expected: {expected_address})")
    
    # =========================================================================
    # CRITERION 4: City/State/Zip correct (15 points)
    # =========================================================================
    city_matches = validation.get('city_matches', False)
    state_matches = validation.get('state_matches', False)
    zip_matches = validation.get('zip_matches', False)
    
    actual_city = pharmacy.get('city', '')
    actual_state = pharmacy.get('state', '')
    actual_zip = pharmacy.get('zip', '')
    
    location_points = 0
    location_details = []
    
    if city_matches:
        location_points += 5
        location_details.append("city ✓")
    else:
        location_details.append(f"city: '{actual_city}' (expected: {expected_city})")
    
    if state_matches:
        location_points += 5
        location_details.append("state ✓")
    else:
        location_details.append(f"state: '{actual_state}' (expected: {expected_state})")
    
    if zip_matches:
        location_points += 5
        location_details.append("zip ✓")
    else:
        location_details.append(f"zip: '{actual_zip}' (expected: {expected_zip})")
    
    score += location_points
    
    if location_points == 15:
        subscores["location_correct"] = True
        feedback_parts.append(f"✅ Location correct: {expected_city}, {expected_state} {expected_zip}")
    elif location_points > 0:
        feedback_parts.append(f"⚠️ Location partial ({location_points}/15): {', '.join(location_details)}")
    else:
        feedback_parts.append(f"❌ Location incorrect: {', '.join(location_details)}")
    
    # =========================================================================
    # CRITERION 5: Phone number present (10 points)
    # =========================================================================
    phone_present = validation.get('phone_present', False)
    actual_phone = pharmacy.get('phone', '')
    
    if phone_present:
        score += 10
        subscores["phone_present"] = True
        feedback_parts.append(f"✅ Phone present: {actual_phone}")
    elif actual_phone:
        score += 5  # Partial credit for any phone value
        feedback_parts.append(f"⚠️ Phone entered but may be incomplete: '{actual_phone}'")
    else:
        feedback_parts.append("❌ Phone number missing")
    
    # =========================================================================
    # CRITERION 6: Fax number present (10 points)
    # =========================================================================
    fax_present = validation.get('fax_present', False)
    actual_fax = pharmacy.get('fax', '')
    
    if fax_present:
        score += 10
        subscores["fax_present"] = True
        feedback_parts.append(f"✅ Fax present: {actual_fax}")
    elif actual_fax:
        score += 5  # Partial credit for any fax value
        feedback_parts.append(f"⚠️ Fax entered but may be incomplete: '{actual_fax}'")
    else:
        feedback_parts.append("❌ Fax number missing")
    
    # =========================================================================
    # CRITERION 7: Newly created during task (10 points) - Anti-gaming
    # =========================================================================
    if newly_created:
        score += 10
        subscores["newly_created"] = True
        feedback_parts.append(f"✅ Pharmacy newly added (count: {initial_count} → {current_count})")
    else:
        feedback_parts.append(f"⚠️ Could not confirm pharmacy was newly created (count: {initial_count} → {current_count})")
    
    # =========================================================================
    # Final evaluation
    # =========================================================================
    
    # Key criteria: pharmacy must exist with some correct attributes
    key_criteria_met = subscores["pharmacy_exists"] and (
        subscores["name_correct"] or 
        subscores["address_correct"] or 
        subscores["location_correct"]
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Generate summary
    if passed:
        summary = f"✅ PASS: Pharmacy successfully added (Score: {score}/100)"
    else:
        summary = f"❌ FAIL: Pharmacy not correctly added (Score: {score}/100)"
    
    full_feedback = summary + "\n\n" + "\n".join(feedback_parts)
    
    logger.info(f"Final score: {score}/100, passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback,
        "subscores": subscores,
        "details": {
            "pharmacy": pharmacy,
            "validation": validation,
            "counts": counts
        }
    }


def main():
    """Main entry point for standalone testing."""
    # Mock test data for development testing
    test_result = {
        "pharmacy_found": True,
        "pharmacy": {
            "id": "1",
            "name": "CVS Pharmacy #8472",
            "address": "2150 Commonwealth Avenue",
            "city": "Boston",
            "state": "MA",
            "zip": "02135",
            "phone": "(617) 555-0142",
            "fax": "(617) 555-0143",
            "email": "rx8472@cvs.com",
            "npi": "1234567890"
        },
        "validation": {
            "name_has_cvs": True,
            "name_has_8472": True,
            "address_matches": True,
            "city_matches": True,
            "state_matches": True,
            "zip_matches": True,
            "phone_present": True,
            "fax_present": True
        },
        "pharmacy_counts": {
            "initial": 0,
            "current": 1,
            "newly_created": True
        }
    }
    
    # Write test data to temp file
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(test_result, f)
        temp_path = f.name
    
    # Mock copy function
    def mock_copy(src, dst):
        import shutil
        shutil.copy(temp_path, dst)
    
    # Run verification
    result = verify_add_pharmacy(
        traj={},
        env_info={'copy_from_env': mock_copy},
        task_info={'metadata': {}}
    )
    
    print(result['feedback'])
    print(f"\nFinal Score: {result['score']}/100")
    print(f"Passed: {result['passed']}")
    
    # Cleanup
    os.unlink(temp_path)
    
    return 0 if result['passed'] else 1


if __name__ == "__main__":
    sys.exit(main())