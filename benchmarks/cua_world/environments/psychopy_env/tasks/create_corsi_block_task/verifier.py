#!/usr/bin/env python3
"""
Verifier for create_corsi_block_task.

Verification Strategy:
1. CSV Analysis (25 pts): Check for required columns, row count (16), and valid sequence data.
2. Code Analysis (55 pts): Static analysis (AST) of the Python script to verify:
   - Imports (visual, event, etc.)
   - Window creation
   - Block definition (list of coords)
   - Mouse handling logic
   - Sequence iteration
3. VLM Verification (20 pts): Visual confirmation of coding workflow.
4. Anti-gaming: File timestamps must be after task start.

Pass Threshold: 65 points (requires valid CSV + substantial code implementation)
"""

import json
import os
import csv
import ast
import re
import tempfile
import logging
from typing import Dict, Any

# Gym-Anything VLM utils
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_corsi_block_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # File paths in container
    script_path = "/home/ga/PsychoPyExperiments/corsi_task.py"
    csv_path = "/home/ga/PsychoPyExperiments/conditions/corsi_sequences.csv"
    result_json_path = "/tmp/task_result.json"

    score = 0
    feedback_parts = []
    
    # Temporary local files
    local_script = tempfile.NamedTemporaryFile(delete=False, suffix='.py').name
    local_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    local_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # Copy files
        copy_from_env(result_json_path, local_result)
        with open(local_result, 'r') as f:
            result_meta = json.load(f)

        # Anti-gaming: Check timestamps
        task_start = result_meta.get("task_start_time", 0)
        script_mtime = result_meta.get("script_mtime", 0)
        csv_mtime = result_meta.get("csv_mtime", 0)

        if script_mtime <= task_start and csv_mtime <= task_start:
             return {"passed": False, "score": 0, "feedback": "Files were not created/modified during the task."}

        # 1. CSV Verification (25 points)
        csv_valid = False
        try:
            copy_from_env(csv_path, local_csv)
            with open(local_csv, 'r') as f:
                reader = csv.DictReader(f)
                headers = [h.strip().lower() for h in (reader.fieldnames or [])]
                rows = list(reader)

            # Check columns (5 pts)
            req_cols = ["span_level", "trial_num", "sequence"]
            if all(c in headers for c in req_cols):
                score += 5
                feedback_parts.append("CSV columns correct")
            else:
                feedback_parts.append(f"CSV missing columns. Found: {headers}")

            # Check rows (10 pts)
            if len(rows) == 16:
                score += 10
                feedback_parts.append("CSV has 16 rows")
            else:
                feedback_parts.append(f"CSV has {len(rows)} rows (expected 16)")

            # Check data validity (10 pts)
            valid_data_count = 0
            for row in rows:
                try:
                    span = int(row.get('span_level', 0))
                    seq = row.get('sequence', '').strip().split('-')
                    # Sequence length should match span, indices 1-9
                    if len(seq) == span and all(1 <= int(x) <= 9 for x in seq):
                        valid_data_count += 1
                except ValueError:
                    continue
            
            if valid_data_count == 16:
                score += 10
                csv_valid = True
                feedback_parts.append("CSV data valid")
            elif valid_data_count > 8:
                score += 5
                feedback_parts.append("CSV data partially valid")

        except Exception as e:
            feedback_parts.append(f"CSV verification failed: {str(e)}")

        # 2. Code Verification (55 points)
        try:
            copy_from_env(script_path, local_script)
            with open(local_script, 'r') as f:
                code_content = f.read()

            # Syntax Check (5 pts)
            try:
                tree = ast.parse(code_content)
                score += 5
                feedback_parts.append("Python syntax valid")
            except SyntaxError:
                feedback_parts.append("Python syntax invalid")
                tree = None

            if tree:
                # Imports (10 pts)
                imports = set()
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for n in node.names:
                            imports.add(n.name)
                    elif isinstance(node, ast.ImportFrom):
                        if node.module:
                            imports.add(node.module)
                
                has_psychopy = any("psychopy" in i for i in imports)
                has_visual = any("visual" in i for i in imports) or "psychopy.visual" in imports
                has_event = any("event" in i for i in imports) or "psychopy.event" in imports
                
                if has_psychopy and (has_visual or has_event):
                    score += 10
                    feedback_parts.append("PsychoPy imports found")
                
                # Window Creation (10 pts)
                if re.search(r'visual\.Window', code_content):
                    score += 10
                    feedback_parts.append("Window creation found")

                # Block Definitions (10 pts)
                # Look for list of at least 9 coordinates
                # Matches list of tuples like [(x,y), ...] or [[x,y], ...]
                coords = re.findall(r'[\[\(]\s*-?\d*\.?\d+\s*,\s*-?\d*\.?\d+\s*[\]\)]', code_content)
                if len(coords) >= 9:
                    score += 10
                    feedback_parts.append("Block coordinates defined")
                elif len(coords) >= 5:
                    score += 5
                
                # Mouse Interaction (10 pts)
                if re.search(r'event\.Mouse|getMouse', code_content):
                    score += 10
                    feedback_parts.append("Mouse handler found")
                
                # Logic/Loop (10 pts)
                # Look for loops over sequences or trials
                if re.search(r'for\s+.*in\s+.*:', code_content) and re.search(r'append', code_content):
                    score += 10
                    feedback_parts.append("Loop/Logic structure found")

        except Exception as e:
            feedback_parts.append(f"Code verification failed: {str(e)}")

        # 3. VLM Verification (20 pts)
        # Use VLM to verify the agent was actually coding in PsychoPy
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots of a user working in PsychoPy.
        1. Is the Coder view (code editor) visible in any frame?
        2. Is there Python code visible that resembles a psychology experiment?
        3. Do you see code related to 'visual.Window', 'Rect', or 'Mouse'?
        
        Respond with JSON: {"coder_visible": bool, "python_code_visible": bool, "relevant_keywords": bool}
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_score = 0
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("coder_visible"): vlm_score += 5
            if parsed.get("python_code_visible"): vlm_score += 10
            if parsed.get("relevant_keywords"): vlm_score += 5
            feedback_parts.append(f"VLM verification score: {vlm_score}/20")
        
        score += vlm_score

    except Exception as e:
        feedback_parts.append(f"Verification process error: {str(e)}")
    finally:
        # Cleanup
        for f in [local_script, local_csv, local_result]:
            if os.path.exists(f):
                os.unlink(f)

    passed = score >= 65 and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }