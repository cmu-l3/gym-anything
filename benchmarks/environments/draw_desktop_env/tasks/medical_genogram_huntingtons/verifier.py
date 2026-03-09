#!/usr/bin/env python3
import json
import os
import sys

def verify_genogram(traj, env_info, task_info):
    """
    Verifies the medical genogram task based on XML analysis.
    Criteria:
    1. Files exist (drawio + png).
    2. Correct Gender Shapes (Male=Rect, Female=Ellipse).
    3. Correct Disease Status (Affected=Filled, Unaffected=White).
    4. Generational Hierarchy (Arthur/Betty < Charles/Diana < Alice).
    5. Proband indicator ('?').
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: API error"}

    # Load result
    result_path = "/tmp/task_result.json"
    local_path = "task_result.json"
    try:
        copy_from_env(result_path, local_path)
        with open(local_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {str(e)}"}
    finally:
        if os.path.exists(local_path):
            os.remove(local_path)

    score = 0
    feedback = []
    
    # 1. File Existence & Activity (20 pts)
    if data.get("drawio_exists") and data.get("drawio_created_during_task"):
        score += 10
        feedback.append("Draw.io file created.")
    elif data.get("drawio_exists"):
        score += 5
        feedback.append("Draw.io file exists but timestamp is old.")
    else:
        feedback.append("Draw.io file missing.")
        
    if data.get("png_exists"):
        score += 10
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    analysis = data.get("analysis", {})
    if analysis.get("error"):
        return {"passed": False, "score": score, "feedback": f"File analysis error: {analysis['error']}"}

    people = analysis.get("people", {})
    required_names = ["Arthur", "Betty", "Charles", "Diana", "Edward", "Alice", "Frank"]
    
    # Check if people found
    found_names = list(people.keys())
    if len(found_names) < 3:
        return {"passed": False, "score": score, "feedback": "Almost no family members labeled in diagram."}

    # 2. Gender Shapes (20 pts)
    # Male: Rect, Female: Ellipse
    males = ["Arthur", "Charles", "Edward", "Frank"]
    females = ["Betty", "Diana", "Alice"]
    gender_correct = 0
    total_checks = 0
    
    for name in males:
        if name in people:
            total_checks += 1
            # draw.io rectangles usually don't have 'ellipse' in style
            if people[name]['shape'] != 'ellipse': 
                gender_correct += 1
    
    for name in females:
        if name in people:
            total_checks += 1
            if people[name]['shape'] == 'ellipse':
                gender_correct += 1
                
    if total_checks > 0:
        gender_score = (gender_correct / total_checks) * 20
        score += gender_score
        feedback.append(f"Gender shapes: {gender_correct}/{total_checks} correct.")

    # 3. Disease Status (25 pts)
    # Affected: Arthur, Charles (Filled)
    # Unaffected: Betty, Diana, Edward, Frank, Alice (White/None)
    affected = ["Arthur", "Charles"]
    unaffected = ["Betty", "Diana", "Edward", "Frank"] # Alice is unknown status, usually empty or ?
    
    status_correct = 0
    status_checks = 0
    
    for name in affected:
        if name in people:
            status_checks += 1
            if people[name]['fill'] == 'filled':
                status_correct += 1
            else:
                feedback.append(f"{name} should be filled (Affected).")

    for name in unaffected:
        if name in people:
            status_checks += 1
            if people[name]['fill'] != 'filled':
                status_correct += 1
    
    if status_checks > 0:
        status_score = (status_correct / status_checks) * 25
        score += status_score
        feedback.append(f"Disease status fill: {status_correct}/{status_checks} correct.")

    # 4. Generational Hierarchy (15 pts)
    # Y(Arthur/Betty) < Y(Charles/Diana) < Y(Alice/Frank)
    # Lower Y value = Higher on page
    gens_ok = False
    try:
        # Average Y per generation
        gen1 = [people[n]['y'] for n in ["Arthur", "Betty"] if n in people]
        gen2 = [people[n]['y'] for n in ["Charles", "Diana", "Edward"] if n in people]
        gen3 = [people[n]['y'] for n in ["Alice", "Frank"] if n in people]
        
        if gen1 and gen2 and gen3:
            avg1 = sum(gen1)/len(gen1)
            avg2 = sum(gen2)/len(gen2)
            avg3 = sum(gen3)/len(gen3)
            
            if avg1 < avg2 < avg3:
                gens_ok = True
    except:
        pass

    if gens_ok:
        score += 15
        feedback.append("Generational hierarchy correct.")
    else:
        feedback.append("Generational layout incorrect or incomplete.")

    # 5. Deceased Status (10 pts)
    # Check for "lines" or "crosses" in the document total
    # Hard to map specifically to Arthur/Betty without complex spatial logic
    # We accept if "lines_count" >= 2 (for the two deceased people)
    lines_count = analysis.get("lines_count", 0)
    if lines_count >= 2:
        score += 10
        feedback.append("Deceased markers (diagonal lines/crosses) detected.")
    else:
        feedback.append(f"Missing deceased markers (expected diagonal lines/crosses, found {lines_count}).")

    # 6. Proband Indicator (10 pts)
    # Alice should have "?" in her text or label
    alice_data = people.get("Alice", {})
    if "?" in alice_data.get("text", ""):
        score += 10
        feedback.append("Proband Alice marked with '?'.")
    else:
        # Check if there's a "?" anywhere in the labels if not attached to Alice directly
        all_text = " ".join([p['text'] for p in people.values()])
        if "?" in all_text:
            score += 5
            feedback.append("Unknown status '?' found, but verify it applies to Alice.")
        else:
            feedback.append("Proband unknown status '?' missing.")

    return {
        "passed": score >= 70,
        "score": round(score),
        "feedback": " ".join(feedback)
    }