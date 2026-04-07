#!/usr/bin/env python3
"""
Verifier for create_custom_fields_cost_tracking task.

Checks:
1. "Cost Category" field exists, is List type, has correct options.
2. "Estimated Budget (USD)" field exists, is Float/Int type.
3. Both fields are enabled for the target project (E-Commerce Platform).
4. Three specific work packages have the correct values assigned.
5. Anti-gaming: Custom field count increased from start.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_fields_cost_tracking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic error check
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Internal verification error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get("metadata", {})
    field_cc_name = metadata.get("field_cost_category", "Cost Category")
    field_budget_name = metadata.get("field_budget", "Estimated Budget (USD)")
    
    cfs = result.get("custom_fields", {})
    wps = result.get("work_packages", [])
    
    # --- 1. Verify "Cost Category" Field (35 pts) ---
    cc_data = cfs.get(field_cc_name, {})
    if cc_data.get("exists"):
        score += 10
        feedback_parts.append(f"Field '{field_cc_name}' created")
        
        # Check Format
        if cc_data.get("format") == "list":
            score += 10
            feedback_parts.append("Format is List")
        else:
            feedback_parts.append(f"Wrong format for '{field_cc_name}': {cc_data.get('format')}")
            
        # Check Options
        expected_opts = ["Labor", "Materials", "Equipment", "Subcontractor", "Overhead"]
        actual_opts = cc_data.get("options", [])
        # Normalize for case-insensitive check
        actual_lower = [o.lower() for o in actual_opts]
        expected_lower = [o.lower() for o in expected_opts]
        
        # Check if all expected options are present in correct order (or at least present)
        # We'll be lenient on order, strict on presence
        missing = [o for o in expected_opts if o.lower() not in actual_lower]
        if not missing:
            score += 15
            feedback_parts.append("All list options present")
        else:
            feedback_parts.append(f"Missing options: {', '.join(missing)}")
            
        # Check Project Mapping
        if cc_data.get("is_global") or "ecommerce-platform" in cc_data.get("project_identifiers", []):
            # We credit this in a shared bucket later, but good to note
            pass
        else:
            feedback_parts.append(f"'{field_cc_name}' not enabled for E-Commerce Platform")
            
    else:
        feedback_parts.append(f"Field '{field_cc_name}' NOT found")

    # --- 2. Verify "Estimated Budget" Field (15 pts) ---
    budget_data = cfs.get(field_budget_name, {})
    if budget_data.get("exists"):
        score += 8
        feedback_parts.append(f"Field '{field_budget_name}' created")
        
        fmt = budget_data.get("format")
        if fmt in ["float", "int", "integer"]:
            score += 7
            feedback_parts.append("Format is Numeric")
        else:
            feedback_parts.append(f"Wrong format for '{field_budget_name}': {fmt}")
    else:
        feedback_parts.append(f"Field '{field_budget_name}' NOT found")

    # --- 3. Verify Project Enablement (15 pts) ---
    # Both fields must be available to the project
    cc_enabled = cc_data.get("exists") and (cc_data.get("is_global") or "ecommerce-platform" in cc_data.get("project_identifiers", []))
    budget_enabled = budget_data.get("exists") and (budget_data.get("is_global") or "ecommerce-platform" in budget_data.get("project_identifiers", []))
    
    if cc_enabled and budget_enabled:
        score += 15
        feedback_parts.append("Both fields enabled for target project")
    elif cc_enabled or budget_enabled:
        score += 7
        feedback_parts.append("Only one field enabled for target project")
    else:
        feedback_parts.append("Fields not enabled for target project")

    # --- 4. Verify Work Package Values (35 pts) ---
    # We expect 3 WPs in the result list
    
    # WP 1: Search -> Labor, 15000
    wp1 = next((w for w in wps if "product search" in w.get("subject", "").lower()), None)
    if wp1 and wp1.get("found"):
        vals = wp1.get("values", {})
        # Check Category
        val_cc = str(vals.get(field_cc_name) or "")
        if "labor" in val_cc.lower():
            score += 7
            feedback_parts.append("WP1 category correct")
        
        # Check Budget
        try:
            val_bud = float(vals.get(field_budget_name) or 0)
            if abs(val_bud - 15000) < 1.0:
                score += 7
                feedback_parts.append("WP1 budget correct")
        except:
            pass
    else:
        feedback_parts.append("WP1 not found/updated")

    # WP 2: Checkout -> Labor, 5000
    wp2 = next((w for w in wps if "checkout" in w.get("subject", "").lower()), None)
    if wp2 and wp2.get("found"):
        vals = wp2.get("values", {})
        val_cc = str(vals.get(field_cc_name) or "")
        if "labor" in val_cc.lower():
            score += 7
            feedback_parts.append("WP2 category correct")
        try:
            val_bud = float(vals.get(field_budget_name) or 0)
            if abs(val_bud - 5000) < 1.0:
                score += 7
                feedback_parts.append("WP2 budget correct")
        except:
            pass
    else:
        feedback_parts.append("WP2 not found/updated")

    # WP 3: Database -> Equipment, 8000
    wp3 = next((w for w in wps if "database queries" in w.get("subject", "").lower()), None)
    if wp3 and wp3.get("found"):
        vals = wp3.get("values", {})
        val_cc = str(vals.get(field_cc_name) or "")
        if "equipment" in val_cc.lower():
            score += 3
            feedback_parts.append("WP3 category correct")
        try:
            val_bud = float(vals.get(field_budget_name) or 0)
            if abs(val_bud - 8000) < 1.0:
                score += 4
                feedback_parts.append("WP3 budget correct")
        except:
            pass
    else:
        feedback_parts.append("WP3 not found/updated")

    # --- 5. Anti-Gaming Check ---
    initial_count = int(result.get("initial_cf_count", 0))
    final_count = int(result.get("total_cf_count", 0))
    
    # We expect at least 2 new fields. If count didn't increase, something is wrong.
    if final_count <= initial_count and score > 0:
        score = 0
        feedback_parts.append("ANTI-GAMING FAIL: Custom field count did not increase.")
    
    passed = score >= 60 and cc_enabled and budget_enabled
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }