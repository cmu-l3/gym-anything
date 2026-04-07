#!/usr/bin/env python3
"""
Verifier for cmd_tlm_dictionary_validation task.

Scoring breakdown (100 pts total, pass threshold = 60):
  10pts  Export metadata JSON readable
  10pts  Dictionary JSON file exists on Desktop
  10pts  File created this session (hard gate)
   5pts  target field equals "INST"
  15pts  telemetry_packets has >= 3 entries with non-empty items
  15pts  commands has >= 3 entries with parameters key
  10pts  summary has all 4 numeric fields
  15pts  Cross-validation: >= 2 telemetry packet names match known COSMOS API (INST)
  10pts  Cross-validation: >= 2 command names match known COSMOS API (INST)
 ---
 100pts total

The cross-validation ensures the agent actually queried the COSMOS environment
for real data rather than purely fabricating the response.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cmd_tlm_dictionary_validation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/cmd_tlm_dictionary_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/cmd_tlm_dictionary.json')

    score = 0
    feedback = []

    # 1. Read export metadata
    export_meta = {}
    tmp_name = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
        score += 10
        feedback.append('Export metadata readable (+10)')
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        if tmp_name and os.path.exists(tmp_name):
            os.unlink(tmp_name)

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)

    if not file_exists:
        feedback.append('Dictionary file not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('Dictionary file exists on Desktop (+10)')

    if not file_is_new:
        feedback.append('Dictionary file predates task start (no content credit)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append('File created during this session (+10)')

    # 2. Copy and parse JSON dictionary
    dictionary = None
    tmp_name = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            dictionary = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Dictionary file is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy dictionary file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        if tmp_name and os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 3. Target equals INST
    target = dictionary.get('target', '')
    if str(target).upper() == 'INST':
        score += 5
        feedback.append('Target is INST (+5)')
    else:
        feedback.append(f'Target mismatch: expected "INST", got "{target}"')

    # 4. Telemetry packets
    tlm_packets = dictionary.get('telemetry_packets', {})
    if isinstance(tlm_packets, dict):
        valid_tlm = 0
        agent_tlm_names = []
        for name, data in tlm_packets.items():
            agent_tlm_names.append(str(name).upper())
            if isinstance(data, dict) and isinstance(data.get('items'), list) and len(data['items']) > 0:
                valid_tlm += 1
        
        if valid_tlm >= 3:
            score += 15
            feedback.append(f'telemetry_packets has {valid_tlm} valid entries (+15)')
        else:
            feedback.append(f'telemetry_packets has only {valid_tlm} valid entries (need 3)')
    else:
        agent_tlm_names = []
        feedback.append('telemetry_packets is not a dictionary')

    # 5. Commands
    cmds = dictionary.get('commands', {})
    if isinstance(cmds, dict):
        valid_cmds = 0
        agent_cmd_names = []
        for name, data in cmds.items():
            agent_cmd_names.append(str(name).upper())
            if isinstance(data, dict) and 'parameters' in data and isinstance(data['parameters'], list):
                valid_cmds += 1
        
        if valid_cmds >= 3:
            score += 15
            feedback.append(f'commands has {valid_cmds} valid entries (+15)')
        else:
            feedback.append(f'commands has only {valid_cmds} valid entries (need 3)')
    else:
        agent_cmd_names = []
        feedback.append('commands is not a dictionary')

    # 6. Summary
    summary = dictionary.get('summary', {})
    if isinstance(summary, dict):
        req_keys = {'total_telemetry_packets', 'total_commands', 'total_telemetry_items', 'total_command_parameters'}
        if req_keys.issubset(set(summary.keys())):
            all_numeric = True
            for k in req_keys:
                if not isinstance(summary[k], (int, float)):
                    all_numeric = False
                    break
            if all_numeric:
                score += 10
                feedback.append('summary has all 4 numeric fields (+10)')
            else:
                feedback.append('summary fields must be numeric')
        else:
            missing = req_keys - set(summary.keys())
            feedback.append(f'summary missing keys: {missing}')
    else:
        feedback.append('summary is not a dictionary')

    # 7. Cross-validation against known INST baseline targets
    # This prevents the agent from simply hallucinating data that looks like a valid response
    known_inst_tlm = {'HEALTH_STATUS', 'ADCS', 'PARAMS', 'IMAGE', 'MECH', 'MEMORY', 'SYSTEM', 'LIMITS_VIOLATION'}
    known_inst_cmd = {'CLEAR', 'COLLECT', 'SETPARAMS', 'START', 'STOP', 'ABORT', 'IMAGE_DUMP', 'CALIBRATE'}

    tlm_matches = set(agent_tlm_names).intersection(known_inst_tlm)
    cmd_matches = set(agent_cmd_names).intersection(known_inst_cmd)

    if len(tlm_matches) >= 2:
        score += 15
        feedback.append(f'CV: {len(tlm_matches)} telemetry packets match known INST packets (+15)')
    else:
        feedback.append(f'CV: Only {len(tlm_matches)} telemetry packets match known INST packets (need 2)')

    if len(cmd_matches) >= 2:
        score += 10
        feedback.append(f'CV: {len(cmd_matches)} commands match known INST commands (+10)')
    else:
        feedback.append(f'CV: Only {len(cmd_matches)} commands match known INST commands (need 2)')

    passed = score >= 60

    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback)
    }