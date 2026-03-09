#!/usr/bin/env python3
"""
Verifier for add_kotlin_serialization task.

Criteria:
1. Serialization Plugin applied (Project or App level).
2. Dependency `kotlinx-serialization-json` added.
3. `Owner.kt` exists and has @Serializable and correct @SerialName annotations.
4. `GitHubRepo.kt` exists and has @Serializable and correct @SerialName annotations.
5. Project compiles successfully.
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_kotlin_serialization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    # 1. Plugin Configuration (15 pts)
    # Check both project and app build.gradle.kts for plugin definition
    plugin_pattern = r'kotlin\("plugin\.serialization"\)|id\("org\.jetbrains\.kotlin\.plugin\.serialization"\)'
    app_gradle = result.get("app_build_gradle_content", "")
    proj_gradle = result.get("project_build_gradle_content", "")
    
    has_plugin = re.search(plugin_pattern, app_gradle) or re.search(plugin_pattern, proj_gradle)
    if has_plugin:
        score += 15
        feedback.append("Serialization plugin applied (15/15)")
    else:
        feedback.append("Serialization plugin MISSING (0/15)")

    # 2. Dependency Check (10 pts)
    dep_pattern = r'implementation\("org\.jetbrains\.kotlinx:kotlinx-serialization-json:.*"\)'
    if re.search(dep_pattern, app_gradle):
        score += 10
        feedback.append("Serialization dependency added (10/10)")
    else:
        feedback.append("Serialization dependency MISSING (0/10)")

    # 3. Owner.kt Checks (20 pts)
    owner_content = result.get("owner_kt_content", "")
    if result.get("owner_kt_exists"):
        if "@Serializable" in owner_content:
            score += 5
            feedback.append("Owner.kt: @Serializable present (5/5)")
        else:
            feedback.append("Owner.kt: @Serializable MISSING (0/5)")
            
        # Check specific fields
        if '@SerialName("avatar_url")' in owner_content and 'val avatarUrl' in owner_content:
            score += 5
            feedback.append("Owner.kt: avatar_url mapped (5/5)")
        else:
            feedback.append("Owner.kt: avatar_url mapping incorrect (0/5)")
            
        if '@SerialName("html_url")' in owner_content and 'val htmlUrl' in owner_content:
            score += 5
            feedback.append("Owner.kt: html_url mapped (5/5)")
        else:
            feedback.append("Owner.kt: html_url mapping incorrect (0/5)")
            
        # Basic check for existence
        score += 5 
        feedback.append("Owner.kt created (5/5)")
    else:
        feedback.append("Owner.kt NOT created (0/20)")

    # 4. GitHubRepo.kt Checks (30 pts)
    repo_content = result.get("github_repo_kt_content", "")
    if result.get("github_repo_kt_exists"):
        if "@Serializable" in repo_content:
            score += 5
            feedback.append("GitHubRepo.kt: @Serializable present (5/5)")
        else:
            feedback.append("GitHubRepo.kt: @Serializable MISSING (0/5)")

        # Check a few critical mappings
        mappings = [
            ('full_name', 'fullName'),
            ('stargazers_count', 'stargazersCount'),
            ('forks_count', 'forksCount'),
            ('open_issues_count', 'openIssuesCount')
        ]
        
        mapping_score = 0
        for json_field, kotlin_field in mappings:
            if f'@SerialName("{json_field}")' in repo_content and f'val {kotlin_field}' in repo_content:
                mapping_score += 4
        
        if mapping_score >= 16:
            mapping_score = 15 # Max 15 for mappings
            
        score += mapping_score
        feedback.append(f"GitHubRepo.kt: Mappings score ({mapping_score}/15)")
        
        # Check Reference to Owner
        if 'val owner: Owner' in repo_content:
            score += 5
            feedback.append("GitHubRepo.kt: References Owner class (5/5)")
        else:
            feedback.append("GitHubRepo.kt: Does not reference Owner class properly (0/5)")
            
        # Existence
        score += 5
        feedback.append("GitHubRepo.kt created (5/5)")
    else:
        feedback.append("GitHubRepo.kt NOT created (0/30)")

    # 5. Build Success (25 pts)
    if result.get("build_success"):
        score += 25
        feedback.append("Project compiles successfully (25/25)")
    else:
        feedback.append("Project FAILED to compile (0/25)")

    # Final check
    passed = score >= 70 and result.get("build_success")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }