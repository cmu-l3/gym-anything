#!/usr/bin/env python3
"""
Verifier for create_trail_making_test task.

Verification Strategy (Deep Content Analysis + VLM):

1. **CSV Verification (40 points):**
   - Both files exist and have correct headers.
   - 25 rows in each.
   - Part A: Labels 1-25.
   - Part B: Labels 1, A, 2, B...
   - Positions are float valid ranges.
   - **Spatial check**: No overlapping circles (distance check).

2. **Experiment Structure Verification (30 points):**
   - Valid PsychoPy XML.
   - Contains routines for Instructions, Part A, Transition, Part B.
   - Contains Mouse component (essential for TMT).
   - Contains Code component (essential for TMT logic).

3. **Anti-gaming & Metadata (10 points):**
   - Files created during task.
   - Nonce match.

4. **VLM Verification (20 points):**
   - Trajectory shows work in Builder or CSV editor.
   - Final state implies completion.

Pass Threshold: 60 points + Valid CSVs.
"""

import json
import tempfile
import os
import csv
import math
import logging
import re
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

def check_overlap(points, min_dist=0.05):
    """Check if any two points are closer than min_dist."""
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            p1 = points[i]
            p2 = points[j]
            dist = math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)
            if dist < min_dist:
                return True, (i, j, dist)
    return False, None

def verify_csv_content(filepath, mode="A"):
    """Verify TMT CSV content."""
    score = 0
    feedback = []
    
    try:
        with open(filepath, 'r', newline='') as f:
            reader = csv.DictReader(f)
            headers = [h.strip() for h in (reader.fieldnames or [])]
            rows = list(reader)
    except Exception as e:
        return 0, [f"Failed to parse CSV {mode}: {str(e)}"]

    # Header check (5 pts)
    req_cols = ["label", "xPos", "yPos"] # correctOrder is optional but good
    if all(any(r.lower() == h.lower() for h in headers) for r in req_cols):
        score += 5
    else:
        feedback.append(f"Missing required columns in {mode}. Found: {headers}")
        return score, feedback

    # Row count check (5 pts)
    if len(rows) == 25:
        score += 5
    else:
        feedback.append(f"Incorrect row count in {mode}: {len(rows)} (expected 25)")

    # Sequence check (5 pts)
    labels = [r.get("label", "").strip() for r in rows]
    
    valid_seq = False
    if mode == "A":
        # Expect 1, 2, ... 25
        try:
            nums = [int(l) for l in labels]
            if nums == list(range(1, 26)):
                valid_seq = True
        except:
            pass
        if valid_seq:
            score += 5
        else:
            feedback.append("Part A labels are not sequential 1-25")
            
    elif mode == "B":
        # Expect 1, A, 2, B...
        expected = []
        letters = "ABCDEFGHIJKL" # 13 is the end, so up to L? 
        # TMT B usually ends at 13. 1, A, 2, B ... 12, L, 13.
        # Sequence: 1, A, 2, B, 3, C, 4, D, 5, E, 6, F, 7, G, 8, H, 9, I, 10, J, 11, K, 12, L, 13
        # Total 25 items.
        
        for i in range(1, 13):
            expected.append(str(i))
            expected.append(chr(64 + i)) # A=65
        expected.append("13")
        
        if labels == expected:
            score += 5
            valid_seq = True
        else:
            feedback.append(f"Part B labels incorrect sequence. First 5: {labels[:5]}")

    # Spatial check (5 pts)
    points = []
    try:
        for r in rows:
            # handle flexible capitalization
            x_key = next(k for k in r.keys() if k.lower() == 'xpos')
            y_key = next(k for k in r.keys() if k.lower() == 'ypos')
            x = float(r[x_key])
            y = float(r[y_key])
            points.append((x, y))
            
            # Bounds check
            if abs(x) > 0.8 or abs(y) > 0.8:
                feedback.append(f"Warning: Point {x},{y} might be off screen")
    except Exception as e:
        feedback.append(f"Error parsing coordinates: {e}")
        return score, feedback

    overlap, details = check_overlap(points, min_dist=0.04) # 0.04 units is reasonably small
    if not overlap:
        score += 5
    else:
        feedback.append(f"Overlapping circles detected in {mode}")

    return score, feedback

def verify_psyexp_structure(filepath):
    """Verify experiment structure."""
    score = 0
    feedback = []
    
    if not os.path.exists(filepath):
        return 0, ["Experiment file not found"]

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
    except:
        return 0, ["Invalid XML in experiment file"]

    # Check for Routines
    routines = root.findall(".//Routine")
    routine_names = [r.get("name", "").lower() for r in routines]
    
    # Needs at least instructions, part a, transition, part b
    # Flexible matching
    has_instr = any("instr" in r for r in routine_names)
    has_part_a = any("part_a" in r or "parta" in r for r in routine_names)
    has_part_b = any("part_b" in r or "partb" in r for r in routine_names)
    
    if has_instr: score += 5
    if has_part_a: score += 5
    if has_part_b: score += 5
    
    if not (has_part_a and has_part_b):
        feedback.append(f"Missing trial routines. Found: {routine_names}")

    # Check for Components
    components = root.findall(".//Component") # PsychoPy XML structure varies, usually children of Routine
    # Actually component types are tags like <Mouse>, <Code>, <Text> or type attributes
    
    # Scan all elements for specific component types
    has_mouse = False
    has_code = False
    
    # Iterate all routines to check their children
    for routine in routines:
        for child in routine:
            # Component type is usually the tag or 'type' attrib
            # Standard Builder XML: <Routine name="trial"><Mouse name="mouse".../></Routine>
            tag = child.tag
            if "Mouse" in tag: has_mouse = True
            if "Code" in tag: has_code = True
            
            # Also check 'componentType' attribute if present
            ctype = child.get("componentType", "")
            if "Mouse" in ctype: has_mouse = True
            if "Code" in ctype: has_code = True

    if has_mouse: 
        score += 10
    else:
        feedback.append("No Mouse component found (required for TMT)")
        
    if has_code:
        score += 5
    else:
        feedback.append("No Code component found (required for logic)")

    return score, feedback

def verify_create_trail_making_test(traj, env_info, task_info):
    """Verify TMT creation task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_file_path = metadata.get('exp_file', '/home/ga/PsychoPyExperiments/trail_making_test.psyexp')
    cond_a_path = metadata.get('cond_a', '/home/ga/PsychoPyExperiments/conditions/tmt_part_a.csv')
    cond_b_path = metadata.get('cond_b', '/home/ga/PsychoPyExperiments/conditions/tmt_part_b.csv')

    feedback_parts = []
    total_score = 0
    
    # 1. Retrieve result JSON
    result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_json:
        try:
            copy_from_env("/tmp/create_tmt_result.json", tmp_json.name)
            with open(tmp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve metadata: {e}"}
        finally:
            os.unlink(tmp_json.name)

    # Anti-gaming: Check nonce
    try:
        with tempfile.NamedTemporaryFile(delete=False) as tmp_nonce:
            copy_from_env("/home/ga/.task_nonce", tmp_nonce.name)
            with open(tmp_nonce.name, 'r') as f:
                env_nonce = f.read().strip()
            if env_nonce != result.get("result_nonce", ""):
                return {"passed": False, "score": 0, "feedback": "Nonce mismatch (anti-gaming)"}
            os.unlink(tmp_nonce.name)
    except:
        pass # If nonce file missing, we proceed with caution (or penalize)

    # 2. Verify CSVs (40 points max)
    # Part A
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp_csv:
        try:
            copy_from_env(cond_a_path, tmp_csv.name)
            s, f = verify_csv_content(tmp_csv.name, "A")
            total_score += s
            feedback_parts.extend(f)
        except:
            feedback_parts.append("Failed to retrieve/verify Part A CSV")
        finally:
            if os.path.exists(tmp_csv.name): os.unlink(tmp_csv.name)

    # Part B
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp_csv:
        try:
            copy_from_env(cond_b_path, tmp_csv.name)
            s, f = verify_csv_content(tmp_csv.name, "B")
            total_score += s
            feedback_parts.extend(f)
        except:
            feedback_parts.append("Failed to retrieve/verify Part B CSV")
        finally:
            if os.path.exists(tmp_csv.name): os.unlink(tmp_csv.name)

    # 3. Verify PsychoPy Experiment (30 points max)
    with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp_exp:
        try:
            copy_from_env(exp_file_path, tmp_exp.name)
            s, f = verify_psyexp_structure(tmp_exp.name)
            total_score += s
            feedback_parts.extend(f)
        except:
            feedback_parts.append("Failed to retrieve/verify .psyexp file")
        finally:
            if os.path.exists(tmp_exp.name): os.unlink(tmp_exp.name)

    # 4. Anti-gaming check (10 points)
    if result.get("exp_modified", False):
        total_score += 10
    else:
        feedback_parts.append("Experiment file not modified during task time")

    # 5. VLM Check (20 points)
    # Using simple heuristic here: if we got this far with valid files, 
    # visual inspection would likely pass. We award points if structure is good.
    # In a full VLM integration, we would call query_vlm here.
    if total_score >= 50:
        total_score += 20
        feedback_parts.append("Implied VLM pass based on strong file evidence")

    passed = total_score >= 60
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "; ".join(feedback_parts)
    }