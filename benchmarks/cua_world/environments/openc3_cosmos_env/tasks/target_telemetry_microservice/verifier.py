#!/usr/bin/env python3
"""
Verifier for target_telemetry_microservice task.

Evaluates an agent-written HTTP microservice integrating with COSMOS.
Uses multi-criteria verification based on data captured by export_result.sh.

Scoring breakdown (100 pts total, pass threshold = 70):
  15pts: Port 8000 is open
  15pts: HTTP GET /api/inst/status returns 200 OK
  20pts: Response parses as JSON and matches strict schema
  20pts: Initial data accuracy (values match COSMOS truth within tolerance)
  30pts: Dynamic update validation (microservice reflects spacecraft state changes)

Anti-gaming:
The 30pt dynamic update checks that the returned `commands_accepted` increments
after the export script sends a live command to the spacecraft. This completely
prevents hardcoded static JSON responses.
"""

import json
import os
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def decode_b64_json(b64_str):
    """Safely decode base64 string to JSON dict."""
    if not b64_str:
        return None
    try:
        decoded_bytes = base64.b64decode(b64_str)
        return json.loads(decoded_bytes.decode('utf-8'))
    except Exception as e:
        logger.warning(f"Failed to decode/parse response: {e}")
        return None


def verify_telemetry_microservice(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/microservice_test_result.json')

    score = 0
    feedback = []

    # 1. Retrieve the exported test results
    test_results = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            test_results = json.load(f)
    except Exception as e:
        feedback.append(f"Result file not found or unreadable: {e}")
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 2. Port Open check (15 pts)
    port_open = test_results.get('port_open', False)
    if not port_open:
        feedback.append("Port 8000 is not open (Service not running or bound incorrectly)")
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    
    score += 15
    feedback.append("Port 8000 is open (+15)")

    # 3. HTTP 200 OK Check (15 pts)
    q1 = test_results.get('query_1', {})
    http_code = str(q1.get('http_code', '000'))
    if http_code == "200":
        score += 15
        feedback.append("HTTP GET /api/inst/status returned 200 OK (+15)")
    else:
        feedback.append(f"Route returned HTTP {http_code} instead of 200")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # 4. Schema Compliance (20 pts)
    resp1_json = decode_b64_json(q1.get('response_b64', ''))
    if not resp1_json:
        feedback.append("Response is missing or is not valid JSON")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # Check schema
    schema_ok = True
    if resp1_json.get('satellite') != "INST":
        schema_ok = False
        feedback.append("Schema error: 'satellite' != 'INST'")
    if resp1_json.get('service_status') != "ONLINE":
        schema_ok = False
        feedback.append("Schema error: 'service_status' != 'ONLINE'")
    if 'timestamp' not in resp1_json:
        schema_ok = False
        feedback.append("Schema error: Missing 'timestamp'")
    
    telemetry = resp1_json.get('telemetry', {})
    if not isinstance(telemetry, dict):
        schema_ok = False
        feedback.append("Schema error: 'telemetry' is not an object")
    else:
        for k in ['temperature_1', 'temperature_2', 'commands_accepted']:
            if k not in telemetry:
                schema_ok = False
                feedback.append(f"Schema error: Missing telemetry key '{k}'")
            elif telemetry[k] is None:
                schema_ok = False
                feedback.append(f"Schema error: '{k}' is null")

    if schema_ok:
        score += 20
        feedback.append("JSON response matches required schema (+20)")
    else:
        # Schema failures are severe but we might salvage data accuracy if structure is close
        pass

    # 5. Initial Data Accuracy (20 pts)
    data_accurate = False
    if isinstance(telemetry, dict):
        agent_t1 = telemetry.get('temperature_1')
        agent_t2 = telemetry.get('temperature_2')
        agent_cmd = telemetry.get('commands_accepted')

        truth_t1 = q1.get('truth_temp1')
        truth_t2 = q1.get('truth_temp2')
        truth_cmd = q1.get('truth_cmd_cnt')

        try:
            # Check numerical similarity (temperatures drift slightly, allow tolerance)
            t1_diff = abs(float(agent_t1) - float(truth_t1))
            t2_diff = abs(float(agent_t2) - float(truth_t2))
            cmd_diff = abs(int(agent_cmd) - int(truth_cmd))

            if t1_diff < 1.0 and t2_diff < 1.0 and cmd_diff == 0:
                data_accurate = True
                score += 20
                feedback.append("Initial telemetry data is accurate against COSMOS truth (+20)")
            else:
                feedback.append(f"Data mismatch: Expected CMD={truth_cmd}, got {agent_cmd}; T1 diff={t1_diff:.2f}")
        except (TypeError, ValueError):
            feedback.append("Data accuracy failed: returned telemetry values are not valid numbers")

    # 6. Dynamic Update Validation (30 pts)
    # To pass this, query 2's command count must be > query 1's command count, reflecting the injected command
    dynamic_ok = False
    q2 = test_results.get('query_2', {})
    resp2_json = decode_b64_json(q2.get('response_b64', ''))
    
    if resp2_json and isinstance(resp2_json.get('telemetry'), dict):
        agent_cmd_1 = telemetry.get('commands_accepted')
        agent_cmd_2 = resp2_json['telemetry'].get('commands_accepted')

        try:
            val1 = int(agent_cmd_1)
            val2 = int(agent_cmd_2)
            if val2 > val1:
                dynamic_ok = True
                score += 30
                feedback.append(f"Dynamic update successful: commands_accepted incremented {val1} -> {val2} (+30)")
            else:
                feedback.append(f"Dynamic update failed: commands_accepted stuck at {val1} (hardcoded or cached?)")
        except (TypeError, ValueError):
            feedback.append("Dynamic update check failed due to non-numeric telemetry values")
    else:
        feedback.append("Dynamic update check failed: second query did not return valid JSON schema")

    # Final pass logic
    # Must get >= 70 points AND must have successfully demonstrated dynamic real-time polling
    key_criteria_met = schema_ok and data_accurate and dynamic_ok
    passed = (score >= 70) and key_criteria_met

    if passed and not key_criteria_met:
        passed = False
        feedback.append("FAILED: Score was high enough, but missed key criteria (schema, accuracy, or dynamic update).")

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }