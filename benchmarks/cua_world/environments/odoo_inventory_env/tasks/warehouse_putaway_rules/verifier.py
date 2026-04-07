#!/usr/bin/env python3
"""
Verifier for warehouse_putaway_rules task.
"""
import json
import os
import tempfile
import logging
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_date(d_str):
    """Parse Odoo UTC string to Unix timestamp."""
    if not d_str:
        return 0
    try:
        dt = datetime.strptime(d_str, "%Y-%m-%d %H:%M:%S")
        return int(dt.replace(tzinfo=timezone.utc).timestamp())
    except:
        return 0

def verify_warehouse_putaway_rules(traj, env_info, task_info):
    """
    Verify the configuration of sub-locations and putaway rules.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_locations = metadata.get('expected_locations', [
        "Zone A - Power Tools",
        "Zone B - Hand Tools",
        "Zone C - Fasteners"
    ])
    expected_rules = metadata.get('expected_rules', {
        "Power Tools": "Zone A - Power Tools",
        "Hand Tools": "Zone B - Hand Tools",
        "Fasteners": "Zone C - Fasteners"
    })
    pass_threshold = metadata.get('pass_threshold', 65)

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env("/tmp/putaway_rules_result.json", local_path)
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)
    wh_stock_id = result.get('wh_stock_id')

    # 1. Check Multi-Locations Enabled (10 pts)
    if result.get('multi_loc_enabled'):
        score += 10
        feedback_parts.append("✅ Storage Locations enabled (+10)")
    else:
        feedback_parts.append("❌ Storage Locations not enabled")

    # 2. Check Locations Created (30 pts - 10 pts each)
    locations = result.get('locations', [])
    loc_map = {}
    created_after_start = True
    
    for loc in locations:
        name = loc.get('name')
        loc_map[name] = loc
        
        # Check hierarchy (must be under WH/Stock)
        parent = loc.get('location_id')
        parent_is_correct = False
        if parent and isinstance(parent, list) and len(parent) > 0:
            if parent[0] == wh_stock_id:
                parent_is_correct = True
        
        # Check creation time (anti-gaming)
        loc_time = parse_odoo_date(loc.get('create_date'))
        if loc_time > 0 and task_start > 0 and loc_time < task_start - 60:
            created_after_start = False

        if name in expected_locations and parent_is_correct:
            score += 10
            feedback_parts.append(f"✅ Location '{name}' created under WH/Stock (+10)")
        elif name in expected_locations:
            score += 5
            feedback_parts.append(f"⚠️ Location '{name}' created but wrong parent (+5)")

    # 3. Check Putaway Rules (30 pts - 10 pts each)
    rules = result.get('putaway_rules', [])
    rules_created_after_start = True
    
    for cat_name, dest_loc_name in expected_rules.items():
        rule_found = False
        for rule in rules:
            rule_cat = rule.get('category_id')
            rule_loc_in = rule.get('location_in_id')
            rule_loc_out = rule.get('location_out_id')
            
            # Unpack Odoo m2o fields
            cat_match = rule_cat and isinstance(rule_cat, list) and rule_cat[1] == cat_name
            in_match = rule_loc_in and isinstance(rule_loc_in, list) and rule_loc_in[0] == wh_stock_id
            out_match = rule_loc_out and isinstance(rule_loc_out, list) and rule_loc_out[1] == dest_loc_name
            
            # Anti-gaming check on rules
            rule_time = parse_odoo_date(rule.get('create_date'))
            if rule_time > 0 and task_start > 0 and rule_time < task_start - 60:
                rules_created_after_start = False

            if cat_match and in_match and out_match:
                rule_found = True
                break
                
        if rule_found:
            score += 10
            feedback_parts.append(f"✅ Putaway rule for {cat_name} -> {dest_loc_name} created (+10)")
        else:
            feedback_parts.append(f"❌ Missing or incorrect putaway rule for {cat_name}")

    # 4. Anti-gaming check score integration (10 pts)
    if created_after_start and rules_created_after_start:
        score += 10
        feedback_parts.append("✅ Entities created during task timeframe (+10)")
    else:
        feedback_parts.append("❌ Some entities were created before task started (Anti-gaming penalty)")

    # 5. VLM Trajectory Verification (20 pts)
    # Proves the agent actually interacted with the UI to do this, rather than exploiting an API
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final: frames.append(final)
            
            prompt = """Look at these screenshots from an Odoo 17 Inventory session.
            Did the user navigate to configuration screens (Settings, Locations, or Putaway Rules) 
            to set up warehouse storage zones and product category routing?
            
            Respond in JSON:
            {
                "interacted_with_config": true/false,
                "reasoning": "brief explanation"
            }"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("interacted_with_config", False):
                    score += 20
                    feedback_parts.append("✅ VLM confirms UI configuration interaction (+20)")
                else:
                    feedback_parts.append("❌ VLM did not observe UI configuration interaction")
            else:
                feedback_parts.append("⚠️ VLM verification failed, skipping visual check.")
        except Exception as e:
            logger.error(f"VLM check error: {e}")
            feedback_parts.append(f"⚠️ VLM check error: {e}")

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }