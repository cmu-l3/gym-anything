#!/usr/bin/env python3
import json
import os
import tempfile

def verify_gitlab_c4_diagram(traj, env_info, task_info):
    """
    Verifies the GitLab C4 Container Diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: File Existence & Modification (10 pts)
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "The .drawio file was not saved."}
    
    if not result.get('file_modified'):
        feedback.append("Warning: File timestamp indicates it wasn't modified during task.")
    else:
        score += 10
        feedback.append("File saved successfully.")

    analysis = result.get('analysis', {})
    
    # Check 2: Components Found (25 pts)
    # Target: 10 specific components. Partial credit allowed.
    found_comps = analysis.get('found_components', [])
    comp_count = len(found_comps)
    if comp_count >= 8:
        score += 25
        feedback.append(f"Excellent! Found {comp_count}/10 GitLab components.")
    elif comp_count >= 5:
        score += 15
        feedback.append(f"Good. Found {comp_count}/10 GitLab components.")
    elif comp_count >= 1:
        score += 5
        feedback.append(f"Found only {comp_count}/10 components. Check spelling?")
    else:
        feedback.append("No correct GitLab component names found.")

    # Check 3: Relationship Edges (15 pts)
    edges = analysis.get('num_edges', 0)
    if edges >= 12:
        score += 15
        feedback.append(f"Sufficient connections ({edges}).")
    elif edges >= 6:
        score += 7
        feedback.append(f"Some connections found ({edges}), but diagram looks incomplete.")
    else:
        feedback.append("Very few connections drawn.")

    # Check 4: Pages (10 pts)
    # Expecting 2 pages
    pages = analysis.get('num_pages', 0)
    if pages >= 2:
        score += 10
        feedback.append("Correctly created multi-page diagram.")
    else:
        feedback.append("Task required 2 pages (Context + Container). Only 1 found.")

    # Check 5: C4 Structure (Boundary + Actors) (15 pts)
    if analysis.get('has_boundary'):
        score += 10
        feedback.append("System boundary detected.")
    
    if analysis.get('has_actors'):
        score += 5
        feedback.append("Actors detected.")

    # Check 6: Protocols (10 pts)
    # HTTPS, gRPC, TCP, etc.
    found_protos = analysis.get('found_protocols', [])
    if len(found_protos) >= 3:
        score += 10
        feedback.append(f"Protocol labels found: {', '.join(found_protos)}")
    elif len(found_protos) > 0:
        score += 5
        feedback.append(f"Some protocol labels found.")

    # Check 7: PNG Export (15 pts)
    if result.get('png_exists'):
        png_size = result.get('png_size', 0)
        if png_size > 2000: # Arbitrary small limit to ensure not empty
            score += 15
            feedback.append("PNG exported successfully.")
        else:
            score += 5
            feedback.append("PNG exported but seems empty/too small.")
    else:
        feedback.append("PNG export missing.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }