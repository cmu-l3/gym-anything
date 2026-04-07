#!/usr/bin/env python3
"""Verifier for build_template_driven_conference_schedule task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conference_schedule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/schedule_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # ================================================================
    # Criterion 1: SessionTemplate Exists & Content (30 points)
    # ================================================================
    template_text = result.get('template_text', '')
    if result.get('template_exists'):
        score += 10
        feedback_parts.append("SessionTemplate exists")
        
        # Check field transclusion syntax in the template
        has_time = "!!time" in template_text or 'field="time"' in template_text
        has_room = "!!room" in template_text or 'field="room"' in template_text
        has_speaker = "!!speaker" in template_text or 'field="speaker"' in template_text
        
        fields_found = sum([has_time, has_room, has_speaker])
        if fields_found == 3:
            score += 20
            feedback_parts.append("All custom fields (time, room, speaker) transcluded in template")
        elif fields_found > 0:
            score += 10
            feedback_parts.append(f"Partial field transclusion ({fields_found}/3 fields found)")
        else:
            feedback_parts.append("FAIL: Template missing field transclusions (!!time, etc.)")
    else:
        feedback_parts.append("FAIL: SessionTemplate not found")

    # ================================================================
    # Criterion 2: Dashboard Exists & Configuration (40 points)
    # ================================================================
    dashboard_text = result.get('dashboard_text', '')
    if result.get('dashboard_exists'):
        score += 10
        feedback_parts.append("Dashboard exists")
        
        # Check Dashboard Tag
        dash_tags = result.get('dashboard_tags', '')
        if 'Dashboard' in dash_tags or 'dashboard' in dash_tags.lower():
            score += 5
            feedback_parts.append("Dashboard properly tagged")
            
        # Check Dynamic List Widget configuration
        has_list_widget = "<$list" in dashboard_text
        has_tag_filter = "tag[MySchedule]" in dashboard_text
        has_sort = "sort[time]" in dashboard_text
        has_template_ref = 'template="SessionTemplate"' in dashboard_text or "template='SessionTemplate'" in dashboard_text or "template=SessionTemplate" in dashboard_text
        
        if has_list_widget and has_tag_filter and has_sort and has_template_ref:
            score += 25
            feedback_parts.append("Dashboard uses perfect dynamic <$list> widget")
        else:
            missing = []
            if not has_list_widget: missing.append("<$list>")
            if not has_tag_filter: missing.append("tag[MySchedule]")
            if not has_sort: missing.append("sort[time]")
            if not has_template_ref: missing.append("template=SessionTemplate")
            
            # Partial credit for widget configuration
            correct_components = 4 - len(missing)
            score += (correct_components * 5)
            feedback_parts.append(f"List widget incomplete. Missing: {', '.join(missing)}")
    else:
        feedback_parts.append("FAIL: My Conference Schedule dashboard not found")

    # ================================================================
    # Criterion 3: Sessions Properly Tagged (30 points)
    # ================================================================
    target_tag = "MySchedule"
    matrix_tagged = target_tag in result.get('matrix_tags', '')
    wayland_tagged = target_tag in result.get('wayland_tags', '')
    osm_tagged = target_tag in result.get('osm_tags', '')
    pg_tagged = target_tag in result.get('pg_tags', '')
    
    tagged_count = sum([matrix_tagged, wayland_tagged, osm_tagged, pg_tagged])
    
    if tagged_count == 4:
        score += 20
        feedback_parts.append("All 4 target sessions tagged properly")
    elif tagged_count > 0:
        score += (tagged_count * 5)
        feedback_parts.append(f"{tagged_count}/4 target sessions tagged")
    else:
        feedback_parts.append("FAIL: No target sessions tagged")

    # Anti-gaming: Ensure they didn't just tag EVERY tiddler
    total_tagged = result.get('total_tagged', 0)
    if total_tagged == 4 and tagged_count == 4:
        score += 10
        feedback_parts.append("Only the exactly specified 4 sessions were tagged")
    elif total_tagged > 4:
        feedback_parts.append(f"WARNING: Tagged {total_tagged} total tiddlers (expected exactly 4)")

    # ================================================================
    # VLM Verification (Optional cross-check of rendered visual state)
    # ================================================================
    from gym_anything.vlm import get_final_screenshot, query_vlm
    final_img = get_final_screenshot(traj)
    if final_img:
        prompt = """You are evaluating a TiddlyWiki dashboard.
Look at this screenshot. 
1. Is the "My Conference Schedule" tiddler visible?
2. Does it display a rendered list of conference sessions (e.g. Matrix 2.0, Wayland, PostgreSQL, OpenStreetMap)?
3. Are the specific fields (time, room, speaker) visible alongside the titles, proving a template was applied?

Return JSON:
{
  "dashboard_visible": true/false,
  "sessions_rendered": true/false,
  "template_applied": true/false
}"""
        try:
            vlm_res = query_vlm(images=[final_img], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('sessions_rendered') and parsed.get('template_applied'):
                    feedback_parts.append("VLM confirms template successfully rendered on screen")
        except Exception as e:
            logger.info(f"VLM verification skipped/failed: {e}")

    # Determine Pass/Fail
    # To pass, they must have created the template transclusion and set up the dashboard filter.
    key_criteria_met = (
        result.get('template_exists') and 
        result.get('dashboard_exists') and 
        (has_time or has_room or has_speaker) and 
        has_tag_filter
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }