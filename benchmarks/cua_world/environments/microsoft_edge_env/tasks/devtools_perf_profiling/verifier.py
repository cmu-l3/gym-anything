#!/usr/bin/env python3
"""
Verifier for devtools_perf_profiling task.

Criteria:
1. Report file exists and was created/modified during the task. (10 pts)
2. Report mentions all 3 target sites (CNN, Wikipedia, GitHub). (15 pts)
3. Report contains specific performance timing data (e.g., "Scripting: 500ms"). (20 pts)
4. Report contains standard DevTools Performance terms (Rendering, Painting, etc.). (15 pts)
5. Browser history confirms visits to all 3 sites during the task. (15 pts)
6. VLM Trajectory: Confirms visual evidence of DevTools Performance panel usage. (25 pts)

Total: 100 pts. Pass threshold: 65 pts.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_devtools_perf_profiling(traj, env_info, task_info):
    """
    Verifies the DevTools Performance Profiling task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    report = result.get("report", {})
    history = result.get("history", {})
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Report Existence & Freshness (10 pts) ---
    if report.get("exists") and report.get("modified_after_start"):
        score += 10
        feedback_parts.append("Report created successfully (10/10)")
    elif report.get("exists"):
        score += 5
        feedback_parts.append("Report exists but not modified during task (5/10)")
    else:
        feedback_parts.append("Report not found (0/10)")

    # --- Criterion 2: Site Coverage in Report (15 pts) ---
    domains_mentioned = report.get("domains_mentioned", [])
    sites_count = len(domains_mentioned)
    if sites_count == 3:
        score += 15
        feedback_parts.append("All 3 sites mentioned in report (15/15)")
    else:
        pts = sites_count * 5
        score += pts
        feedback_parts.append(f"{sites_count}/3 sites mentioned in report ({pts}/15)")

    # --- Criterion 3: Timing Data (20 pts) ---
    if report.get("has_timing_data"):
        score += 20
        feedback_parts.append("Timing data found in report (20/20)")
    else:
        feedback_parts.append("No timing values (ms/s) found in report (0/20)")

    # --- Criterion 4: Performance Terminology (15 pts) ---
    # Expected: Scripting, Rendering, Painting, Loading, Idle
    term_count = report.get("performance_terms_count", 0)
    if term_count >= 3:
        score += 15
        feedback_parts.append("Correct DevTools terminology used (15/15)")
    elif term_count > 0:
        score += 5
        feedback_parts.append("Some DevTools terminology used (5/15)")
    else:
        feedback_parts.append("No standard DevTools terms found (0/15)")

    # --- Criterion 5: Browser History Verification (15 pts) ---
    visited_count = sum([
        history.get("cnn_visited", False),
        history.get("wikipedia_visited", False),
        history.get("github_visited", False)
    ])
    if visited_count == 3:
        score += 15
        feedback_parts.append("History confirms visits to all sites (15/15)")
    else:
        pts = visited_count * 5
        score += pts
        feedback_parts.append(f"History confirms visits to {visited_count}/3 sites ({pts}/15)")

    # --- Criterion 6: VLM Trajectory Verification (25 pts) ---
    # We check if the agent actually opened the Performance panel
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying a web development task. 
    Look at these screenshots of Microsoft Edge.
    
    I am looking for evidence that the user opened the "Performance" panel in Developer Tools (DevTools).
    
    Positive indicators:
    - A panel labeled "Performance" is visible.
    - A flame chart (colorful bars showing CPU activity) is visible.
    - Donut charts showing Summary (Loading, Scripting, Rendering, Painting).
    - Buttons like "Record" (circle icon) or "Reload" (refresh icon) inside a DevTools panel.
    
    Question: Is the DevTools Performance panel visible in ANY of these frames?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {}) # If structured output
        # Fallback to text analysis if parsed not available or simple string
        response_text = vlm_result.get("response", "").lower()
        if "yes" in response_text and "performance" in response_text:
            vlm_passed = True
    
    if vlm_passed:
        score += 25
        feedback_parts.append("VLM confirmed usage of Performance panel (25/25)")
    else:
        # Fallback: if they got high score on report details, maybe VLM just missed it
        if score >= 50: 
            score += 10 # Give partial credit if report is good
            feedback_parts.append("VLM did not clearly see Performance panel, but report looks authentic (+10)")
        else:
            feedback_parts.append("VLM did not detect Performance panel usage (0/25)")

    # --- Final Result ---
    # Pass threshold: 65
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }