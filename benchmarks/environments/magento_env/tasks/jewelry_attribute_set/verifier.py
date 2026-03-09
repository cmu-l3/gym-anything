#!/usr/bin/env python3
"""Verifier for Jewelry Attribute Set task in Magento.

Task: Create 3 product attributes and organize them into a 'Jewelry' attribute set
with a specific group 'Jewelry Specifications'.

Scoring (100 pts total):
1. Attributes exist and have correct types (30 pts)
2. Attributes have correct option values (20 pts)
3. Attribute Set 'Jewelry' exists (15 pts)
4. Attribute Group 'Jewelry Specifications' exists (15 pts)
5. Attributes are assigned to the group correctly (20 pts)

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_jewelry_attribute_set(traj, env_info, task_info):
    """Verify attributes, set, and assignments."""
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/jewelry_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")
    
    score = 0
    feedback_parts = []
    
    # 1. Verify Attributes (10 pts each)
    attrs = result
    
    # jewelry_material
    mat = attrs.get('jewelry_material', {})
    if mat.get('found') and mat.get('input') == 'select':
        score += 10
        feedback_parts.append("jewelry_material exists (10 pts)")
        
        # Check options (Gold, Silver, Bronze, Platinum)
        opts = mat.get('options', '').lower()
        required = ['gold', 'silver', 'bronze', 'platinum']
        if all(r in opts for r in required):
            score += 10
            feedback_parts.append("jewelry_material options correct (10 pts)")
        else:
            feedback_parts.append(f"jewelry_material options incomplete: found '{opts}'")
    else:
        feedback_parts.append("jewelry_material missing or wrong type")

    # gemstone_type
    gem = attrs.get('gemstone_type', {})
    if gem.get('found') and gem.get('input') == 'select':
        score += 10
        feedback_parts.append("gemstone_type exists (10 pts)")
        
        # Check options (Diamond, Ruby, Emerald, Sapphire, None)
        opts = gem.get('options', '').lower()
        required = ['diamond', 'ruby', 'emerald', 'sapphire', 'none']
        if all(r in opts for r in required):
            score += 10
            feedback_parts.append("gemstone_type options correct (10 pts)")
        else:
            feedback_parts.append(f"gemstone_type options incomplete: found '{opts}'")
    else:
        feedback_parts.append("gemstone_type missing or wrong type")

    # chain_length_inches
    chain = attrs.get('chain_length_inches', {})
    if chain.get('found') and chain.get('input') == 'text':
        score += 10
        feedback_parts.append("chain_length_inches exists (10 pts)")
    else:
        feedback_parts.append("chain_length_inches missing or wrong type")

    # 2. Verify Attribute Set & Group (30 pts)
    aset = attrs.get('attribute_set', {})
    agroup = attrs.get('attribute_group', {})
    
    if aset.get('found'):
        score += 15
        feedback_parts.append("Attribute Set 'Jewelry' exists (15 pts)")
        
        if agroup.get('found'):
            score += 15
            feedback_parts.append("Group 'Jewelry Specifications' exists (15 pts)")
        else:
            feedback_parts.append("Group 'Jewelry Specifications' missing in set")
    else:
        feedback_parts.append("Attribute Set 'Jewelry' missing")

    # 3. Verify Assignments (20 pts)
    assigns = attrs.get('assignments', {})
    assigned_count = sum(1 for v in assigns.values() if v)
    
    if assigned_count == 3:
        score += 20
        feedback_parts.append("All 3 attributes assigned to group correctly (20 pts)")
    elif assigned_count > 0:
        partial = int((assigned_count / 3) * 20)
        score += partial
        feedback_parts.append(f"Partial assignments: {assigned_count}/3 assigned ({partial} pts)")
    else:
        feedback_parts.append("No attributes assigned to the new group")

    # Anti-gaming check: Verify counts increased
    initial_attr = int(result.get('initial_attr_count', 0))
    current_attr = int(result.get('current_attr_count', 0))
    if current_attr <= initial_attr:
        feedback_parts.append("(Warning: Attribute count did not increase)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }