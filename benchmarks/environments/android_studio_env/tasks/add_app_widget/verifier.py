#!/usr/bin/env python3
"""
Verifier for add_app_widget task.
"""

import json
import logging
import os
import re
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_app_widget(traj, env_info, task_info):
    """
    Verify the implementation of an Android App Widget.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    expected_ids = metadata.get('expected_ids', ["widget_city_name", "widget_temperature", "widget_condition"])

    score = 0
    feedback_parts = []
    
    # --- 1. Widget Layout Verification (20 pts) ---
    layout_content = result.get('layout_content', '')
    if result.get('layout_exists') and layout_content:
        score += 5
        # Parse XML to check IDs
        try:
            # Remove potential non-xml trash if cat captured weird stuff, though unlikely with read_file_content
            root = ET.fromstring(layout_content)
            
            # Check for IDs
            ids_found = 0
            for elem in root.iter():
                attrib_id = elem.get('{http://schemas.android.com/apk/res/android}id', '')
                for expected_id in expected_ids:
                    if expected_id in attrib_id:
                        ids_found += 1
            
            # Unique IDs found (approximate check logic)
            found_ids_set = set()
            for elem in root.iter():
                attrib_id = elem.get('{http://schemas.android.com/apk/res/android}id', '')
                if 'widget_city_name' in attrib_id: found_ids_set.add('city')
                if 'widget_temperature' in attrib_id: found_ids_set.add('temp')
                if 'widget_condition' in attrib_id: found_ids_set.add('cond')
            
            if len(found_ids_set) >= 3:
                score += 15
                feedback_parts.append("Layout: Valid with all required IDs.")
            else:
                score += 5
                feedback_parts.append(f"Layout: Missing some IDs. Found: {found_ids_set}")
                
        except ET.ParseError:
            feedback_parts.append("Layout: File exists but invalid XML.")
    else:
        feedback_parts.append("Layout: File missing.")

    # --- 2. Widget Metadata Verification (20 pts) ---
    info_content = result.get('info_content', '')
    if result.get('info_exists') and info_content:
        score += 5
        try:
            root = ET.fromstring(info_content)
            if root.tag == 'appwidget-provider':
                score += 5
                # Check attributes
                attribs = root.attrib
                # Mapping android namespace usually requires full string or ignoring ns
                # Simpler: check if keys containing 'minWidth', 'minHeight' exist
                has_dims = any('minWidth' in k for k in attribs) and any('minHeight' in k for k in attribs)
                has_update = any('updatePeriodMillis' in k for k in attribs)
                has_layout = any('initialLayout' in k for k in attribs)
                
                if has_dims and has_update and has_layout:
                    score += 10
                    feedback_parts.append("Metadata: Valid configuration.")
                else:
                    score += 5
                    feedback_parts.append("Metadata: Missing required attributes.")
            else:
                feedback_parts.append("Metadata: Invalid root tag.")
        except ET.ParseError:
            feedback_parts.append("Metadata: Invalid XML.")
    else:
        feedback_parts.append("Metadata: File missing.")

    # --- 3. Provider Class Verification (20 pts) ---
    provider_content = result.get('provider_content', '')
    if result.get('provider_exists') and provider_content:
        score += 5
        # Check inheritance
        if 'AppWidgetProvider' in provider_content:
            score += 5
            # Check onUpdate
            if 'onUpdate' in provider_content:
                score += 5
                # Check RemoteViews
                if 'RemoteViews' in provider_content:
                    score += 5
                    feedback_parts.append("Provider: Code structure looks correct.")
                else:
                    feedback_parts.append("Provider: Missing RemoteViews usage.")
            else:
                feedback_parts.append("Provider: Missing onUpdate override.")
        else:
            feedback_parts.append("Provider: Does not extend AppWidgetProvider.")
    else:
        feedback_parts.append("Provider: File missing.")

    # --- 4. Manifest Registration Verification (20 pts) ---
    manifest_content = result.get('manifest_content', '')
    if manifest_content:
        # Simple text check usually sufficient for manifest snippets
        if 'WeatherWidgetProvider' in manifest_content and '<receiver' in manifest_content:
            score += 10
            if 'android.appwidget.action.APPWIDGET_UPDATE' in manifest_content:
                score += 5
                if 'android.appwidget.provider' in manifest_content:
                    score += 5
                    feedback_parts.append("Manifest: Registration correct.")
                else:
                    feedback_parts.append("Manifest: Missing metadata tag.")
            else:
                feedback_parts.append("Manifest: Missing intent action.")
        else:
            feedback_parts.append("Manifest: Receiver not registered.")
    else:
        feedback_parts.append("Manifest: Content empty.")

    # --- 5. Build Success (20 pts) ---
    if result.get('build_success'):
        score += 20
        feedback_parts.append("Build: Success.")
    else:
        feedback_parts.append("Build: Failed.")

    # Anti-gaming check
    if not result.get('layout_created_during_task') and not result.get('manifest_modified'):
        score = 0
        feedback_parts.append("Anti-gaming: No files created/modified during task.")

    passed = score >= 60 and result.get('build_success')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }