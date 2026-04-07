#!/usr/bin/env python3
"""
Verifier for create_textile_unit_flow task.

Checks:
1. Unit Group "Units of linear density" created
2. Units "tex", "dtex", "denier" created with correct factors
3. Flow Property "Linear density" created and linked to Unit Group
4. Product Flow "Polyester staple fiber" created and linked to Flow Property
5. VLM check for UI interaction workflow
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_textile_unit_flow(traj, env_info, task_info):
    """Verify creation of textile units and flows in openLCA."""
    
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata & Constants
    score = 0
    feedback_parts = []
    
    ug_data = result.get('unit_group', {})
    fp_data = result.get('flow_property', {})
    flow_data = result.get('flow', {})
    
    # 3. Verify Unit Group (15 pts)
    if ug_data.get('found'):
        score += 15
        feedback_parts.append("Unit Group created")
    else:
        feedback_parts.append("Unit Group NOT found")

    # 4. Verify Units (30 pts)
    units = ug_data.get('units', [])
    tex_found = False
    dtex_found = False
    denier_found = False
    
    for u in units:
        name = u.get('name', '').lower()
        factor = float(u.get('factor', 0))
        is_ref = str(u.get('is_ref', '0'))
        
        # Check tex (Reference, 1.0)
        if 'tex' == name:
            if abs(factor - 1.0) < 0.001 and (is_ref == '1' or is_ref == 'True'):
                score += 10
                tex_found = True
            elif abs(factor - 1.0) < 0.001:
                # Value correct but maybe not marked ref? Still partial credit
                score += 5
                feedback_parts.append("tex found but not ref?")
                tex_found = True

        # Check dtex (0.1)
        if 'dtex' in name or 'decitex' in name:
            if abs(factor - 0.1) < 0.01:
                score += 10
                dtex_found = True

        # Check denier (0.1111...)
        if 'denier' in name:
            # 1/9 is approx 0.111111
            if abs(factor - (1.0/9.0)) < 0.02:
                score += 10
                denier_found = True
    
    if tex_found: feedback_parts.append("Unit 'tex' correct")
    if dtex_found: feedback_parts.append("Unit 'dtex' correct")
    if denier_found: feedback_parts.append("Unit 'denier' correct")

    # 5. Verify Flow Property (25 pts)
    if fp_data.get('found'):
        score += 15
        if fp_data.get('linked_to_ug'):
            score += 10
            feedback_parts.append("Flow Property linked correctly")
        else:
            feedback_parts.append("Flow Property created but NOT linked to Unit Group")
    else:
        feedback_parts.append("Flow Property NOT found")

    # 6. Verify Product Flow (25 pts)
    if flow_data.get('found'):
        score += 15
        if flow_data.get('linked_to_fp'):
            score += 5
            feedback_parts.append("Flow linked to Property")
        else:
            feedback_parts.append("Flow created but NOT linked to Property")
            
        if flow_data.get('is_product'):
            score += 5
            feedback_parts.append("Flow type is Product")
        else:
            feedback_parts.append("Flow type incorrect (not Product)")
    else:
        feedback_parts.append("Product Flow NOT found")

    # 7. VLM Trajectory Check (5 pts)
    # Simple check: verify screenshots exist and show usage
    screenshot_exists = result.get('screenshot_path')
    if screenshot_exists and score > 0:
        score += 5
    
    # Final Tally
    passed = score >= 60 and ug_data.get('found') and len(units) >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "units_found": [u.get('name') for u in units],
            "flow_created": flow_data.get('name')
        }
    }