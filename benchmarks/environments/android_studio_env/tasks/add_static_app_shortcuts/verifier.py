#!/usr/bin/env python3
"""
Verifier for add_static_app_shortcuts task.

Scoring (100 points):
1. shortcuts.xml exists and is valid XML (10 pts)
2. shortcuts.xml contains 2 shortcuts with correct IDs (20 pts)
3. "New Note" shortcut has correct Icon, Intent, Target (15 pts)
4. "Search" shortcut has correct Icon, Intent, Target (15 pts)
5. Manifest contains <meta-data> linking to shortcuts (20 pts)
6. String resources defined (10 pts)
7. Build succeeds (10 pts)
"""

import json
import logging
import os
import tempfile
import xml.etree.ElementTree as ET
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
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

def verify_add_static_app_shortcuts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Read result from export script
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    shortcuts_content = result.get("shortcuts_content", "")
    manifest_content = result.get("manifest_content", "")
    strings_content = result.get("strings_content", "")
    build_success = result.get("build_success", False)
    
    score = 0
    feedback_parts = []
    
    # 1. Verify shortcuts.xml existence and validity (10 pts)
    shortcuts_root = None
    if shortcuts_content:
        try:
            # Strip potential whitespace/encoding issues
            shortcuts_root = ET.fromstring(shortcuts_content)
            if shortcuts_root.tag == "shortcuts":
                score += 10
                feedback_parts.append("shortcuts.xml valid")
            else:
                feedback_parts.append("shortcuts.xml root is not <shortcuts>")
        except ET.ParseError:
            feedback_parts.append("shortcuts.xml is not valid XML")
    else:
        feedback_parts.append("shortcuts.xml not found")

    # 2. Verify Shortcuts Content (50 pts total)
    if shortcuts_root is not None:
        ns = {'android': 'http://schemas.android.com/apk/res/android'}
        # Register namespace for findall
        # ET in python < 3.8 often struggles with default namespaces in attributes if not handled carefully
        # We'll iterate and check attributes manually to be robust against namespace variations
        
        shortcuts = shortcuts_root.findall("shortcut")
        
        # Helper to get attr with namespace
        def get_android_attr(elem, attr_name):
            return elem.get(f"{{http://schemas.android.com/apk/res/android}}{attr_name}")

        new_note_found = False
        search_found = False
        
        for s in shortcuts:
            sid = get_android_attr(s, "shortcutId")
            
            # Check "New Note" (ID: shortcut_new_note)
            if sid == "shortcut_new_note":
                new_note_found = True
                score += 10
                
                # Icon
                icon = get_android_attr(s, "icon")
                if icon == "@drawable/ic_add":
                    score += 5
                else:
                    feedback_parts.append(f"New Note icon incorrect: {icon}")
                
                # Intent
                intent = s.find("intent")
                if intent is not None:
                    action = get_android_attr(intent, "action")
                    target_pkg = get_android_attr(intent, "targetPackage")
                    target_class = get_android_attr(intent, "targetClass")
                    
                    if action == "com.example.quicknotes.CREATE_NOTE":
                        score += 5
                    if target_pkg == "com.example.quicknotes" and target_class == "com.example.quicknotes.MainActivity":
                        score += 5
                else:
                    feedback_parts.append("New Note intent missing")

            # Check "Search" (ID: shortcut_search)
            elif sid == "shortcut_search":
                search_found = True
                score += 10
                
                # Icon
                icon = get_android_attr(s, "icon")
                if icon == "@drawable/ic_search":
                    score += 5
                else:
                    feedback_parts.append(f"Search icon incorrect: {icon}")
                
                # Intent
                intent = s.find("intent")
                if intent is not None:
                    action = get_android_attr(intent, "action")
                    target_pkg = get_android_attr(intent, "targetPackage")
                    target_class = get_android_attr(intent, "targetClass")
                    
                    if action == "com.example.quicknotes.SEARCH":
                        score += 5
                    if target_pkg == "com.example.quicknotes" and target_class == "com.example.quicknotes.MainActivity":
                        score += 5
                else:
                    feedback_parts.append("Search intent missing")
        
        if not new_note_found:
            feedback_parts.append("ID shortcut_new_note not found")
        if not search_found:
            feedback_parts.append("ID shortcut_search not found")

    # 3. Verify Manifest Configuration (20 pts)
    if manifest_content:
        # Simple regex or substring check is often more robust than namespace parsing for manifests
        if 'android.app.shortcuts' in manifest_content and '@xml/shortcuts' in manifest_content:
            score += 20
            feedback_parts.append("Manifest meta-data configured")
        else:
            feedback_parts.append("Manifest missing shortcuts meta-data")
    
    # 4. Verify Strings (10 pts)
    # Check if they created string resources (looked up by @string reference in XML usually, 
    # but here we just check if strings.xml was updated with relevant keywords)
    if "New Note" in strings_content and "Search" in strings_content:
        score += 10
        feedback_parts.append("String resources found")
    elif strings_content:
         # Agent might have used different names, check if shortcuts.xml uses @string
         if shortcuts_root is not None:
             uses_string_refs = True
             for s in shortcuts_root.findall("shortcut"):
                 label = s.get(f"{{http://schemas.android.com/apk/res/android}}shortcutShortLabel")
                 if label and not label.startswith("@string/"):
                     uses_string_refs = False
             
             if uses_string_refs: 
                 score += 10 # Giving benefit of doubt if they used refs, assuming build passed
                 feedback_parts.append("String refs used")
             else:
                 feedback_parts.append("Hardcoded strings or missing resources")

    # 5. Build Success (10 pts)
    if build_success:
        score += 10
        feedback_parts.append("Build successful")
    else:
        feedback_parts.append("Build failed")

    # VLM Verification (Bonus/Confirmation)
    # Using trajectory frames to verify they actually used the IDE
    # This is a coding task, so programmatic verification is primary, 
    # but we check if files were modified during task as anti-gaming
    if not result.get("shortcuts_modified", False):
        score = min(score, 20) # Cap score if file wasn't modified during task
        feedback_parts.append("ANTI-GAMING: shortcuts.xml not modified during task")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }