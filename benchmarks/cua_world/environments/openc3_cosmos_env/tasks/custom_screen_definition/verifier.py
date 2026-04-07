#!/usr/bin/env python3
"""
Verifier for custom_screen_definition task.

Checks:
- Screen file exists in COSMOS plugins and was created this session.
- Screen definition contains required telemetry item references.
- JSON report exists on Desktop and contains required keys.
"""

import base64
import json
import os
import re
import tempfile

def verify_custom_screen_definition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/custom_screen_definition_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/screen_report.json')

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
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback)}
    finally:
        if tmp_name and os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 2. Check screen file
    screen_exists = export_meta.get('screen_file_exists', False)
    screen_is_new = export_meta.get('screen_file_is_new', False)
    screen_b64 = export_meta.get('screen_file_content_b64', '')

    if screen_exists:
        score += 20
        feedback.append('Screen file exists in COSMOS plugins (+20)')
        
        if screen_is_new:
            score += 10
            feedback.append('Screen file created during this session (+10)')
            
            # 3. Parse screen content
            try:
                screen_text = base64.b64decode(screen_b64).decode('utf-8', errors='replace')
                screen_upper = screen_text.upper()
                
                # Try to extract items associated with HEALTH_STATUS
                items = re.findall(r'HEALTH_STATUS\s+([A-Z0-9_]+)', screen_upper)
                unique_items = set(items)
                
                # Fallback: if they just wrote the item names without HEALTH_STATUS
                for req in ['TEMP1', 'TEMP2', 'TEMP3', 'TEMP4', 'COLLECTS']:
                    if req in screen_upper:
                        unique_items.add(req)
                        
                # 6th item fallback (if they just wrote it without HEALTH_STATUS)
                required_set = {'TEMP1', 'TEMP2', 'TEMP3', 'TEMP4', 'COLLECTS'}
                if len(unique_items - required_set) == 0:
                    known_extra = [
                        'GROUND1STATUS', 'GROUND2STATUS', 'ASCIICMD', 'DURATION',
                        'CCSDSSEQCNT', 'CCSDSLENGTH', 'CCSDSVERSION', 'CCSDSFLAGS',
                        'CCSDSSTREAMID', 'CCSDSAPID', 'OS_CPU', 'OS_MEM', 'OS_DISK',
                        'OS_NET_RCV', 'OS_NET_SNT', 'OS_SYS_TIME'
                    ]
                    for extra in known_extra:
                        if extra in screen_upper:
                            unique_items.add(extra)
                
                # Score required items
                if 'TEMP1' in unique_items:
                    score += 8
                    feedback.append('Screen contains TEMP1 (+8)')
                else:
                    feedback.append('Screen missing TEMP1')
                    
                if 'TEMP2' in unique_items:
                    score += 8
                    feedback.append('Screen contains TEMP2 (+8)')
                else:
                    feedback.append('Screen missing TEMP2')
                    
                if 'TEMP3' in unique_items:
                    score += 8
                    feedback.append('Screen contains TEMP3 (+8)')
                else:
                    feedback.append('Screen missing TEMP3')
                    
                if 'TEMP4' in unique_items:
                    score += 8
                    feedback.append('Screen contains TEMP4 (+8)')
                else:
                    feedback.append('Screen missing TEMP4')
                    
                if 'COLLECTS' in unique_items:
                    score += 8
                    feedback.append('Screen contains COLLECTS (+8)')
                else:
                    feedback.append('Screen missing COLLECTS')
                    
                # 6th item
                additional_items = unique_items - required_set
                if len(additional_items) >= 1:
                    score += 5
                    feedback.append(f'Screen contains 6th item ({list(additional_items)[0]}) (+5)')
                else:
                    feedback.append('Screen missing a 6th telemetry item')
                    
            except Exception as e:
                feedback.append(f'Error parsing screen content: {e}')
        else:
            feedback.append('Screen file predates task start (no content points)')
    else:
        feedback.append('Screen file not found in COSMOS plugins')

    # 4. Check JSON report
    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    
    if file_exists:
        score += 5
        feedback.append('JSON report exists on Desktop (+5)')
        
        if file_is_new:
            score += 5
            feedback.append('JSON report created during this session (+5)')
        else:
            feedback.append('JSON report predates task start')
            
        # Parse JSON
        tmp_name = None
        try:
            with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
                tmp_name = tmp.name
            copy_from_env(output_file, tmp_name)
            with open(tmp_name, 'r') as f:
                report = json.load(f)
                
            required_keys = {'screen_name', 'target', 'items_displayed', 'title'}
            if required_keys.issubset(set(report.keys())):
                score += 5
                feedback.append('JSON report has required keys (+5)')
            else:
                feedback.append(f"JSON report missing keys: {required_keys - set(report.keys())}")
        except Exception as e:
            feedback.append(f'JSON report parse error: {e}')
        finally:
            if tmp_name and os.path.exists(tmp_name):
                os.unlink(tmp_name)
    else:
        feedback.append('JSON report not found on Desktop')

    passed = score >= 60 and screen_exists and screen_is_new
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }