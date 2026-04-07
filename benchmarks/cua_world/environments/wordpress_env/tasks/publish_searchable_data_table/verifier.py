#!/usr/bin/env python3
"""
Verifier for publish_searchable_data_table task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):
Programmatic checks (70 points):
  1. TablePress plugin installed and active (15 pts)
  2. Table data imported successfully (10 pts)
  3. Data authenticity: 'Aachen' found in the imported table data (15 pts)
  4. Published post with exact title exists & created during task (10 pts)
  5. Post content contains valid TablePress shortcode or block (20 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  6. Agent workflow progression (plugin install, import, post creation)

Pass threshold: 70 points AND (plugin_active AND data_authentic AND post_found AND shortcode_embedded)
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent adding a data table to WordPress.

The agent should progress through:
1. Navigating to Plugins > Add New and searching/installing "TablePress"
2. Activating the plugin
3. Navigating to the TablePress menu and using the "Import" tab to upload a CSV file
4. Navigating to Posts > Add New
5. Creating a post, entering the title, and embedding the table (via shortcode [table id=... /] or a block)
6. Publishing the post

Assess:
1. WORKFLOW_COMPLETED: Did the agent install the plugin, import the data, and create the post?
2. PLUGIN_INSTALL_VISIBLE: Is the plugin search or activation visible?
3. CSV_IMPORT_VISIBLE: Is the TablePress file import interface visible?
4. POST_EDITOR_VISIBLE: Is the post editor visible with table shortcode/block?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "plugin_install_visible": true/false,
    "csv_import_visible": true/false,
    "post_editor_visible": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress data table publication task.

Assess:
1. SUCCESS_INDICATORS: Do you see the published post on the front-end rendering a data table, OR the WordPress admin showing a successful publication of the post containing the TablePress block/shortcode?
2. DATA_VISIBLE: Is there evidence of the meteorite data (e.g., words like "Aachen", "Aarhus", or columns like "mass (g)")?
3. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "success_indicators": true/false,
    "data_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_data_table(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result file from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    tp_active = result.get("tablepress_active", False)
    table_exists = result.get("table_exists", False)
    data_authentic = result.get("data_authentic", False)
    post_found = result.get("post_found", False)
    post_created_after = result.get("post_created_after_start", False)
    post_content = result.get("post_content", "")

    # Programmatic checks
    if tp_active:
        score += 15
        feedback_parts.append("TablePress active")
    else:
        feedback_parts.append("TablePress NOT active")

    if table_exists:
        score += 10
        feedback_parts.append("Table created")
        if data_authentic:
            score += 15
            feedback_parts.append("Authentic data imported")
        else:
            feedback_parts.append("Data not authentic/missing CSV content")
    else:
        feedback_parts.append("Table NOT imported")

    if post_found and post_created_after:
        score += 10
        feedback_parts.append("Post created")
    elif post_found:
        feedback_parts.append("Post found but existed before task (gaming attempt)")
        post_found = False # invalidate for final check
    else:
        feedback_parts.append("Target post NOT found")

    # Check for shortcode or block in content
    # Look for [table id=... /] or WordPress block markup <!-- wp:tablepress/table {"id":"..."} /-->
    shortcode_embedded = False
    if post_found:
        shortcode_match = re.search(r'\[table\s+id=[\'"]?\w+[\'"]?\s*/?\]', post_content, re.IGNORECASE)
        block_match = re.search(r'<!--\s*wp:tablepress/table\s+.*?-->', post_content, re.IGNORECASE)
        
        if shortcode_match or block_match:
            shortcode_embedded = True
            score += 20
            feedback_parts.append("Table embedded in post")
        else:
            feedback_parts.append("No TablePress shortcode/block found in post")

    # VLM Evaluation (Optional but recommended)
    query_vlm = env_info.get("query_vlm")
    vlm_success = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        final_frame = get_final_screenshot(traj)
        
        # Trajectory Eval
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
        if traj_res:
            if traj_res.get("workflow_completed"):
                score += 10
                vlm_success = True
            if traj_res.get("plugin_install_visible") and traj_res.get("csv_import_visible"):
                score += 10
                
        # Final state Eval
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
        if final_res and final_res.get("success_indicators") and not final_res.get("error_indicators"):
            score += 10
            feedback_parts.append("VLM confirmed visual success")
    else:
        # Give free VLM points if VLM is unavailable but programmatic passes perfectly
        if tp_active and data_authentic and post_found and shortcode_embedded:
            score += 30
            vlm_success = True
            feedback_parts.append("VLM points granted (offline)")

    # Final logic
    key_criteria_met = tp_active and data_authentic and post_found and shortcode_embedded
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }