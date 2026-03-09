#!/usr/bin/env python3
"""
Verifier for add_retrofit_networking task.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_retrofit_networking(traj, env_info, task_info):
    """
    Verifies that the agent added Retrofit networking correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    feedback = []
    
    files = result.get('files', {})
    task_start = result.get('task_start', 0)

    # 1. Dependencies (15 pts)
    build_gradle = files.get('build_gradle', {}).get('content', '')
    deps_score = 0
    required_deps = [
        'retrofit', 'converter-moshi', 'moshi-kotlin', 'logging-interceptor', 'kotlinx-coroutines-android'
    ]
    found_deps = []
    for dep in required_deps:
        if dep in build_gradle:
            found_deps.append(dep)
            deps_score += 3
    
    score += deps_score
    feedback.append(f"Dependencies: {len(found_deps)}/5 found ({deps_score}/15 pts)")

    # 2. Permission (10 pts)
    manifest = files.get('manifest', {}).get('content', '')
    if 'android.permission.INTERNET' in manifest:
        score += 10
        feedback.append("Internet permission added (10/10 pts)")
    else:
        feedback.append("Internet permission MISSING (0/10 pts)")

    # 3. Post Model (15 pts)
    post_content = files.get('post_model', {}).get('content', '')
    if post_content:
        # Check for data class and fields
        if 'data class Post' in post_content and 'val id: Int' in post_content and 'val title: String' in post_content:
            score += 15
            feedback.append("Post model valid (15/15 pts)")
        else:
            score += 5 # Partial credit for existence
            feedback.append("Post model exists but missing fields/structure (5/15 pts)")
    else:
        feedback.append("Post model not found (0/15 pts)")

    # 4. API Service (20 pts)
    service_content = files.get('api_service', {}).get('content', '')
    if service_content:
        # Check for interface and methods
        service_points = 0
        if 'interface PostApiService' in service_content: service_points += 5
        if '@GET' in service_content: service_points += 5
        if 'getPosts' in service_content: service_points += 5
        if 'suspend fun' in service_content: service_points += 5
        
        score += service_points
        feedback.append(f"API Service structure ({service_points}/20 pts)")
    else:
        feedback.append("API Service not found (0/20 pts)")

    # 5. API Client (20 pts)
    client_content = files.get('api_client', {}).get('content', '')
    if client_content:
        client_points = 0
        if 'object ApiClient' in client_content: client_points += 5
        if 'Retrofit.Builder' in client_content: client_points += 5
        if 'MoshiConverterFactory' in client_content: client_points += 5
        if 'jsonplaceholder.typicode.com' in client_content: client_points += 5
        
        score += client_points
        feedback.append(f"API Client structure ({client_points}/20 pts)")
    else:
        feedback.append("API Client not found (0/20 pts)")

    # 6. Build Success (15 pts)
    build_success = result.get('build', {}).get('success', False)
    if build_success:
        score += 15
        feedback.append("Gradle build SUCCESS (15/15 pts)")
    else:
        feedback.append("Gradle build FAILED (0/15 pts)")

    # 7. VLM Trajectory (5 pts)
    # Simple check if any files were modified after task start
    files_modified = any(
        f.get('mtime', 0) > task_start 
        for f in files.values()
    )
    if files_modified:
        score += 5
        feedback.append("Activity detected (5/5 pts)")
    else:
        feedback.append("No file modifications detected (0/5 pts)")

    return {
        "passed": score >= 60 and build_success,
        "score": score,
        "feedback": " | ".join(feedback)
    }