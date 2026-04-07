#!/usr/bin/env python3
"""
Verifier for setup_community_events_calendar task.

Verification Strategy:
Programmatic checks (70 points):
  1. 'The Events Calendar' plugin active (10 pts)
  2. Venue 'Downtown Central Library' created (15 pts)
  3. Event 1 created with correct date & linked to venue (15 pts)
  4. Event 2 created with correct date & linked to venue (15 pts)
  5. Event 3 created with correct date & linked to venue (15 pts)

VLM checks (30 points):
  6. Process verification: Trajectory shows agent navigating plugin installation and event creation (15 pts)
  7. Final state verification: Final frame shows events list or success (10 pts)
  8. Cross-validation: Programmatic matches VLM observations (5 pts)

Pass threshold: >= 70 points AND Plugin active AND Venue created AND at least 2 events fully configured.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Prompts ---

TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent installing a plugin and setting up an events calendar in WordPress.

The agent should progress through:
1. Navigating to Plugins > Add New and searching for/installing "The Events Calendar"
2. Navigating to Events > Venues to create a venue
3. Navigating to Events > Add New to create 3 events
4. Reading from a text/markdown file on the Desktop

Assess:
1. PLUGIN_INSTALLED: Is there evidence of the agent installing or activating the Events Calendar plugin?
2. VENUE_CREATED: Is the agent seen interacting with the venue creation form?
3. EVENTS_CREATED: Is the agent seen entering event details (title, dates, times) into the event editor?
4. READ_DATA: Is there evidence of the agent reading the event schedule file?

Respond in JSON format:
{
    "plugin_installed": true/false,
    "venue_created": true/false,
    "events_created": true/false,
    "read_data": true/false,
    "confidence": "low"/"medium"/"high",
    "stages_observed": ["list stages"]
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of an Events Calendar setup task in WordPress.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. SUCCESS_INDICATORS: Are events visible in the Events list, or is there a "Post published" success message?
3. EVENTS_PLUGIN_VISIBLE: Can you see the "Events" menu in the WordPress left sidebar?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "events_plugin_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

def verify_setup_events_calendar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================
    
    plugin_active = result.get('plugin_active', False)
    if plugin_active:
        score += 10
        feedback_parts.append("Plugin active")
    else:
        feedback_parts.append("FAIL: Plugin not active")

    venue_data = result.get('venue', {})
    venue_found = venue_data.get('found', False)
    venue_id = str(venue_data.get('id', ''))
    
    if venue_found and venue_id and venue_id != "null":
        score += 15
        feedback_parts.append("Venue created")
    else:
        feedback_parts.append("FAIL: Venue not found")

    events = result.get('events', {})
    events_configured = 0
    
    expected_data = [
        ("event1", "2026-06-01", 15),
        ("event2", "2026-06-10", 15),
        ("event3", "2026-06-15", 15)
    ]

    for event_key, expected_date, max_pts in expected_data:
        event = events.get(event_key, {})
        if event.get('found', False):
            event_score = 5  # Base points for existing
            
            # Check date
            start_date = event.get('start_date', '')
            if expected_date in start_date:
                event_score += 5
            else:
                feedback_parts.append(f"{event_key} wrong date ({start_date})")
                
            # Check venue linkage
            ev_venue_id = str(event.get('venue_id', ''))
            if venue_found and ev_venue_id == venue_id:
                event_score += 5
            else:
                feedback_parts.append(f"{event_key} not linked to correct venue")
                
            score += event_score
            if event_score == max_pts:
                events_configured += 1
                feedback_parts.append(f"{event_key} perfectly configured")
        else:
            feedback_parts.append(f"{event_key} missing")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=6)
            final_frame = get_final_screenshot(traj)
            
            # Trajectory analysis (15 pts)
            traj_analysis = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            if traj_analysis:
                if traj_analysis.get('plugin_installed'): vlm_score += 5
                if traj_analysis.get('venue_created'): vlm_score += 5
                if traj_analysis.get('events_created'): vlm_score += 5
            
            # Final state analysis (10 pts)
            final_analysis = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            if final_analysis:
                if final_analysis.get('events_plugin_visible'): vlm_score += 5
                if final_analysis.get('success_indicators'): vlm_score += 5
                
            # Cross-validation (5 pts)
            if plugin_active and events_configured >= 2 and traj_analysis and traj_analysis.get('events_created'):
                vlm_score += 5
                
            score += vlm_score
            feedback_parts.append(f"VLM score: {vlm_score}/30")
        except Exception as e:
            logger.warning(f"VLM execution failed: {e}")
            # Prorated fallback if VLM crashes
            score = int((score / 70) * 100)
            feedback_parts.append("VLM failed, score prorated")
    else:
        # Prorate if VLM not available
        score = int((score / 70) * 100)
        feedback_parts.append("VLM unavailable, score prorated")

    # Final pass determination
    key_criteria_met = plugin_active and venue_found and events_configured >= 2
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }