#!/usr/bin/env python3
"""
Verifier for custom_facility_attributes task.

Scoring (100 points total):
1. Attribute 'Generator Functional' created correctly (Name, Type=BOOLEAN/TRUE_ONLY) [20pts]
2. Attribute 'Distance...' created correctly (Name, Type=INTEGER/NUMBER) [20pts]
3. Both attributes assigned to Organisation Unit scope [20pts]
4. Bo Govt Hospital facility updated with ANY values for these attributes [10pts]
5. Correct values assigned (Generator=true/Yes, Distance=15) [30pts]
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_custom_facility_attributes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from container
    temp_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/custom_facility_attributes_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback = []

    # 1. Verify 'Generator Functional' Attribute
    attr1 = result.get('attr1_data')
    attr1_id = None
    if result.get('attr1_found') and attr1:
        # Check Name (Implicitly checked by filter in export script, but good to confirm)
        # Check Type
        val_type = attr1.get('valueType', '')
        if val_type in ['BOOLEAN', 'TRUE_ONLY']:
            score += 20
            feedback.append("Attribute 'Generator Functional' created with correct type.")
        else:
            score += 10 # Partial credit for name only
            feedback.append(f"Attribute 'Generator Functional' exists but wrong type: {val_type} (Expected BOOLEAN/YesNo).")
        
        # Check Scope
        if attr1.get('organisationUnitAttribute') is True:
            score += 10
            feedback.append("Attribute 'Generator Functional' correctly assigned to Org Units.")
        else:
            feedback.append("Attribute 'Generator Functional' NOT assigned to Org Units.")
            
        attr1_id = attr1.get('id')
    else:
        feedback.append("Attribute 'Generator Functional' not found.")

    # 2. Verify 'Distance...' Attribute
    attr2 = result.get('attr2_data')
    attr2_id = None
    if result.get('attr2_found') and attr2:
        val_type = attr2.get('valueType', '')
        # DHIS2 has INTEGER, INTEGER_POSITIVE, INTEGER_NEGATIVE, NUMBER, UNIT_INTERVAL
        if val_type in ['INTEGER', 'INTEGER_POSITIVE', 'NUMBER']:
            score += 20
            feedback.append("Attribute 'Distance...' created with correct type.")
        else:
            score += 10
            feedback.append(f"Attribute 'Distance...' exists but wrong type: {val_type} (Expected Integer).")
            
        # Check Scope
        if attr2.get('organisationUnitAttribute') is True:
            score += 10
            feedback.append("Attribute 'Distance...' correctly assigned to Org Units.")
        else:
            feedback.append("Attribute 'Distance...' NOT assigned to Org Units.")
            
        attr2_id = attr2.get('id')
    else:
        feedback.append("Attribute 'Distance to District Office (km)' not found.")

    # 3. Verify Facility Values
    facility = result.get('facility_data')
    if facility and attr1_id and attr2_id:
        attr_values = facility.get('attributeValues', [])
        
        # Helper to find value by attribute ID
        def get_val(a_id):
            for av in attr_values:
                if av.get('attribute', {}).get('id') == a_id:
                    return av.get('value')
            return None

        val1 = get_val(attr1_id)
        val2 = get_val(attr2_id)

        # Check Attribute 1 Value (Generator)
        # DHIS2 boolean values are usually stored as "true" or "false" string
        if val1 is not None:
            score += 5 # Found value entry
            if str(val1).lower() == 'true':
                score += 15
                feedback.append("Facility Generator value is correct (Yes/true).")
            else:
                feedback.append(f"Facility Generator value incorrect: {val1}")
        else:
            feedback.append("No value set for 'Generator Functional' on facility.")

        # Check Attribute 2 Value (Distance)
        if val2 is not None:
            score += 5 # Found value entry
            # Check for 15
            try:
                if float(val2) == 15.0:
                    score += 15
                    feedback.append("Facility Distance value is correct (15).")
                else:
                    feedback.append(f"Facility Distance value incorrect: {val2}")
            except ValueError:
                feedback.append(f"Facility Distance value not a number: {val2}")
        else:
            feedback.append("No value set for 'Distance...' on facility.")
    else:
        if not facility:
            feedback.append("Facility 'Bo Govt Hospital' not found (this shouldn't happen).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }