#!/usr/bin/env python3
"""
Verifier for implement_swipe_refresh task.

Scoring (100 points total):
1. Dependency Verification (20 pts):
   - build.gradle.kts contains 'swiperefreshlayout'
2. Build Verification (20 pts):
   - Project compiles successfully
3. Layout Verification (35 pts):
   - SwipeRefreshLayout exists in XML (15 pts)
   - Wraps RecyclerView (10 pts)
   - Has correct ID @+id/swipe_refresh (10 pts)
4. Code Verification (25 pts):
   - setOnRefreshListener implemented (15 pts)
   - Calls viewModel.refreshData() (5 pts)
   - Resets isRefreshing to false (5 pts)

Also uses VLM for visual confirmation of the workflow.
"""

import json
import logging
import os
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_implement_swipe_refresh(traj, env_info, task_info):
    """Verify implementation of Swipe-to-Refresh pattern."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read exported result
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    score = 0
    feedback_parts = []
    
    # 1. Dependency Check (20 pts)
    build_content = result.get("build_gradle_content", "")
    if "swiperefreshlayout" in build_content:
        score += 20
        feedback_parts.append("Dependency added (20/20)")
    else:
        feedback_parts.append("Missing swiperefreshlayout dependency (0/20)")

    # 2. Build Check (20 pts)
    if result.get("build_success", False):
        score += 20
        feedback_parts.append("Build success (20/20)")
    else:
        feedback_parts.append("Build failed or not attempted (0/20)")

    # 3. Layout Check (35 pts)
    layout_content = result.get("layout_content", "")
    layout_score = 0
    
    # Check for tag existence
    if "SwipeRefreshLayout" in layout_content or "androidx.swiperefreshlayout.widget.SwipeRefreshLayout" in layout_content:
        layout_score += 15
        feedback_parts.append("SwipeRefreshLayout found in XML")
        
        # Check hierarchy (simple regex containment check)
        # We look for SwipeRefresh... then RecyclerView ... then /SwipeRefresh
        # Normalizing whitespace for regex
        normalized_layout = re.sub(r'\s+', ' ', layout_content)
        if re.search(r'SwipeRefreshLayout.*RecyclerView.*</.*SwipeRefreshLayout>', normalized_layout, re.IGNORECASE):
            layout_score += 10
            feedback_parts.append("Correct nesting")
        else:
            feedback_parts.append("Incorrect nesting (RecyclerView must be inside SwipeRefreshLayout)")
            
        # Check ID
        if 'android:id="@+id/swipe_refresh"' in layout_content:
            layout_score += 10
            feedback_parts.append("Correct ID used")
        else:
            feedback_parts.append("Incorrect ID")
    else:
        feedback_parts.append("SwipeRefreshLayout missing from XML")
    
    score += layout_score
    feedback_parts.append(f"Layout score: {layout_score}/35")

    # 4. Code Logic Check (25 pts)
    kt_content = result.get("main_activity_content", "")
    code_score = 0
    
    if "setOnRefreshListener" in kt_content:
        code_score += 15
        feedback_parts.append("Listener implemented")
        
        if "refreshData" in kt_content:
            code_score += 5
            feedback_parts.append("Data refresh called")
        else:
            feedback_parts.append("Missing data refresh call")
            
        if "isRefreshing" in kt_content and "false" in kt_content:
            code_score += 5
            feedback_parts.append("Indicator dismissal logic found")
        else:
            feedback_parts.append("Missing indicator dismissal (isRefreshing = false)")
    else:
        feedback_parts.append("setOnRefreshListener not found")
        
    score += code_score
    feedback_parts.append(f"Code score: {code_score}/25")

    # 5. VLM Verification (Bonus/Confirmation)
    # Use VLM to confirm the visual state if programmatic checks are ambiguous
    if query_vlm:
        frames = sample_trajectory_frames(traj, num_samples=3)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        prompt = """
        You are verifying an Android development task.
        The user should have modified the XML layout to include a SwipeRefreshLayout (often visible in code editor)
        and modified the Kotlin code to add a refresh listener.
        
        Look at these screenshots. Do you see:
        1. Code modifications involving 'SwipeRefreshLayout' or 'setOnRefreshListener'?
        2. A successful build output or green checks?
        3. The Android Studio interface?
        
        Respond with {"evidence_found": true/false, "reason": "..."}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("evidence_found", False):
                feedback_parts.append("VLM confirmed work progression.")
        except Exception:
            pass

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }