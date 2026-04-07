#!/usr/bin/env python3
"""
Verifier for standardize_product_attribute task.

This verifier checks if the agent successfully converted a custom text attribute
to a global taxonomy attribute in WooCommerce.

Verification Criteria:
1. Product attributes modified in database (Global 'pa_color' added).
2. Correct taxonomy term ('Green') linked to product.
3. Old custom text attribute ('Color') removed.
4. Other custom attributes ('Material') preserved.
5. VLM trajectory verification (workflow check).
"""

import json
import os
import sys
import tempfile
import logging
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import phpserialize for robust parsing
PHPSERIALIZE_AVAILABLE = False
try:
    import phpserialize
    PHPSERIALIZE_AVAILABLE = True
except ImportError:
    # Attempt to install it if missing (runtime environment usually allows this)
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "phpserialize"])
        import phpserialize
        PHPSERIALIZE_AVAILABLE = True
    except Exception as e:
        logger.warning(f"Could not install phpserialize: {e}")

# ================================================================
# VLM HELPER
# ================================================================
def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception:
        pass
    return None

TRAJECTORY_PROMPT = """You are verifying a WooCommerce data cleanup task.
The user should have:
1. Edited the 'Eco-Friendly Sneaker'.
2. Gone to the 'Attributes' tab.
3. REMOVED a custom 'Color' text attribute.
4. ADDED a global 'Color' attribute and selected 'Green'.

Look at these screenshots sequence.
- Do you see the Attributes tab?
- Do you see the transition from a text field for Color to a dropdown/tag selection?
- Is 'Material' kept intact?

Respond in JSON:
{
    "attributes_tab_visited": true/false,
    "global_attribute_added": true/false,
    "custom_attribute_removed": true/false,
    "confidence": "low/medium/high"
}
"""

def parse_php_array(serialized_str):
    """
    Parse PHP serialized string.
    If phpserialize lib is available, use it.
    Else, use robust heuristic string parsing for this specific task.
    """
    if PHPSERIALIZE_AVAILABLE:
        try:
            # phpserialize requires bytes
            if isinstance(serialized_str, str):
                serialized_str = serialized_str.encode('utf-8')
            data = phpserialize.loads(serialized_str, decode_strings=True)
            # data is a dict (ordered dict usually).
            # Convert to python dict for easier usage
            return data
        except Exception as e:
            logger.error(f"phpserialize failed: {e}")
            return None
            
    # Fallback: String checking
    # We look for keys in the serialized string
    return serialized_str


def verify_standardize_product_attribute(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    db_check = result.get('db_check', {})
    raw_attrs = db_check.get('attributes_raw', '')
    
    score = 0
    feedback = []
    
    # 1. Check Global Attribute Presence (40 pts)
    # Using phpserialize if available
    has_global_color = False
    has_custom_color = False
    has_material = False
    
    parsed_attrs = parse_php_array(raw_attrs)
    
    if isinstance(parsed_attrs, dict):
        # Check keys
        # Global attributes are usually keyed by slug 'pa_color'
        if 'pa_color' in parsed_attrs:
            attr = parsed_attrs['pa_color']
            # Check if it is a taxonomy
            if str(attr.get('is_taxonomy')) == '1':
                has_global_color = True
        
        # Check for Custom Color removal
        # Iterate over keys to see if any non-taxonomy 'Color' exists
        for key, val in parsed_attrs.items():
            name = val.get('name', '')
            is_tax = str(val.get('is_taxonomy', '0'))
            if name.lower() == 'color' and is_tax == '0':
                has_custom_color = True
            if name.lower() == 'material' and is_tax == '0':
                has_material = True
                
    else:
        # Fallback string analysis
        if 's:8:"pa_color"' in str(raw_attrs) and 's:11:"is_taxonomy";i:1' in str(raw_attrs):
             has_global_color = True
        # Logic for custom removal in string is hard, we rely on absence of certain patterns
        # If we see s:5:"Color" ... is_taxonomy";i:0, it's bad.
        # But 'Color' is also the name of the global one.
        # Simplistic check:
        if 's:5:"Color"' in str(raw_attrs) and 's:11:"is_taxonomy";i:0' in str(raw_attrs):
             # This pattern implies a custom attribute named Color exists
             has_custom_color = True
        
        if 's:8:"Material"' in str(raw_attrs):
            has_material = True

    if has_global_color:
        score += 40
        feedback.append("Global 'Color' attribute added.")
    else:
        feedback.append("Global 'Color' attribute NOT found.")

    # 2. Check Term Relationship (20 pts)
    if db_check.get('term_linked'):
        score += 20
        feedback.append("Correct term 'Green' assigned.")
    else:
        feedback.append("Term 'Green' NOT assigned.")

    # 3. Check Custom Attribute Removal (20 pts)
    if not has_custom_color:
        score += 20
        feedback.append("Custom 'Color' text attribute removed.")
    else:
        feedback.append("Custom 'Color' text attribute still present.")

    # 4. Check Material Preservation (10 pts)
    if has_material:
        score += 10
        feedback.append("'Material' attribute preserved.")
    else:
        feedback.append("'Material' attribute missing.")

    # 5. VLM Verification (10 pts)
    vlm_score = 0
    if env_info.get('query_vlm'):
        # Sample trajectory
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = _vlm_query(env_info['query_vlm'], TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get('global_attribute_added'):
                vlm_score = 10
                feedback.append("VLM confirmed workflow.")
    
    score += vlm_score

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }