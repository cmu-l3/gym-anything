#!/usr/bin/env python3
"""
Verifier for webhook_notification_integration task.

Evaluates an agent's ability to orchestrate spacecraft commanding with
external web service integration (HTTP POST JSON webhook).

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  Webhook server received at least 1 HTTP request
  20pts  Received payload(s) strictly match the required JSON schema
  20pts  Multiple alerts (≥ 3 valid alerts received)
  20pts  Monotonic increase (`collect_count` values strictly increase)
  30pts  Telemetry cross-reference: Commands actually sent in COSMOS and 
         webhook reported count aligns with real telemetry state.
 ---
 100pts total

Anti-Gaming features:
- If the agent just loops an HTTP POST with fake counts, the command 
  count check (current_cmds - initial_cmds >= 3) will fail, losing 30 pts.
- The reported max count cannot exceed the actual telemetry count.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_webhook_notification_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/webhook_notification_result.json')

    score = 0
    feedback = []

    # ── Step 1: Read export metadata ────────────────────────────────────────
    export_data = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        feedback.append(f'Failed to read export data: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # Extract metrics
    try:
        initial_cmds = int(export_data.get('initial_cmds', 0))
        current_cmds = int(export_data.get('current_cmds', 0))
        current_tlm = float(export_data.get('current_tlm', 0))
        payloads = export_data.get('payloads', [])
    except Exception as e:
        feedback.append(f'Malformed export metrics: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}

    cmds_sent = current_cmds - initial_cmds

    # ── Step 2: Webhook Hit (10 pts) ────────────────────────────────────────
    if not payloads:
        feedback.append('No HTTP POST requests received by the webhook server')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    score += 10
    feedback.append(f'Webhook received {len(payloads)} request(s) (+10)')

    # ── Step 3: JSON Schema Validity (20 pts) ───────────────────────────────
    valid_payloads = []
    for p in payloads:
        if not isinstance(p, dict):
            continue
        # Schema check
        if (p.get('satellite') == 'INST' and 
            p.get('alert_type') == 'COLLECT_COMPLETE' and 
            isinstance(p.get('collect_count'), (int, float))):
            valid_payloads.append(p)
            
    if not valid_payloads:
        feedback.append('None of the received payloads matched the required JSON schema')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    score += 20
    feedback.append(f'Found {len(valid_payloads)} schema-compliant payload(s) (+20)')

    # ── Step 4: Multiple Alerts (20 pts) ────────────────────────────────────
    if len(valid_payloads) >= 3:
        score += 20
        feedback.append('At least 3 valid alerts were received (+20)')
    else:
        feedback.append(f'Only received {len(valid_payloads)} valid alert(s), expected at least 3')

    # ── Step 5: Monotonic Increase (20 pts) ─────────────────────────────────
    if len(valid_payloads) > 1:
        counts = [p['collect_count'] for p in valid_payloads]
        is_monotonic = all(counts[i] < counts[i+1] for i in range(len(counts)-1))
        if is_monotonic:
            score += 20
            feedback.append(f'collect_count strictly increased across requests: {counts} (+20)')
        else:
            feedback.append(f'collect_count sequence is not strictly increasing: {counts}')
    elif len(valid_payloads) == 1:
        feedback.append('Cannot verify monotonic increase with only 1 valid payload')

    # ── Step 6: Telemetry Verification (30 pts) ─────────────────────────────
    # Anti-gaming: Prove they commanded the satellite and sent accurate data
    telemetry_passed = True
    
    if cmds_sent < 3:
        telemetry_passed = False
        feedback.append(f'Only {cmds_sent} INST COLLECT commands detected in COSMOS (expected >= 3)')
        
    max_reported = max([p['collect_count'] for p in valid_payloads]) if valid_payloads else 0
    if max_reported > current_tlm:
        telemetry_passed = False
        feedback.append(f'Reported collect_count ({max_reported}) exceeds actual COSMOS telemetry ({current_tlm})')

    if telemetry_passed:
        score += 30
        feedback.append('Webhook telemetry cross-referenced successfully with COSMOS state (+30)')

    # ── Final Determination ─────────────────────────────────────────────────
    passed = score >= 70
    
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback),
        'subscores': {
            'webhook_hit': len(payloads) > 0,
            'schema_valid': len(valid_payloads) > 0,
            'multiple_alerts': len(valid_payloads) >= 3,
            'telemetry_verified': telemetry_passed
        }
    }