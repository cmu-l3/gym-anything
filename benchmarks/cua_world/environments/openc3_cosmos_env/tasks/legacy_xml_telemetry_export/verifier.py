#!/usr/bin/env python3
"""
Verifier for legacy_xml_telemetry_export task.

A ground station engineer must sample live telemetry from OpenC3 COSMOS
10 times at 1-second intervals and format it into a rigid XML schema.

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  File Freshness: File exists and was created after task start (Hard Gate)
  20pts  Valid XML Syntax: File parses successfully as XML
  10pts  Root Schema Validation: Root is TelemetryExport with target/packet attributes
  20pts  Sample Node Count: Exactly 10 <Sample> nodes with sequential indices
  20pts  Parameter Completeness: All samples contain TEMP1, TEMP2, COLLECTS with correct units
  10pts  Temporal Progression: Timestamps parse and show >= 0.5s delta between consecutive samples
  10pts  Live Data Variance: TEMP1 values show variance (not a hardcoded static value copied 10x)
 ---
 100pts total

Do-nothing invariant: passed=False (score = 0)
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _parse_iso(timestamp_str):
    """Safely parse ISO 8601 string, handling 'Z'."""
    try:
        if timestamp_str.endswith('Z'):
            timestamp_str = timestamp_str[:-1] + '+00:00'
        return datetime.fromisoformat(timestamp_str)
    except Exception:
        return None


def verify_legacy_xml_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/legacy_xml_telemetry_export_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/legacy_telemetry_export.xml')

    score = 0
    feedback = []

    # ── Step 1: Read export metadata ────────────────────────────────────────
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

    # ── Criterion 1: File Freshness (10 pts - HARD GATE) ────────────────────
    if not file_exists:
        feedback.append('XML file not found on Desktop (0 pts)')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    if not file_is_new:
        feedback.append('XML file predates task start (Not created this session). No content credit.')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    
    score += 10
    feedback.append('File exists and was created this session (+10)')

    # ── Step 2: Copy and Read XML File ──────────────────────────────────────
    xml_content = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.xml', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            xml_content = f.read()
    except Exception as e:
        feedback.append(f'Could not copy XML file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Criterion 2: Valid XML Syntax (20 pts) ──────────────────────────────
    try:
        root = ET.fromstring(xml_content)
        score += 20
        feedback.append('File is valid parseable XML (+20)')
    except ET.ParseError as e:
        feedback.append(f'Invalid XML syntax: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Criterion 3: Root Schema Validation (10 pts) ────────────────────────
    if root.tag == "TelemetryExport":
        if root.attrib.get("target") == "INST" and root.attrib.get("packet") == "HEALTH_STATUS":
            score += 10
            feedback.append('Root node and attributes correct (+10)')
        else:
            feedback.append(f"Root attributes incorrect: {root.attrib}")
    else:
        feedback.append(f"Incorrect root tag: {root.tag} (Expected TelemetryExport)")

    # ── Criterion 4: Sample Node Count (20 pts) ─────────────────────────────
    samples = root.findall('Sample')
    num_samples = len(samples)
    
    indices = []
    for s in samples:
        try:
            indices.append(int(s.attrib.get('index', -1)))
        except ValueError:
            pass

    has_10_samples = (num_samples == 10)
    sequential_indices = (indices == list(range(1, 11)))

    if has_10_samples and sequential_indices:
        score += 20
        feedback.append('Exactly 10 <Sample> nodes with sequential indices (+20)')
    else:
        feedback.append(f'Found {num_samples} <Sample> nodes. Indices match expected: {sequential_indices}')

    # ── Data extraction for further checks ──────────────────────────────────
    timestamps = []
    temp1_values = []
    completeness_pass = True

    required_params = {
        "TEMP1": "C",
        "TEMP2": "C",
        "COLLECTS": "COUNT"
    }

    for s in samples:
        ts_str = s.attrib.get('timestamp')
        if ts_str:
            dt = _parse_iso(ts_str)
            if dt:
                timestamps.append(dt)
        
        # Check params
        params = s.findall('Parameter')
        param_dict = {}
        for p in params:
            name = p.attrib.get('name')
            val = p.attrib.get('value')
            unit = p.attrib.get('unit')
            if name:
                param_dict[name] = {"value": val, "unit": unit}
                if name == "TEMP1" and val is not None:
                    try:
                        temp1_values.append(float(val))
                    except ValueError:
                        pass
        
        # Verify completeness
        for req_name, req_unit in required_params.items():
            if req_name not in param_dict:
                completeness_pass = False
            elif param_dict[req_name]["unit"] != req_unit:
                completeness_pass = False
            elif param_dict[req_name]["value"] is None:
                completeness_pass = False

    # ── Criterion 5: Parameter Completeness (20 pts) ────────────────────────
    if len(samples) > 0 and completeness_pass:
        score += 20
        feedback.append('All samples have required parameters and units (+20)')
    else:
        feedback.append('Parameter completeness failed (missing nodes, missing/wrong units, or empty values)')

    # ── Criterion 6: Temporal Progression (10 pts) ──────────────────────────
    temporal_pass = False
    if len(timestamps) == 10:
        temporal_pass = True
        for i in range(1, len(timestamps)):
            delta = (timestamps[i] - timestamps[i-1]).total_seconds()
            if delta < 0.5:
                temporal_pass = False
                break
    
    if temporal_pass:
        score += 10
        feedback.append('Timestamps show valid temporal progression >= 0.5s (+10)')
    else:
        if len(timestamps) != 10:
            feedback.append(f'Temporal progression failed: expected 10 valid timestamps, got {len(timestamps)}')
        else:
            feedback.append('Temporal progression failed: interval between samples < 0.5s')

    # ── Criterion 7: Live Data Variance (10 pts - ANTI-GAMING) ──────────────
    if len(temp1_values) >= 2 and len(set(temp1_values)) > 1:
        score += 10
        feedback.append('Telemetry data shows live variance (Not static/hardcoded) (+10)')
    else:
        feedback.append('Telemetry data variance failed (Constant values detected, suggesting hardcoded copy-paste)')

    # Evaluate final pass
    passed = (score >= 70)

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }