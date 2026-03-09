#!/usr/bin/env python3
"""
Verifier for field_calc_gdp_percapita task.

Task: Add GDP_PCAP field (GDP_MD_EST * 1e6 / POP_EST) to countries layer,
      export to /home/ga/gvsig_exports/countries_gdp_percapita.shp

Scoring criteria (100 pts total):
  1. Output file exists                          (15 pts)
  2. GDP_PCAP field present in output            (30 pts)
  3. USA GDP_PCAP in plausible range [35k, 90k]  (25 pts)
  4. China GDP_PCAP in plausible range [4k, 22k] (20 pts)
  5. Feature count close to source 177 +/- 5    (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_field_calc_gdp_percapita(traj, env_info, task_info):
    """
    Verify that GDP per capita was calculated and exported correctly.

    Reads /tmp/field_calc_gdp_percapita_result.json written by export_result.sh.

    Scoring (100 points total):
    - Output file exists: 15 pts
    - GDP_PCAP field present: 30 pts
    - USA GDP_PCAP in plausible range [35k, 90k]: 25 pts
    - China GDP_PCAP in plausible range [4k, 22k]: 20 pts
    - Feature count close to source 177 ± 5: 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "ERROR: copy_from_env not available in env_info.",
            "subscores": {}
        }

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/field_calc_gdp_percapita_result.json', temp_path)
            with open(temp_path, 'r') as f:
                data = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result JSON: {e}",
            "subscores": {}
        }

    logger.info(f"Task result: {data}")

    score = 0
    subscores = {}
    feedback_parts = []

    # Criterion 1: Output file exists (15 pts)
    if data.get('file_exists'):
        subscores['file_exists'] = 15
        score += 15
        feedback_parts.append("Output shapefile exists.")
    else:
        subscores['file_exists'] = 0
        feedback_parts.append("FAIL: /home/ga/gvsig_exports/countries_gdp_percapita.shp not found.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Criterion 2: GDP_PCAP field present (30 pts)
    if data.get('has_gdp_pcap_field'):
        subscores['gdp_pcap_field'] = 30
        score += 30
        feedback_parts.append("GDP_PCAP field found in output.")
    else:
        subscores['gdp_pcap_field'] = 0
        fields_str = ', '.join(data.get('fields', [])[:15])
        feedback_parts.append(
            f"FAIL: GDP_PCAP field not found. Fields present: {fields_str}"
        )
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Criterion 3: USA GDP_PCAP in plausible range [35000, 90000] (25 pts)
    sample_values = data.get('sample_values', {})
    us_val = sample_values.get('United States')
    if us_val is not None:
        if 35_000 <= us_val <= 90_000:
            subscores['us_gdp_pcap'] = 25
            score += 25
            feedback_parts.append(f"USA GDP_PCAP = {us_val:,.0f} USD (plausible range 35k-90k).")
        else:
            subscores['us_gdp_pcap'] = 0
            feedback_parts.append(
                f"FAIL: USA GDP_PCAP = {us_val:,.2f} USD — outside expected range [35k-90k]. "
                "Check formula: should be GDP_MD_EST * 1e6 / POP_EST."
            )
    else:
        subscores['us_gdp_pcap'] = 0
        feedback_parts.append("FAIL: Could not find United States GDP_PCAP value in output.")

    # Criterion 4: China GDP_PCAP in plausible range [4000, 22000] (20 pts)
    cn_val = sample_values.get('China')
    if cn_val is not None:
        if 4_000 <= cn_val <= 22_000:
            subscores['china_gdp_pcap'] = 20
            score += 20
            feedback_parts.append(f"China GDP_PCAP = {cn_val:,.0f} USD (plausible range 4k-22k).")
        else:
            subscores['china_gdp_pcap'] = 0
            feedback_parts.append(
                f"FAIL: China GDP_PCAP = {cn_val:,.2f} USD — outside expected range [4k-22k]. "
                "Check formula: should be GDP_MD_EST * 1e6 / POP_EST."
            )
    else:
        subscores['china_gdp_pcap'] = 0
        feedback_parts.append("FAIL: Could not find China GDP_PCAP value in output.")

    # Criterion 5: Feature count close to source 177 ± 5 (10 pts)
    fc = data.get('feature_count')
    if fc is not None and 172 <= fc <= 182:
        subscores['feature_count'] = 10
        score += 10
        feedback_parts.append(f"Feature count: {fc} (expected ~177).")
    elif fc is not None and fc > 100:
        subscores['feature_count'] = 5
        score += 5
        feedback_parts.append(f"Feature count: {fc} (outside expected range 172-182 but non-trivial).")
    else:
        subscores['feature_count'] = 0
        feedback_parts.append(f"FAIL: Feature count {fc} is too low or unavailable.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
