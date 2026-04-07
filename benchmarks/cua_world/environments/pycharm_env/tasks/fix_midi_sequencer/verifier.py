#!/usr/bin/env python3
"""
Verifier for fix_midi_sequencer task.
"""

import json
import os
import tempfile
import struct
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_midi_sequencer(traj, env_info, task_info):
    """
    Verify that the MIDI sequencer bugs were fixed.
    
    Criteria:
    1. Pytest suite passed (Logic check).
    2. Code analysis shows fixes (Heuristic check).
    3. Generated MIDI file is valid (Binary check).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fix_midi_sequencer_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Check Pytest Results (Primary Logic Check)
    pytest_code = result.get('pytest_exit_code', -1)
    if pytest_code == 0:
        score += 40
        feedback.append("Tests passed (40 pts)")
    else:
        feedback.append(f"Tests failed with exit code {pytest_code}")
        # Parse output for partial credit
        output = result.get('pytest_output', '')
        if 'test_vlq_large_number PASSED' in output:
            score += 10
            feedback.append("VLQ logic partially fixed (+10 pts)")
        if 'test_delta_time_logic PASSED' in output:
            score += 10
            feedback.append("Delta time logic fixed (+10 pts)")

    # 3. Check Code Analysis (Heuristics)
    code_analysis = result.get('code_analysis', {})
    if code_analysis.get('encoder_fixed'):
        score += 10
        feedback.append("Encoder code looks correct (+10 pts)")
    if code_analysis.get('delta_fixed'):
        score += 10
        feedback.append("Sequencer delta logic looks correct (+10 pts)")
    if code_analysis.get('eot_fixed'):
        score += 10
        feedback.append("End of Track logic present (+10 pts)")

    # 4. Binary Verification of Output File
    # We inspect the agent's generated MIDI file
    temp_midi = tempfile.NamedTemporaryFile(delete=False, suffix='.mid')
    try:
        copy_from_env("/tmp/agent_output.mid", temp_midi.name)
        if os.path.getsize(temp_midi.name) > 0:
            with open(temp_midi.name, 'rb') as f:
                data = f.read()
                
            # Check Header
            if data.startswith(b'MThd'):
                score += 5
                feedback.append("Valid MIDI Header (+5 pts)")
            
            # Check End of Track
            if data.endswith(b'\xFF\x2F\x00'):
                score += 15
                feedback.append("Valid End of Track marker (+15 pts)")
            else:
                feedback.append("Missing End of Track marker")
                
            # Basic sanity check on track length
            # Find MTrk
            idx = data.find(b'MTrk')
            if idx != -1:
                # Read declared length
                declared_len = struct.unpack('>I', data[idx+4:idx+8])[0]
                actual_len = len(data) - (idx + 8)
                if declared_len == actual_len:
                     # If they match exactly, the file structure is solid
                     pass
        else:
            feedback.append("Generated MIDI file is empty")
            
    except Exception as e:
        feedback.append("Could not retrieve generated MIDI file")
    finally:
        if os.path.exists(temp_midi.name):
            os.unlink(temp_midi.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback)
    }