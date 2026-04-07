#!/usr/bin/env python3
"""
Verifier for model_ebus_charging_infrastructure task.

Uses `copy_from_env` to extract and parse XML configurations and simulation outputs.
Ensures SUMO's battery infrastructure was properly deployed and the scenario executed.
"""

import os
import json
import logging
import tempfile
import re
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def copy_file_from_env(copy_from_env, remote_path, local_dir):
    """Helper to safely copy a single file from the container."""
    filename = os.path.basename(remote_path)
    local_path = os.path.join(local_dir, filename)
    try:
        copy_from_env(remote_path, local_path)
        if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
            return local_path
    except Exception as e:
        logger.warning(f"Failed to copy {remote_path}: {e}")
    return None

def verify_ebus_charging(traj, env_info, task_info):
    """
    Verify the electric bus charging infrastructure task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_power = metadata.get('expected_charger_power', '200000')
    expected_cap = metadata.get('expected_battery_capacity', '50000')
    expected_charge = metadata.get('expected_battery_charge', '10000')

    score = 0
    feedback_parts = []
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Read JSON result
        result_json_path = copy_file_from_env(copy_from_env, "/tmp/task_result.json", temp_dir)
        if not result_json_path:
            return {"passed": False, "score": 0, "feedback": "Result JSON not found"}

        with open(result_json_path, 'r') as f:
            result = json.load(f)

        files_meta = result.get('files', {})

        # Copy all exported files
        cs_xml = copy_file_from_env(copy_from_env, "/tmp/ebus_export/charging_stations.add.xml", temp_dir)
        vtypes_xml = copy_file_from_env(copy_from_env, "/tmp/ebus_export/pasubio_vtypes.add.xml", temp_dir)
        busses_xml = copy_file_from_env(copy_from_env, "/tmp/ebus_export/pasubio_busses.rou.xml", temp_dir)
        config_xml = copy_file_from_env(copy_from_env, "/tmp/ebus_export/run.sumocfg", temp_dir)
        battery_xml = copy_file_from_env(copy_from_env, "/tmp/ebus_export/battery_output.xml", temp_dir)
        report_txt = copy_file_from_env(copy_from_env, "/tmp/ebus_export/battery_report.txt", temp_dir)

        # -------------------------------------------------------------
        # Criterion 1: Charging Station File (20 points)
        # -------------------------------------------------------------
        has_cs = False
        if cs_xml:
            try:
                tree = ET.parse(cs_xml)
                for cs in tree.iter('chargingStation'):
                    if cs.get('id') == 'fast_charger_1' and str(cs.get('power')) == expected_power:
                        has_cs = True
                        break
            except ET.ParseError:
                feedback_parts.append("charging_stations.add.xml is malformed")

        if has_cs:
            score += 20
            feedback_parts.append("Charging station correct")
        else:
            feedback_parts.append("Charging station missing or incorrect")

        # -------------------------------------------------------------
        # Criterion 2: Battery Parameters (20 points)
        # -------------------------------------------------------------
        has_params = False
        if vtypes_xml:
            try:
                tree = ET.parse(vtypes_xml)
                for vtype in tree.iter('vType'):
                    params = {p.get('key'): p.get('value') for p in vtype.iter('param')}
                    if (params.get('has.battery.device') == 'true' and 
                        params.get('device.battery.capacity') == expected_cap and
                        params.get('device.battery.chargeLevel') == expected_charge):
                        has_params = True
                        break
            except ET.ParseError:
                feedback_parts.append("pasubio_vtypes.add.xml is malformed")
        
        if has_params:
            score += 20
            feedback_parts.append("Battery parameters correct")
        else:
            feedback_parts.append("Battery parameters missing or incorrect")

        # -------------------------------------------------------------
        # Criterion 3: Charging Stop Added (15 points)
        # -------------------------------------------------------------
        has_stop = False
        if busses_xml:
            try:
                tree = ET.parse(busses_xml)
                for stop in tree.iter('stop'):
                    if stop.get('chargingStation') == 'fast_charger_1' and str(stop.get('duration')) == '120':
                        has_stop = True
                        break
            except ET.ParseError:
                feedback_parts.append("pasubio_busses.rou.xml is malformed")

        if has_stop:
            score += 15
            feedback_parts.append("Charging stop added")
        else:
            feedback_parts.append("Charging stop missing")

        # -------------------------------------------------------------
        # Criterion 4: Config Updated (15 points)
        # -------------------------------------------------------------
        has_config_add = False
        has_config_batt = False
        if config_xml:
            try:
                tree = ET.parse(config_xml)
                for add in tree.iter('additional-files'):
                    val = add.get('value', '')
                    if 'charging_stations.add.xml' in val:
                        has_config_add = True
                for bout in tree.iter('battery-output'):
                    if bout.get('value'):
                        has_config_batt = True
            except ET.ParseError:
                feedback_parts.append("run.sumocfg is malformed")

        if has_config_add and has_config_batt:
            score += 15
            feedback_parts.append("Config updated")
        else:
            feedback_parts.append("Config missing additional file or battery-output")

        # -------------------------------------------------------------
        # Criterion 5: Simulation Succeeded (20 points)
        # -------------------------------------------------------------
        batt_ok = False
        last_batt_cap = None
        batt_meta = files_meta.get('battery_output.xml', {})
        
        if battery_xml and batt_meta.get('created_during_task', False):
            try:
                tree = ET.parse(battery_xml)
                vehicles = list(tree.iter('vehicle'))
                if vehicles:
                    batt_ok = True
                    # Need to find the last known actualBatteryCapacity
                    # The <vehicle> tag has an actualBatteryCapacity attribute in the <timestep> tag
                    last_batt_cap = float(vehicles[-1].get('actualBatteryCapacity', 0))
            except ET.ParseError:
                feedback_parts.append("battery_output.xml is malformed")

        if batt_ok:
            score += 20
            feedback_parts.append("Simulation executed successfully")
        else:
            feedback_parts.append("Simulation failed or no battery output generated")

        # -------------------------------------------------------------
        # Criterion 6: Value Extracted (10 points)
        # -------------------------------------------------------------
        value_extracted = False
        if report_txt and last_batt_cap is not None:
            try:
                with open(report_txt, 'r') as f:
                    content = f.read().strip()
                numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
                if numbers:
                    for n in numbers:
                        if abs(float(n) - last_batt_cap) <= 1.0:
                            value_extracted = True
                            break
            except Exception:
                pass

        if value_extracted:
            score += 10
            feedback_parts.append(f"Correct capacity extracted (~{last_batt_cap:.2f})")
        else:
            feedback_parts.append("Failed to extract final capacity")

    # Final pass logic
    passed = score >= 70 and batt_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }