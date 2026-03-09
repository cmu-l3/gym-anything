#!/usr/bin/env python3
"""
Verifier for Separate Catalog Store Setup task.

Verification Logic:
1. Root Category 'Pro Catalog' exists and is Level 1 (20 pts)
2. Subcategory 'Office Solutions' exists and is child of 'Pro Catalog' (15 pts)
3. Store Group 'NestWell Pro' exists (20 pts)
4. Store Group is linked to 'Pro Catalog' (root_category_id match) (25 pts)
5. Store View 'pro_en' exists, is active, and belongs to 'NestWell Pro' (10 pts)
6. Product 'LAPTOP-001' is in 'Office Solutions' (10 pts)

Pass Threshold: 65 points (Must minimally link store to new root)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_separate_catalog_store_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Root Category (20 pts)
    root = result.get("root_category", {})
    root_id = int(root.get("id", 0))
    root_level = int(root.get("level", 0))
    
    # In Magento, Level 0=Root(Invisible), Level 1=Default Category(Visible Root)
    if root_id > 0 and root_level == 1:
        score += 20
        feedback.append("✅ Root Category 'Pro Catalog' created correctly (Level 1).")
    elif root_id > 0:
        score += 5
        feedback.append(f"⚠️ 'Pro Catalog' created but wrong level (Level {root_level}, expected 1).")
    else:
        feedback.append("❌ Root Category 'Pro Catalog' not found.")

    # 2. Check Subcategory (15 pts)
    sub = result.get("subcategory", {})
    sub_id = int(sub.get("id", 0))
    sub_parent = int(sub.get("parent_id", 0))

    if sub_id > 0 and root_id > 0 and sub_parent == root_id:
        score += 15
        feedback.append("✅ Subcategory 'Office Solutions' created under 'Pro Catalog'.")
    elif sub_id > 0:
        score += 5
        feedback.append("⚠️ 'Office Solutions' exists but is not under 'Pro Catalog'.")
    else:
        feedback.append("❌ Subcategory 'Office Solutions' not found.")

    # 3. Check Store Group (20 pts)
    group = result.get("store_group", {})
    group_id = int(group.get("id", 0))
    group_root = int(group.get("root_category_id", 0))

    if group_id > 0:
        score += 20
        feedback.append("✅ Store Group 'NestWell Pro' created.")
    else:
        feedback.append("❌ Store Group 'NestWell Pro' not found.")

    # 4. Check Store -> Root Link (25 pts) - CRITICAL
    if group_id > 0 and root_id > 0 and group_root == root_id:
        score += 25
        feedback.append("✅ Store Group linked correctly to 'Pro Catalog'.")
    elif group_id > 0:
        feedback.append(f"❌ Store Group linked to wrong root (ID {group_root}, expected {root_id}).")
    
    # 5. Check Store View (10 pts)
    view = result.get("store_view", {})
    view_id = int(view.get("id", 0))
    view_group = int(view.get("group_id", 0))
    view_active = int(view.get("is_active", 0))

    if view_id > 0 and view_group == group_id and view_active == 1:
        score += 10
        feedback.append("✅ Store View 'pro_en' created and active.")
    elif view_id > 0:
        score += 5
        feedback.append("⚠️ Store View 'pro_en' exists but has issues (inactive or wrong group).")
    else:
        feedback.append("❌ Store View 'pro_en' not found.")

    # 6. Check Product Assignment (10 pts)
    if result.get("product_assigned", False):
        score += 10
        feedback.append("✅ Product 'LAPTOP-001' assigned to 'Office Solutions'.")
    else:
        feedback.append("❌ Product 'LAPTOP-001' not assigned to correct category.")

    # Final Verdict
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }