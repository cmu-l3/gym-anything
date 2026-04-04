#!/usr/bin/env python3
"""
Verifier for implement_onboarding_carousel task.

Scoring Breakdown (100 pts total):
1. Build Success (20 pts)
2. Layout Structure (20 pts):
   - activity_main.xml contains ViewPager2 and TabLayout
3. Item Layout (15 pts):
   - item_onboarding.xml exists and contains ImageView + TextViews
4. Adapter Implementation (25 pts):
   - OnboardingAdapter exists, extends RecyclerView.Adapter
   - Binds views in onBindViewHolder
5. Integration (20 pts):
   - MainActivity uses TabLayoutMediator
   - Does not hardcode strings in main layout
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_onboarding_carousel(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Build Success (20 pts)
    if result.get("build_success", False):
        score += 20
        feedback_parts.append("Project compiles (20/20)")
    else:
        feedback_parts.append("Project failed to compile (0/20)")

    # 2. Layout Structure (20 pts)
    main_xml = result.get("activity_xml_content", "")
    has_vp2 = "androidx.viewpager2.widget.ViewPager2" in main_xml
    has_tabs = "com.google.android.material.tabs.TabLayout" in main_xml
    
    if has_vp2 and has_tabs:
        score += 20
        feedback_parts.append("Main layout contains ViewPager2 and TabLayout (20/20)")
    elif has_vp2:
        score += 10
        feedback_parts.append("Main layout has ViewPager2 but missing TabLayout (10/20)")
    else:
        feedback_parts.append("Main layout missing required components (0/20)")

    # 3. Item Layout (15 pts)
    item_xml = result.get("item_xml_content", "")
    if result.get("item_xml_exists", False):
        has_img = "<ImageView" in item_xml
        has_txt = item_xml.count("<TextView") >= 2
        if has_img and has_txt:
            score += 15
            feedback_parts.append("Item layout created correctly (15/15)")
        else:
            score += 5
            feedback_parts.append("Item layout exists but missing views (5/15)")
    else:
        feedback_parts.append("Item layout not found (0/15)")

    # 4. Adapter Implementation (25 pts)
    adapter_code = result.get("adapter_content", "")
    if result.get("adapter_exists", False):
        extends_adapter = "RecyclerView.Adapter" in adapter_code
        binds_views = "onBindViewHolder" in adapter_code
        if extends_adapter and binds_views:
            score += 25
            feedback_parts.append("Adapter implemented correctly (25/25)")
        elif extends_adapter:
            score += 10
            feedback_parts.append("Adapter class exists but incomplete (10/25)")
    else:
        feedback_parts.append("OnboardingAdapter not found (0/25)")

    # 5. Integration and Logic (20 pts)
    main_code = result.get("main_activity_content", "")
    has_mediator = "TabLayoutMediator" in main_code
    hardcoded = result.get("hardcoded_in_main", False)
    
    if hardcoded:
        feedback_parts.append("CRITICAL: Text hardcoded in activity_main.xml (-20 pts)")
        # No points for integration if they faked it
    elif has_mediator:
        score += 20
        feedback_parts.append("TabLayoutMediator used for integration (20/20)")
    else:
        feedback_parts.append("TabLayoutMediator not found in MainActivity (0/20)")

    # VLM Verification (Optional Boost / Verification of Visuals)
    # If the score is borderline, we check if they actually ran it.
    # For now, we stick to programmatic scoring as primary, but if VLM is available
    # we could verify the visual output.
    
    passed = score >= 60 and result.get("build_success", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }