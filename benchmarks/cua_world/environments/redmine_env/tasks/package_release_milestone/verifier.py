#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_package_release_milestone(traj, env_info, task_info):
    """
    Verifies that the agent created the version, linked the wiki, and assigned the correct issues.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_version_name = metadata.get('target_version_name', "Permitting Complete")
    wiki_title = metadata.get('wiki_title', "Permitting_Summary")
    target_issues = set(metadata.get('target_issues', []))
    active_distractors = set(metadata.get('distractor_issues_active', []))
    versioned_distractors = set(metadata.get('distractor_issues_versioned', []))

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    max_score = 100

    # 1. Verify Version Creation (20 pts)
    versions = data.get('versions', {}).get('versions', [])
    created_version = next((v for v in versions if v['name'] == target_version_name), None)
    
    version_id = None
    if created_version:
        score += 10
        feedback.append(f"Version '{target_version_name}' created.")
        version_id = created_version['id']
        
        # Check attributes
        if created_version.get('status') == 'locked':
            score += 10
            feedback.append("Version status is 'locked'.")
        else:
            feedback.append(f"Version status is '{created_version.get('status')}' (expected 'locked').")
            
        # Check wiki link (API sometimes returns 'wiki_page_title', check structure)
        # The standard Redmine API version object might just have 'wiki_page_title' if extended, 
        # or we might need to check if the wiki page links back. 
        # Usually versions.json includes 'wiki_page_title' if set.
        if created_version.get('wiki_page_title') == wiki_title:
            # Score this under Wiki section
            feedback.append(f"Version linked to wiki page '{wiki_title}'.")
        else:
            # Note failure but don't deduct yet
            pass
    else:
        feedback.append(f"Version '{target_version_name}' NOT found.")

    # 2. Verify Wiki Page (20 pts)
    wiki_page = data.get('wiki_page', {}).get('wiki_page', {})
    if wiki_page and wiki_page.get('title') == wiki_title:
        score += 10
        feedback.append(f"Wiki page '{wiki_title}' created.")
        
        # Check text content
        text = wiki_page.get('text', "")
        if "environmental and regulatory permits" in text:
            score += 5
            feedback.append("Wiki content is correct.")
        
        # Check linkage (from version side or wiki side)
        # If version had the link, we give points here
        if created_version and created_version.get('wiki_page_title') == wiki_title:
            score += 5
            feedback.append("Wiki correctly linked to Version.")
        else:
            feedback.append("Wiki NOT linked to Version correctly.")
    else:
        feedback.append(f"Wiki page '{wiki_title}' NOT found.")

    # 3. Verify Issue Assignment (60 pts)
    issues = data.get('issues', {}).get('issues', [])
    
    # Track counts
    correctly_moved = 0
    incorrectly_moved_active = 0
    incorrectly_moved_versioned = 0
    
    for issue in issues:
        subject = issue.get('subject')
        current_version_id = issue.get('fixed_version', {}).get('id')
        current_version_name = issue.get('fixed_version', {}).get('name')
        
        # Check Target Issues
        if subject in target_issues:
            if current_version_name == target_version_name:
                correctly_moved += 1
            else:
                feedback.append(f"Issue '{subject}' NOT moved to target version.")
        
        # Check Active Distractors (Should have NO version)
        elif subject in active_distractors:
            if current_version_id is not None:
                incorrectly_moved_active += 1
                feedback.append(f"Active issue '{subject}' wrongly assigned to '{current_version_name}'.")
        
        # Check Versioned Distractors (Should stay in 'Survey Phase 1')
        elif subject in versioned_distractors:
            if current_version_name != "Survey Phase 1":
                incorrectly_moved_versioned += 1
                feedback.append(f"Versioned issue '{subject}' wrongly moved from 'Survey Phase 1'.")

    # Scoring Issues
    # 30 pts for moving targets (approx 7.5 per issue for 4 issues)
    if len(target_issues) > 0:
        move_score = (correctly_moved / len(target_issues)) * 30
        score += move_score
        if correctly_moved == len(target_issues):
            feedback.append(f"All {correctly_moved} target issues correctly moved.")
    
    # 30 pts for safety (Distractors)
    # Deduct 5 pts for each mistake, min 0
    safety_deduction = (incorrectly_moved_active + incorrectly_moved_versioned) * 5
    safety_score = max(0, 30 - safety_deduction)
    score += safety_score
    
    if safety_deduction == 0:
        feedback.append("No distractor issues were incorrectly modified.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }