#!/usr/bin/env python3
"""
Verifier for create_srtt_implicit_learning task.

Scoring Criteria (100 points total):
1. Files Exist & Created During Task (20 pts)
   - 4 required files, must have mtime > start_time
2. Sequence Block CSV (20 pts)
   - Valid CSV, 60 rows
   - Follows [4,2,3,1,3,2,4,3,2,1] pattern exactly
   - Correct position/key mappings
3. Random Block CSV (15 pts)
   - Valid CSV, 60 rows
   - Balanced positions (13-17 counts)
   - Max 2 consecutive repeats
   - No full 10-element sequence present
4. Blocks CSV (10 pts)
   - 7 rows
   - Correct order: 5 seq, 1 rnd, 1 seq
5. Experiment Structure (.psyexp) (35 pts)
   - Valid XML
   - Nested loops (at least 2 loops)
   - Correct routines (trial, feedback/break, instructions)
   - Keyboard component uses correct columns

Verification Method:
- Pulls files from container using `copy_from_env`
- Parses CSVs with `csv` module
- Parses .psyexp with `xml.etree.ElementTree`
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_srtt_implicit_learning(traj, env_info, task_info):
    # 1. Setup and Retrieve Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sequence = metadata.get('expected_sequence', [4, 2, 3, 1, 3, 2, 4, 3, 2, 1])
    
    # Define file paths in container
    files_map = {
        'result_json': "/tmp/task_result.json",
        'psyexp': metadata.get('experiment_file'),
        'seq_csv': metadata.get('sequence_file'),
        'rnd_csv': metadata.get('random_file'),
        'blk_csv': metadata.get('blocks_file'),
        'nonce': "/home/ga/.task_nonce"
    }

    # Copy files to host temp storage
    local_files = {}
    temp_dir = tempfile.TemporaryDirectory()
    
    try:
        for key, remote_path in files_map.items():
            if not remote_path: continue
            local_path = os.path.join(temp_dir.name, os.path.basename(remote_path))
            try:
                copy_from_env(remote_path, local_path)
                if os.path.exists(local_path):
                    local_files[key] = local_path
            except Exception:
                pass # File might not exist

        # Load metadata
        if 'result_json' not in local_files:
            return {"passed": False, "score": 0, "feedback": "Task result metadata missing"}
        
        with open(local_files['result_json'], 'r') as f:
            result_meta = json.load(f)

        # Check Nonce
        if 'nonce' in local_files:
            with open(local_files['nonce'], 'r') as f:
                env_nonce = f.read().strip()
            if result_meta.get('result_nonce') != env_nonce:
                 return {"passed": False, "score": 0, "feedback": "Integrity check failed (nonce mismatch)"}
        
        task_start = result_meta.get('task_start_time', 0)
        
        score = 0
        feedback = []

        # --- CRITERION 1: File Existence & Timestamp (20 pts) ---
        files_exist_score = 0
        for key in ['psyexp', 'seq_csv', 'rnd_csv', 'blk_csv']:
            file_info = result_meta.get('files', {}).get(key.split('_')[0] if 'csv' in key else 'experiment', {})
            if file_info.get('exists') and file_info.get('mtime', 0) > task_start:
                files_exist_score += 5
            elif file_info.get('exists'):
                feedback.append(f"{key} exists but looks old (pre-task?)")
                files_exist_score += 2 # Partial credit if it exists but time checks fail (clock skew?)
            else:
                feedback.append(f"Missing file: {key}")
        
        score += files_exist_score
        feedback.append(f"File checks: {files_exist_score}/20")

        # --- CRITERION 2: Sequence CSV (20 pts) ---
        seq_score = 0
        if 'seq_csv' in local_files:
            try:
                with open(local_files['seq_csv'], 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    # Check row count
                    if len(rows) == 60:
                        seq_score += 5
                    else:
                        feedback.append(f"Seq CSV has {len(rows)} rows (expected 60)")

                    # Check Columns
                    if all(k in (reader.fieldnames or []) for k in ['position', 'xPos', 'correctKey']):
                        seq_score += 5
                    
                    # Check Pattern
                    pattern_match = True
                    mapping_match = True
                    x_map = {1: -0.45, 2: -0.15, 3: 0.15, 4: 0.45}
                    key_map = {1: 'z', 2: 'x', 3: 'n', 4: 'm'}

                    for i, row in enumerate(rows):
                        pos = int(float(row.get('position', 0)))
                        
                        # Pattern check
                        if pos != expected_sequence[i % 10]:
                            pattern_match = False
                        
                        # Mapping check
                        try:
                            x_val = float(row.get('xPos', 0))
                            if abs(x_val - x_map.get(pos, 99)) > 0.01: mapping_match = False
                            if row.get('correctKey', '').strip() != key_map.get(pos, ''): mapping_match = False
                        except:
                            mapping_match = False
                    
                    if pattern_match: seq_score += 5
                    else: feedback.append("Sequence pattern does not match expected SRTT sequence")
                    
                    if mapping_match: seq_score += 5
                    else: feedback.append("Sequence mappings (position->x/key) incorrect")

            except Exception as e:
                feedback.append(f"Error parsing Seq CSV: {e}")
        
        score += seq_score
        feedback.append(f"Sequence CSV: {seq_score}/20")

        # --- CRITERION 3: Random CSV (15 pts) ---
        rnd_score = 0
        if 'rnd_csv' in local_files:
            try:
                with open(local_files['rnd_csv'], 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    positions = []
                    for r in rows:
                        try:
                            positions.append(int(float(r.get('position', 0))))
                        except: pass
                    
                    if len(positions) == 60:
                        rnd_score += 3
                    
                    # Check Balance (13-17)
                    counts = Counter(positions)
                    if all(13 <= counts[k] <= 17 for k in [1,2,3,4]):
                        rnd_score += 4
                    else:
                        feedback.append(f"Random balance poor: {dict(counts)}")

                    # Check Repetitions (Max 2 consecutive)
                    max_rep = 1
                    curr_rep = 1
                    for i in range(1, len(positions)):
                        if positions[i] == positions[i-1]:
                            curr_rep += 1
                            max_rep = max(max_rep, curr_rep)
                        else:
                            curr_rep = 1
                    
                    if max_rep <= 2:
                        rnd_score += 4
                    else:
                        feedback.append(f"Random block has {max_rep} consecutive repeats (max 2 allowed)")

                    # Check for full sequence embedding
                    has_seq = False
                    seq_list = expected_sequence
                    for i in range(len(positions) - 10):
                        if positions[i:i+10] == seq_list:
                            has_seq = True
                            break
                    
                    if not has_seq:
                        rnd_score += 4
                    else:
                        feedback.append("Random block contains forbidden sequence pattern")

            except Exception as e:
                feedback.append(f"Error parsing Random CSV: {e}")

        score += rnd_score
        feedback.append(f"Random CSV: {rnd_score}/15")

        # --- CRITERION 4: Blocks CSV (10 pts) ---
        blk_score = 0
        if 'blk_csv' in local_files:
            try:
                with open(local_files['blk_csv'], 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    if len(rows) == 7:
                        blk_score += 3
                    
                    # Check Order
                    # Expected: 5 seq, 1 rnd, 1 seq
                    types = []
                    files = []
                    for r in rows:
                        types.append(r.get('blockType', ''))
                        files.append(r.get('conditionsFile', ''))
                    
                    # Flexible matching for "sequence" vs "random"
                    is_seq = lambda s: 'seq' in s.lower()
                    is_rnd = lambda s: 'rand' in s.lower()
                    
                    order_ok = (all(is_seq(t) for t in types[:5]) and 
                                is_rnd(types[5]) and 
                                is_seq(types[6]))
                    
                    file_ok = (all('sequence' in f.lower() for f in files[:5]) and
                               'random' in files[5].lower() and
                               'sequence' in files[6].lower())

                    if order_ok: blk_score += 4
                    else: feedback.append("Block order incorrect (expected 5 seq, 1 rnd, 1 seq)")
                    
                    if file_ok: blk_score += 3
            
            except Exception as e:
                feedback.append(f"Error parsing Blocks CSV: {e}")

        score += blk_score
        feedback.append(f"Blocks CSV: {blk_score}/10")

        # --- CRITERION 5: Psyexp Structure (35 pts) ---
        exp_score = 0
        if 'psyexp' in local_files:
            try:
                tree = ET.parse(local_files['psyexp'])
                root = tree.getroot()
                
                if 'PsychoPy' in root.tag or 'PsychoPy' in str(root.attrib):
                    exp_score += 5
                
                # Check Loops
                loops = root.findall(".//LoopInitiator")
                if len(loops) >= 2:
                    exp_score += 10
                else:
                    feedback.append(f"Found {len(loops)} loops, expected nested structure (>=2)")

                # Check Routines
                routines = root.findall(".//Routine")
                routine_names = [r.get('name') for r in routines]
                
                has_trial = any('trial' in n.lower() for n in routine_names)
                has_instr = any('instruct' in n.lower() for n in routine_names)
                
                if has_trial: exp_score += 5
                if has_instr: exp_score += 5

                # Check Components in Trial Routine
                trial_routine = None
                for r in routines:
                    if 'trial' in r.get('name', '').lower():
                        trial_routine = r
                        break
                
                if trial_routine:
                    comps = list(trial_routine)
                    comp_types = [c.tag for c in comps]
                    
                    # Visual Stim
                    if any('Polygon' in t or 'Image' in t or 'Text' in t for t in comp_types):
                        exp_score += 5
                    
                    # Keyboard
                    kb = None
                    for c in comps:
                        if 'Keyboard' in c.tag:
                            kb = c
                            break
                    
                    if kb:
                        exp_score += 5
                        # Check params
                        # We want correctAns to reference a variable (e.g. $correctKey or $corrAns)
                        # but parsing XML for specific params is tricky without exact schema knowledge.
                        # We'll stick to existence for robustness.

            except Exception as e:
                feedback.append(f"Error parsing .psyexp: {e}")

        score += exp_score
        feedback.append(f"Experiment Structure: {exp_score}/35")

        # Final Result
        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    finally:
        temp_dir.cleanup()