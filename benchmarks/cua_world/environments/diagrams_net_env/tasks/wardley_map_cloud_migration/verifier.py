#!/usr/bin/env python3
import json
import sys

def verify_wardley_map(traj, env_info, task_info):
    """
    Verifies the Wardley Map task based on file analysis and metadata.
    """
    # 1. Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy unavailable"}

    try:
        # Save result.json to a temp file
        import tempfile
        import os
        
        fd, temp_path = tempfile.mkstemp()
        os.close(fd)
        
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            data = json.load(f)
        os.remove(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    # 2. Extract Data
    analysis = data.get("analysis", {})
    pdf_exists = data.get("pdf_exists", False)
    
    if not analysis.get("valid_xml"):
        return {"passed": False, "score": 0, "feedback": "Could not parse diagram file. Ensure it was saved correctly."}

    # 3. Scoring Criteria
    score = 0
    feedback = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    expected_components = metadata.get('expected_components', [])
    min_shapes = metadata.get('min_shapes', 18)
    
    # Criterion 1: File Modification (Anti-Gaming)
    if analysis.get("modified_after_start"):
        score += 5
    else:
        feedback.append("Warning: Diagram file not modified after task start.")

    # Criterion 2: Shape Count (Base axes has ~15 shapes, we expect +18 components + legends/annotations)
    # The starter file has 15 shapes. The agent adds 18 nodes + labels.
    # We look for a significant increase.
    total_shapes = analysis.get("total_shapes", 0)
    # 15 (base) + 15 (minimum effort) = 30
    if total_shapes >= 30:
        score += 15
        feedback.append(f"Shape count good ({total_shapes}).")
    elif total_shapes >= 20:
        score += 8
        feedback.append(f"Shape count low ({total_shapes}).")
    else:
        feedback.append(f"Insufficient shapes ({total_shapes}).")

    # Criterion 3: Component Labels Matching
    # Normalize labels for fuzzy matching
    found_labels = [l.lower() for l in analysis.get("labels_found", [])]
    matched_count = 0
    for expected in expected_components:
        # Check if expected name appears in any found label
        if any(expected.lower() in fl for fl in found_labels):
            matched_count += 1
            
    if matched_count >= 15:
        score += 15
        feedback.append(f"Matched {matched_count}/18 components.")
    elif matched_count >= 10:
        score += 10
        feedback.append(f"Matched {matched_count}/18 components.")
    else:
        feedback.append(f"Only matched {matched_count} components. Check spelling.")

    # Criterion 4: Edges (Dependencies)
    # Expect ~22 dependencies + 6 evolution arrows
    edges = analysis.get("total_edges", 0)
    # The base template has 2 axes lines + 3 dividers = 5 edges.
    # New edges should be at least 15.
    new_edges = edges - 5
    if new_edges >= 15:
        score += 15
        feedback.append(f"Edge count good ({new_edges} added).")
    elif new_edges >= 8:
        score += 7
        feedback.append(f"Edge count low ({new_edges} added).")
    else:
        feedback.append("Missing dependency links.")

    # Criterion 5: Evolution Arrows (Dashed)
    dashed = analysis.get("dashed_arrows", 0)
    # Base template has 3 dashed dividers.
    # Expect 6 new dashed arrows. Total ~9.
    if dashed >= 6: 
        score += 10
        feedback.append("Evolution arrows detected.")
    else:
        feedback.append("Missing or incorrect style for evolution arrows (must be dashed).")

    # Criterion 6: Color Coding
    # Expect at least 3 distinct colors (excluding white/none)
    colors = analysis.get("colors_found", [])
    # Filter out common defaults like #FFFFFF if needed, though script excludes 'none'
    if len(colors) >= 3:
        score += 10
        feedback.append(f"Color coding used ({len(colors)} colors).")
    else:
        feedback.append("Insufficient color coding.")

    # Criterion 7: Legend & Annotations
    # Hard to detect strictly, we check for generic extra text or shapes
    # If matched_count is high and shapes > 35, likely present.
    if total_shapes >= 40:
        score += 10
        feedback.append("Annotations/Legend likely present (high shape count).")
    elif total_shapes >= 35:
        score += 5

    # Criterion 8: PDF Export
    if pdf_exists and data.get("pdf_size", 0) > 1000:
        score += 10
        feedback.append("PDF export successful.")
    else:
        feedback.append("PDF export missing or empty.")
        
    # Bonus: All components
    if matched_count == 18:
        score += 5
        feedback.append("Bonus: All components found!")

    # Final Check
    passed = score >= 55 and matched_count >= 10 and new_edges >= 5
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }