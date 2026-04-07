#!/usr/bin/env python3
"""Verifier for configure_wiki_identity_and_homepage task."""

import json
import tempfile
import os

def verify_configure_wiki(traj, env_info, task_info):
    """Verify that wiki global identity, homepage, and default tiddlers were correctly configured."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    
    # -------------------------------------------------------------------------
    # Criterion 1: Site Title (15 pts)
    # -------------------------------------------------------------------------
    site_title = result.get('site_title', '').strip()
    title_mtime = result.get('title_mtime', 0)
    if site_title == "Kafka Docs":
        score += 15
        feedback_parts.append("Site Title is correct")
    elif "kafka" in site_title.lower():
        score += 7
        feedback_parts.append(f"Site Title partially correct: {site_title}")
    else:
        feedback_parts.append(f"Site Title incorrect: '{site_title}'")
        
    # -------------------------------------------------------------------------
    # Criterion 2: Site Subtitle (15 pts)
    # -------------------------------------------------------------------------
    site_subtitle = result.get('site_subtitle', '').strip()
    subtitle_mtime = result.get('subtitle_mtime', 0)
    if site_subtitle == "Event Streaming Platform Reference":
        score += 15
        feedback_parts.append("Site Subtitle is correct")
    elif "event streaming" in site_subtitle.lower():
        score += 7
        feedback_parts.append(f"Site Subtitle partially correct: {site_subtitle}")
    else:
        feedback_parts.append(f"Site Subtitle incorrect: '{site_subtitle}'")
        
    # -------------------------------------------------------------------------
    # Criterion 3: Default Tiddlers (20 pts)
    # -------------------------------------------------------------------------
    default_tiddlers = result.get('default_tiddlers', '').strip()
    default_mtime = result.get('default_mtime', 0)
    if default_tiddlers == "[[Kafka Knowledge Base]]" or default_tiddlers == "Kafka Knowledge Base":
        score += 20
        feedback_parts.append("Default Tiddlers is correct")
    elif "Kafka Knowledge Base" in default_tiddlers:
        score += 10
        feedback_parts.append(f"Default Tiddlers partially correct: {default_tiddlers}")
    else:
        feedback_parts.append(f"Default Tiddlers incorrect: '{default_tiddlers}'")

    # -------------------------------------------------------------------------
    # Criterion 4 & 5: Homepage and Button (25 + 15 pts)
    # -------------------------------------------------------------------------
    homepage_exists = result.get('homepage_exists', False)
    homepage_mtime = result.get('homepage_mtime', 0)
    homepage_text = result.get('homepage_text', '')
    
    has_button = False
    has_message = False
    
    if homepage_exists and len(homepage_text) > 0:
        score += 10
        feedback_parts.append("Homepage tiddler exists with text")
        
        has_button = '<$button' in homepage_text
        has_message = 'tm-new-tiddler' in homepage_text
        has_label = 'Add Concept' in homepage_text
        
        if has_button and has_message:
            score += 15
            feedback_parts.append("Action button syntax found")
        elif has_button:
            score += 5
            feedback_parts.append("Button syntax found but missing tm-new-tiddler")
        else:
            feedback_parts.append("FAIL: Action button syntax not found")
            
        # Check Button Parameter Config
        has_title = 'New Concept' in homepage_text
        has_tags = 'Concept' in homepage_text
        
        config_score = 0
        if has_title:
            config_score += 7.5
        if has_tags:
            config_score += 7.5
            
        if config_score == 15:
            score += 15
            feedback_parts.append("Button parameters correct")
        elif config_score > 0:
            score += int(config_score)
            feedback_parts.append("Button parameters partially correct")
        else:
            feedback_parts.append("FAIL: Button parameters incorrect")
            
    else:
        feedback_parts.append("FAIL: Homepage tiddler not found or is empty")
        
    # -------------------------------------------------------------------------
    # Criterion 6: Anti-gaming Timestamp Checks (10 pts)
    # -------------------------------------------------------------------------
    gui_save = result.get('gui_save_detected', False)
    modifications = sum([
        title_mtime > task_start,
        subtitle_mtime > task_start,
        default_mtime > task_start,
        homepage_mtime > task_start
    ])
    
    if gui_save or modifications >= 2:
        score += 10
        feedback_parts.append("GUI interaction / modifications verified")
    else:
        feedback_parts.append("No/few file modifications detected during task time")
        
    # Set passed status based on threshold and critical requirements
    # Must achieve 70/100, have a homepage, have a button, and it must trigger new tiddlers, and default tiddler must point to it
    key_criteria_met = (
        homepage_exists and 
        has_button and 
        has_message and 
        ("Kafka Knowledge Base" in default_tiddlers)
    )
    
    passed = (score >= 70) and key_criteria_met
    
    if not key_criteria_met:
        feedback_parts.append("FAILED: Core critical criteria not met.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }