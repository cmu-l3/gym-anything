#!/bin/bash
echo "=== Exporting FCD output task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# We will run a Python script inside the container to parse the XML files safely 
# since FCD files can be large, and writing a clean JSON is much easier.
echo "Analyzing configuration and FCD outputs..."

python3 << 'PYEOF' > /tmp/python_analysis.json
import xml.etree.ElementTree as ET
import json
import os
import time

# Helper to read task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

results = {
    "config_valid": False,
    "config_has_fcd_output": False,
    "config_fcd_path_correct": False,
    "config_fcd_period": None,
    "config_has_begin_end": False,
    "config_begin": None,
    "config_end": None,
    "config_retains_inputs": False,
    "config_has_tripinfo": False,
    "fcd_file_exists": False,
    "fcd_file_size": 0,
    "fcd_has_timesteps": False,
    "fcd_timestep_count": 0,
    "fcd_has_vehicles": False,
    "fcd_has_required_attrs": False,
    "fcd_min_time": None,
    "fcd_max_time": None,
    "fcd_time_span": 0,
    "fcd_avg_timestep_gap": None,
    "tripinfo_exists": False,
    "files_created_after_start": True
}

# Analyze configuration file
config_path = "/home/ga/SUMO_Scenarios/bologna_pasubio/run_fcd.sumocfg"
if os.path.exists(config_path):
    if os.path.getmtime(config_path) < task_start:
        results["files_created_after_start"] = False
        
    try:
        tree = ET.parse(config_path)
        root = tree.getroot()
        results["config_valid"] = True
        
        # Check input section
        input_elem = root.find(".//input")
        if input_elem is not None:
            net = input_elem.find("net-file")
            routes = input_elem.find("route-files")
            additional = input_elem.find("additional-files")
            if net is not None and routes is not None and additional is not None:
                if "pasubio" in (net.get("value", "") + routes.get("value", "") + additional.get("value", "")):
                    results["config_retains_inputs"] = True
        
        # Check output section
        output_elem = root.find(".//output")
        if output_elem is not None:
            fcd = output_elem.find("fcd-output")
            if fcd is not None:
                results["config_has_fcd_output"] = True
                fcd_path = fcd.get("value", "")
                if "pasubio_fcd.xml" in fcd_path and "SUMO_Output" in fcd_path:
                    results["config_fcd_path_correct"] = True
            
            fcd_period = output_elem.find("fcd-output.period")
            if fcd_period is not None:
                results["config_fcd_period"] = fcd_period.get("value", "")
            
            tripinfo = output_elem.find("tripinfo-output")
            if tripinfo is not None:
                results["config_has_tripinfo"] = True
        
        # Check time section
        time_elem = root.find(".//time")
        if time_elem is not None:
            begin = time_elem.find("begin")
            end = time_elem.find("end")
            if begin is not None and end is not None:
                results["config_has_begin_end"] = True
                results["config_begin"] = begin.get("value", "")
                results["config_end"] = end.get("value", "")
    except Exception as e:
        pass

# Analyze FCD output using iterparse (memory efficient)
fcd_path = "/home/ga/SUMO_Output/pasubio_fcd.xml"
if os.path.exists(fcd_path):
    if os.path.getmtime(fcd_path) < task_start:
        results["files_created_after_start"] = False
        
    results["fcd_file_exists"] = True
    results["fcd_file_size"] = os.path.getsize(fcd_path)
    
    try:
        timestep_times = []
        vehicle_count = 0
        has_required_attrs = False
        
        context = ET.iterparse(fcd_path, events=("start",))
        for event, elem in context:
            if elem.tag == "timestep":
                t = float(elem.get("time", -1))
                timestep_times.append(t)
                if len(timestep_times) > 1000:
                    pass # Just sampling
            elif elem.tag == "vehicle":
                vehicle_count += 1
                if not has_required_attrs:
                    attrs = set(elem.attrib.keys())
                    required = {"id", "x", "y", "speed"}
                    if required.issubset(attrs):
                        has_required_attrs = True
            # Clear elements to save memory
            elem.clear()
            
        results["fcd_has_timesteps"] = len(timestep_times) > 0
        results["fcd_timestep_count"] = len(timestep_times)
        results["fcd_has_vehicles"] = vehicle_count > 0
        results["fcd_has_required_attrs"] = has_required_attrs
        
        if timestep_times:
            results["fcd_min_time"] = min(timestep_times)
            results["fcd_max_time"] = max(timestep_times)
            results["fcd_time_span"] = max(timestep_times) - min(timestep_times)
            
            if len(timestep_times) > 1:
                gaps = [timestep_times[i+1] - timestep_times[i] for i in range(min(100, len(timestep_times)-1))]
                results["fcd_avg_timestep_gap"] = sum(gaps) / len(gaps)
    except Exception as e:
        pass

# Analyze tripinfo
tripinfo_path = "/home/ga/SUMO_Output/tripinfos.xml"
if os.path.exists(tripinfo_path):
    if os.path.getmtime(tripinfo_path) < task_start:
        results["files_created_after_start"] = False
    results["tripinfo_exists"] = True

print(json.dumps(results, indent=2))
PYEOF

# Move analysis results to the standard export path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/python_analysis.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/python_analysis.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Analysis JSON exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="