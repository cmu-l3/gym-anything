#!/usr/bin/env python3
"""
Verifier for constellation_isolation_audit task.

A ground systems engineer must verify that commanding INST does not cross-talk
to INST2, and vice versa. They execute commands in OpenC3 COSMOS and produce
a structured JSON isolation report at /home/ga/Desktop/isolation_audit.json.

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  File Creation: isolation_audit.json exists and was created during the session
  15pts  Schema Compliance: JSON contains all required keys and phase objects
  15pts  Phase 1 Logic: JSON correctly reflects INST incremented, INST2 isolated
  15pts  Phase 2 Logic: JSON correctly reflects INST2 incremented, INST isolated
  20pts  Live Target 1 Commanded: live INST COLLECTS counter > pre-task baseline
  25pts  Live Target 2 Commanded: live INST2 COLLECTS counter > pre-task baseline
 ---
 100pts total

Because the pass threshold is 70 points, the agent MUST successfully command both
satellites in the live system (45 points total from live checks). Simply
writing a hallucinatory JSON file will yield at most 55 points, failing the task.

Do-nothing invariant: passed=False (score <= 10)
"""

import json
import os
import tempfile


def verify_constellation_isolation_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/constellation_isolation_audit_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/isolation_audit.json')

    score = 0
    feedback = []

    # ── Step 1: Read export metadata (Anti-Gaming & File Freshness) ─────────
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)

    # Convert live telemetry values to float (handle 'unknown' or empty string gracefully)
    def parse_float(val):
        try:
            return float(val)
        except (ValueError, TypeError):
            return -1.0

    live_inst_initial = parse_float(export_meta.get('live_inst_initial', '0'))
    live_inst_final = parse_float(export_meta.get('live_inst_final', '0'))
    live_inst2_initial = parse_float(export_meta.get('live_inst2_initial', '0'))
    live_inst2_final = parse_float(export_meta.get('live_inst2_final', '0'))

    # ── Step 2: Live Anti-Gaming Checks (45 pts) ─────────────────────────────
    # Check if they actually sent the INST command
    if live_inst_final > live_inst_initial and live_inst_initial != -1.0:
        score += 20
        feedback.append(f"Live INST actually commanded (+20) [{live_inst_initial} -> {live_inst_final}]")
    else:
        feedback.append(f"Live INST NOT commanded (live counters unchanged: {live_inst_initial})")

    # Check if they actually sent the INST2 command
    if live_inst2_final > live_inst2_initial and live_inst2_initial != -1.0:
        score += 25
        feedback.append(f"Live INST2 actually commanded (+25) [{live_inst2_initial} -> {live_inst2_final}]")
    else:
        feedback.append(f"Live INST2 NOT commanded (live counters unchanged: {live_inst2_initial})")

    # ── Step 3: File Creation (10 pts) ───────────────────────────────────────
    if not file_exists:
        feedback.append("Audit report not found on Desktop (0 pts for file contents)")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    if not file_is_new:
        feedback.append("Audit report predates task start (no content credit)")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 10
    feedback.append("Audit report created during session (+10)")

    # ── Step 4: Parse Audit JSON ─────────────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f"Audit file is not valid JSON: {e}")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f"Could not copy audit file: {e}")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 5: Schema Compliance (15 pts) ───────────────────────────────────
    required_keys = {'operator', 'test_timestamp', 'phase1_command_inst', 'phase2_command_inst2', 'system_isolated'}
    missing_keys = required_keys - set(report.keys())
    
    if missing_keys:
        feedback.append(f"Missing top-level keys: {sorted(missing_keys)}")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
        
    p1 = report.get('phase1_command_inst', {})
    p2 = report.get('phase2_command_inst2', {})
    
    if not isinstance(p1, dict) or not isinstance(p2, dict):
        feedback.append("phase1 and phase2 must be JSON objects")
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    score += 15
    feedback.append("Schema compliance met (+15)")

    # ── Step 6: Phase 1 Logic (15 pts) ───────────────────────────────────────
    try:
        p1_i1_init = float(p1.get('inst_initial_collects', 0))
        p1_i1_final = float(p1.get('inst_final_collects', 0))
        p1_i2_init = float(p1.get('inst2_initial_collects', 0))
        p1_i2_final = float(p1.get('inst2_final_collects', 0))
        
        p1_i1_inc = p1.get('inst_incremented')
        p1_i2_iso = p1.get('inst2_isolated')
        
        if (p1_i1_final > p1_i1_init) and (p1_i2_final == p1_i2_init) and (p1_i1_inc is True) and (p1_i2_iso is True):
            score += 15
            feedback.append("Phase 1 logic correct (+15)")
        else:
            feedback.append("Phase 1 logic failed: INST must increment, INST2 must remain static")
    except (ValueError, TypeError):
        feedback.append("Phase 1 logic failed: values must be numeric")

    # ── Step 7: Phase 2 Logic (15 pts) ───────────────────────────────────────
    try:
        p2_i1_init = float(p2.get('inst_initial_collects', 0))
        p2_i1_final = float(p2.get('inst_final_collects', 0))
        p2_i2_init = float(p2.get('inst2_initial_collects', 0))
        p2_i2_final = float(p2.get('inst2_final_collects', 0))
        
        p2_i2_inc = p2.get('inst2_incremented')
        p2_i1_iso = p2.get('inst_isolated')
        
        if (p2_i2_final > p2_i2_init) and (p2_i1_final == p2_i1_init) and (p2_i2_inc is True) and (p2_i1_iso is True):
            score += 15
            feedback.append("Phase 2 logic correct (+15)")
        else:
            feedback.append("Phase 2 logic failed: INST2 must increment, INST must remain static")
    except (ValueError, TypeError):
        feedback.append("Phase 2 logic failed: values must be numeric")

    # ── Finalize ─────────────────────────────────────────────────────────────
    passed = score >= 70
    return {'passed': passed, 'score': score, 'feedback': ' | '.join(feedback)}