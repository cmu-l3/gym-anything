#!/usr/bin/env python3
"""
Verifier for Workspace Setup task.

Scoring Breakdown (100 points):
- Folder "Dev Tools" created on Favorites Bar: 15 pts
- Bookmarks Added (3 specific URLs present): 15 pts
- Titles Renamed (Repo, Help, Build): 15 pts
- Startup Page Set (restore_on_startup=4 + github URL): 25 pts
- Backup Created (file exists): 15 pts
- Backup Valid (contains correct data): 15 pts

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_workspace_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Retrieve result from container
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

    # 1. Verify Folder Creation (15 pts)
    folder_data = result.get("dev_tools_folder")
    if folder_data and folder_data.get("name") == "Dev Tools":
        score += 15
        feedback.append("Success: 'Dev Tools' folder found.")
    else:
        feedback.append("Fail: 'Dev Tools' folder not found on Favorites Bar.")

    # 2. Verify Bookmarks Content & Renaming (30 pts total)
    bookmarks = result.get("bookmarks_found", [])
    
    # Expected mapping
    expected = {
        "github.com": "Repo",
        "stackoverflow.com": "Help",
        "jenkins.io": "Build"
    }
    
    urls_found = 0
    names_correct = 0
    
    for bm in bookmarks:
        url = bm.get("url", "").lower()
        name = bm.get("name", "")
        
        # Check URL matches any expected domain
        matched_key = None
        for domain, expected_name in expected.items():
            if domain in url:
                matched_key = domain
                urls_found += 1
                
                # Check name exact match
                if name == expected_name:
                    names_correct += 1
                break
    
    # URL points (15 pts for 3 urls, 5 each)
    url_score = min(urls_found * 5, 15)
    score += url_score
    if url_score < 15:
        feedback.append(f"Partial: Found {urls_found}/3 correct bookmark URLs.")
    else:
        feedback.append("Success: All 3 bookmark URLs found.")

    # Name points (15 pts for 3 names, 5 each)
    name_score = min(names_correct * 5, 15)
    score += name_score
    if name_score < 15:
        feedback.append(f"Partial: {names_correct}/3 bookmarks correctly renamed.")
    else:
        feedback.append("Success: All bookmarks correctly renamed.")

    # 3. Verify Startup Config (25 pts)
    # restore_on_startup should be 4 (Open specific pages)
    # startup_urls should contain github
    startup = result.get("startup_config", {})
    restore_mode = startup.get("restore_on_startup")
    startup_urls = startup.get("startup_urls", [])
    
    startup_correct = False
    # Mode 4 is "Open specific pages". 
    # Sometimes agents might set it to "Continue where you left off" (1) and just leave tabs open, 
    # but the task asks to "Configure Edge to open a specific page on startup".
    if restore_mode == 4:
        # Check URLs
        has_github = any("github.com" in u for u in startup_urls)
        if has_github:
            score += 25
            startup_correct = True
            feedback.append("Success: Startup page configured correctly.")
        else:
            feedback.append("Fail: Startup mode correct, but GitHub URL missing.")
    else:
        feedback.append(f"Fail: Startup mode incorrect (Expected 4, got {restore_mode}).")

    # 4. Verify Export (30 pts total)
    export = result.get("export_info", {})
    
    # Exists & Fresh (15 pts)
    if export.get("exists") and export.get("created_after_start"):
        score += 15
        feedback.append("Success: Export file created.")
        
        # Content Valid (15 pts)
        if export.get("content_valid"):
            score += 15
            feedback.append("Success: Export file content valid.")
        else:
            feedback.append("Fail: Export file content missing required bookmarks.")
    else:
        feedback.append("Fail: Export file missing or created before task start.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }