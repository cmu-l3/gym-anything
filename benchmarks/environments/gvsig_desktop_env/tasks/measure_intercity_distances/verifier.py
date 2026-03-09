#!/usr/bin/env python3
import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_distances(traj, env_info, task_info):
    """
    Verify the agent correctly measured and reported geodesic distances.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    tolerance_pct = metadata.get('tolerance_percent', 15)

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Timestamp (20 pts)
    output_exists = result.get("output_exists", False)
    created_fresh = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file distances.txt not found."}
    
    if created_fresh:
        score += 20
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File exists but timestamp is old/invalid.")
        score += 5 # Minimal points for existence

    # 3. Parse Content
    content_b64 = result.get("file_content_b64", "")
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        content = ""

    lines = content.splitlines()
    if not lines:
        feedback_parts.append("File is empty.")
    else:
        feedback_parts.append(f"File contains {len(lines)} lines.")

    # 4. Analyze Measurements (80 pts total)
    # Define targets and regex
    # Format expected: "CityA-CityB: 1234 km"
    # We'll be flexible with regex
    
    targets = [
        {"key": "ny_london", "names": ["New York", "London"], "gt": ground_truth.get("ny_london", 5570)},
        {"key": "tokyo_sydney", "names": ["Tokyo", "Sydney"], "gt": ground_truth.get("tokyo_sydney", 7800)},
        {"key": "ba_capetown", "names": ["Buenos Aires", "Cape Town"], "gt": ground_truth.get("ba_capetown", 6890)}
    ]
    
    valid_measurements = 0
    
    for target in targets:
        gt_dist = target['gt']
        found_val = None
        
        # Search all lines for this pair
        for line in lines:
            # Check if both city names appear in the line (case insensitive)
            if all(name.lower() in line.lower() for name in target['names']):
                # Extract number: look for digits, optional commas/decimals
                # e.g., "5,500.5" -> 5500.5
                # Regex logic: find number followed optionally by "km"
                matches = re.findall(r'([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)', line)
                
                # Filter out numbers that are obviously not the distance (e.g. if they wrote "Pair 1")
                # We assume the distance is likely the largest number or explicitly near "km"
                # For simplicity, let's take the number closest to the ground truth if multiple found,
                # or just the last number in the line which is usually the value.
                
                best_match = None
                min_diff = float('inf')
                
                for m in matches:
                    try:
                        val = float(m.replace(',', ''))
                        diff = abs(val - gt_dist)
                        if diff < min_diff:
                            min_diff = diff
                            best_match = val
                    except ValueError:
                        continue
                
                if best_match is not None:
                    found_val = best_match
                    break
        
        # Verify accuracy
        if found_val is not None:
            lower = gt_dist * (1 - tolerance_pct / 100.0)
            upper = gt_dist * (1 + tolerance_pct / 100.0)
            
            if lower <= found_val <= upper:
                score += 26 # ~26.6 pts per valid measurement to reach 80
                valid_measurements += 1
                feedback_parts.append(f"✓ {target['names'][0]}-{target['names'][1]}: {found_val:.1f} km (Ref: {gt_dist})")
            else:
                score += 5 # Partial credit for finding the pair but wrong value
                feedback_parts.append(f"✗ {target['names'][0]}-{target['names'][1]}: {found_val:.1f} km (Outside tolerance {lower:.0f}-{upper:.0f})")
        else:
            feedback_parts.append(f"✗ {target['names'][0]}-{target['names'][1]}: Not found/parsed")

    # Final Score
    # Max possible: 20 + 26*3 = 98 -> adjust to 100
    if valid_measurements == 3:
        score = 100
    elif valid_measurements == 2:
        score = max(score, 70) 
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }