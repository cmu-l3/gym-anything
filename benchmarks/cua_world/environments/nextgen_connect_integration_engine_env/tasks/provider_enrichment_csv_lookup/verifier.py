#!/usr/bin/env python3
"""
Verifier for provider_enrichment_csv_lookup task.

Criteria:
1. Channel exists and is deployed (10 pts)
2. Output files exist (20 pts)
3. Data Accuracy: Output HL7 PV1-7 matches CSV data (50 pts)
4. Optimization: Deploy script used for CSV reading (20 pts)
"""

import json
import base64
import tempfile
import os
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provider_enrichment_csv_lookup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Channel Status (10 pts)
    channel_found = result.get('channel_found', False)
    channel_status = result.get('channel_status', 'UNKNOWN')
    
    if channel_found:
        if channel_status in ['STARTED', 'DEPLOYED', 'RUNNING']:
            score += 10
            feedback_parts.append(f"Channel is running ({channel_status})")
        else:
            score += 5
            feedback_parts.append(f"Channel exists but status is {channel_status}")
    else:
        feedback_parts.append("Channel 'Provider_Enrichment' not found")

    # 2. Output Files Existence (20 pts)
    output_files = result.get('output_files', [])
    num_files = len(output_files)
    
    # We expect roughly the number of providers generated (8 in setup script)
    # The setup script generates 8 providers.
    if num_files >= 5:
        score += 20
        feedback_parts.append(f"Found {num_files} output files (Expected >= 5)")
    elif num_files > 0:
        score += int(20 * (num_files / 5))
        feedback_parts.append(f"Found partial output files: {num_files}")
    else:
        feedback_parts.append("No output files found")

    # 3. Data Accuracy (50 pts)
    # Reconstruct CSV map
    csv_b64 = result.get('csv_content_base64', '')
    provider_map = {} # ID -> (Last, First)
    
    if csv_b64:
        try:
            csv_content = base64.b64decode(csv_b64).decode('utf-8')
            reader = csv.DictReader(io.StringIO(csv_content))
            for row in reader:
                # Handle potential BOM or whitespace
                pid = row.get('ProviderID', '').strip()
                last = row.get('LastName', '').strip()
                first = row.get('FirstName', '').strip()
                if pid:
                    provider_map[pid] = (last, first)
        except Exception as e:
            feedback_parts.append(f"Error parsing reference CSV: {e}")

    correct_enrichment_count = 0
    total_checked = 0
    
    if provider_map and output_files:
        for file_obj in output_files:
            try:
                content = base64.b64decode(file_obj['content']).decode('utf-8')
                # Parse HL7 manually to be robust
                segments = content.split('\r')
                pv1 = next((s for s in segments if s.startswith('PV1|')), None)
                if pv1:
                    fields = pv1.split('|')
                    # PV1-7 is usually index 7
                    if len(fields) > 7:
                        prov_field = fields[7]
                        comps = prov_field.split('^')
                        p_id = comps[0] if len(comps) > 0 else ""
                        p_last = comps[1] if len(comps) > 1 else ""
                        p_first = comps[2] if len(comps) > 2 else ""
                        
                        if p_id in provider_map:
                            total_checked += 1
                            exp_last, exp_first = provider_map[p_id]
                            
                            # Check match (case insensitive)
                            if p_last.lower() == exp_last.lower() and p_first.lower() == exp_first.lower():
                                correct_enrichment_count += 1
                            else:
                                feedback_parts.append(f"Mismatch in {file_obj['filename']}: ID={p_id}, Got={p_last}^{p_first}, Exp={exp_last}^{exp_first}")
            except Exception:
                continue

    if total_checked > 0:
        accuracy = correct_enrichment_count / total_checked
        points = int(50 * accuracy)
        score += points
        feedback_parts.append(f"Enrichment Accuracy: {correct_enrichment_count}/{total_checked} correct ({int(accuracy*100)}%)")
    elif num_files > 0:
        feedback_parts.append("Could not verify enrichment (CSV parsing or HL7 format issue)")
    
    # 4. Implementation Optimization (20 pts)
    # Check if Deploy Script reads the file
    deploy_script_b64 = result.get('deploy_script_content_base64', '')
    deploy_script = ""
    if deploy_script_b64:
        deploy_script = base64.b64decode(deploy_script_b64).decode('utf-8')
    
    # Keywords indicating file reading in Java/JS
    keywords = ['java.io.File', 'FileReader', 'BufferedReader', 'Scanner', 'FileUtils', 'csv']
    # Also check for global map usage
    map_keywords = ['globalChannelMap', '$gc', 'put', 'GlobalMap']
    
    has_file_io = any(k in deploy_script for k in keywords)
    has_map_usage = any(k in deploy_script for k in map_keywords)
    
    if has_file_io and has_map_usage:
        score += 20
        feedback_parts.append("Deploy script correctly implements File I/O and Global Map caching")
    elif has_file_io:
        score += 10
        feedback_parts.append("Deploy script has File I/O but missing map assignment keywords")
    elif deploy_script.strip():
        feedback_parts.append("Deploy script is present but doesn't look like it reads files (missing keywords)")
    else:
        feedback_parts.append("Deploy script is empty - likely implemented logic in Transformer (suboptimal)")

    # Final logic
    passed = score >= 80  # Requires most things to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }