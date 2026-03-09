#!/usr/bin/env python3
"""
Verifier for configure_task_dependencies task.

Verifies that:
1. The dependency graph exists.
2. 'Provision Infrastructure' is a parent to both DB and Web tasks (Fan-Out).
3. 'Deploy Application' is a child of both DB and Web tasks (Fan-In).
4. No cyclical or incorrect serial dependencies exist.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_task_dependencies(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    task_titles = metadata.get('task_titles', {})
    
    # Expected Tasks
    t1_title = "Provision Infrastructure"
    t2_title = "Configure Database Cluster"
    t3_title = "Configure Web Server Nodes"
    t4_title = "Deploy Application Artifacts"

    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Database query error: {result['error']}"}

    tasks = result.get('tasks', [])
    dependencies = result.get('dependencies', [])
    
    if not tasks:
        return {"passed": False, "score": 0, "feedback": "No tasks found for the target request."}
    
    if not dependencies:
        return {"passed": False, "score": 0, "feedback": "No dependencies configured."}

    # 2. Map Task IDs to Titles for easier verification
    id_to_title = {}
    title_to_id = {}
    
    for t in tasks:
        tid = t.get('task_wo_id')
        title = t.get('task_title')
        if tid and title:
            id_to_title[tid] = title
            title_to_id[title] = tid # Assuming unique titles for this request

    # Verify all 4 required tasks exist
    missing_tasks = []
    for title in [t1_title, t2_title, t3_title, t4_title]:
        if title not in title_to_id:
            missing_tasks.append(title)
    
    if missing_tasks:
        return {"passed": False, "score": 0, "feedback": f"Missing required tasks: {', '.join(missing_tasks)}"}

    # 3. Build Dependency Graph (Adjacency List)
    # Graph: Parent -> [Children]
    graph = {title: set() for title in [t1_title, t2_title, t3_title, t4_title]}
    
    # Graph: Child -> [Parents] (for checking Fan-In)
    reverse_graph = {title: set() for title in [t1_title, t2_title, t3_title, t4_title]}

    dep_count = 0
    for dep in dependencies:
        parent_id = dep.get('parent_task_id')
        child_id = dep.get('child_task_id')
        
        if parent_id in id_to_title and child_id in id_to_title:
            p_title = id_to_title[parent_id]
            c_title = id_to_title[child_id]
            
            graph[p_title].add(c_title)
            reverse_graph[c_title].add(p_title)
            dep_count += 1

    feedback_parts.append(f"Found {dep_count} dependency links.")
    score += 20 # Base points for having dependencies

    # 4. Verify Fan-Out (Provision -> DB & Web)
    # Check if Provision is parent to DB
    fan_out_score = 0
    if t2_title in graph[t1_title]:
        fan_out_score += 15
        feedback_parts.append("Correct: Provision -> Database")
    else:
        feedback_parts.append("Missing: Provision -> Database")

    # Check if Provision is parent to Web
    if t3_title in graph[t1_title]:
        fan_out_score += 15
        feedback_parts.append("Correct: Provision -> Web Server")
    else:
        feedback_parts.append("Missing: Provision -> Web Server")
    
    score += fan_out_score

    # 5. Verify Fan-In (DB & Web -> Deploy)
    # Check if Deploy has DB as parent
    fan_in_score = 0
    if t2_title in reverse_graph[t4_title]:
        fan_in_score += 15
        feedback_parts.append("Correct: Database -> Deploy")
    else:
        feedback_parts.append("Missing: Database -> Deploy")

    # Check if Deploy has Web as parent
    if t3_title in reverse_graph[t4_title]:
        fan_in_score += 15
        feedback_parts.append("Correct: Web Server -> Deploy")
    else:
        feedback_parts.append("Missing: Web Server -> Deploy")
        
    score += fan_in_score

    # 6. Check for Forbidden/Incorrect Links (Anti-Gaming / Logic Check)
    # Example: DB shouldn't depend on Web, or vice versa (they should be parallel)
    penalty = 0
    
    # Check if DB depends on Web
    if t3_title in reverse_graph[t2_title]:
        penalty += 10
        feedback_parts.append("Error: Database depends on Web Server (Should be parallel)")
        
    # Check if Web depends on DB
    if t2_title in reverse_graph[t3_title]:
        penalty += 10
        feedback_parts.append("Error: Web Server depends on Database (Should be parallel)")
        
    # Check if Provision depends on anything
    if reverse_graph[t1_title]:
        penalty += 10
        feedback_parts.append("Error: Provision task should be the start (has parents)")

    # Check if Deploy is a parent to anything
    if graph[t4_title]:
        penalty += 10
        feedback_parts.append("Error: Deploy task should be the end (has children)")

    if penalty == 0:
        score += 20
        feedback_parts.append("Logic Check: Structure is valid (Parallel execution preserved)")
    else:
        score = max(0, score - penalty)

    # Final Evaluation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }