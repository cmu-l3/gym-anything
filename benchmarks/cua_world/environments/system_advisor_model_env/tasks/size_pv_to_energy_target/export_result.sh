#!/bin/bash
echo "=== Exporting task results ==="

RESULT_FILE="/home/ga/Documents/SAM_Projects/tucson_sizing_result.json"
EXPORT_FILE="/tmp/task_result.json"
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Run Python script to extract JSON data AND perform PySAM cross-validation
# (Since the host verifier doesn't have PySAM installed, we do the simulation check inside the container)
python3 << PYEOF
import json
import os
import glob
import traceback

result_file = "$RESULT_FILE"
task_start = $TASK_START

export = {
    "file_exists": False,
    "file_modified_after_start": False,
    "valid_json": False,
    "system_capacity_kw": None,
    "annual_energy_kwh": None,
    "capacity_factor_pct": None,
    "monthly_energy_kwh": None,
    "target_energy_kwh": None,
    "location": None,
    "tilt_deg": None,
    "azimuth_deg": None,
    "cross_sim_annual_energy": None,
    "cross_sim_capacity_factor": None,
    "cross_sim_error": None,
    "python_used": False
}

# Check if Python was used (anti-gaming)
if os.path.exists("/home/ga/.bash_history"):
    with open("/home/ga/.bash_history", "r", errors="ignore") as f:
        if "python" in f.read():
            export["python_used"] = True

if os.path.exists(result_file):
    export["file_exists"] = True
    stat = os.stat(result_file)
    export["file_modified_after_start"] = stat.st_mtime > task_start

    try:
        with open(result_file) as f:
            data = json.load(f)
        export["valid_json"] = True

        # Extract required fields
        for key in ["system_capacity_kw", "annual_energy_kwh", "capacity_factor_pct",
                    "monthly_energy_kwh", "target_energy_kwh", "location", "tilt_deg", "azimuth_deg"]:
            if key in data:
                export[key] = data[key]

    except Exception as e:
        export["json_error"] = str(e)

    # Cross-simulation validation using PySAM
    sys_cap = export["system_capacity_kw"]
    if sys_cap is not None:
        try:
            import PySAM.Pvwattsv8 as pv
            system = pv.default("PVWattsNone")

            # Locate weather file
            solar_res_dir = ""
            if os.path.exists("/home/ga/.SAM/solar_resource_dir.txt"):
                solar_res_dir = open("/home/ga/.SAM/solar_resource_dir.txt").read().strip()

            weather_file = None
            if solar_res_dir and os.path.isdir(solar_res_dir):
                # Try Tucson, then Phoenix, then any AZ file, then any CSV
                candidates = glob.glob(os.path.join(solar_res_dir, "*tucson*")) + \
                             glob.glob(os.path.join(solar_res_dir, "*Tucson*")) + \
                             glob.glob(os.path.join(solar_res_dir, "*phoenix*")) + \
                             glob.glob(os.path.join(solar_res_dir, "*Phoenix*")) + \
                             glob.glob(os.path.join(solar_res_dir, "*az_*")) + \
                             glob.glob(os.path.join(solar_res_dir, "*.csv"))
                if candidates:
                    weather_file = candidates[0]

            if weather_file:
                system.SolarResource.solar_resource_file = weather_file
                system.SystemDesign.system_capacity = float(sys_cap)
                system.SystemDesign.array_type = 0  # Fixed open rack
                system.SystemDesign.tilt = float(export.get("tilt_deg", 32))
                system.SystemDesign.azimuth = float(export.get("azimuth_deg", 180))
                system.SystemDesign.dc_ac_ratio = 1.2
                system.SystemDesign.losses = 14.08
                system.SystemDesign.module_type = 0  # Standard

                system.execute()

                export["cross_sim_annual_energy"] = system.Outputs.annual_energy
                export["cross_sim_capacity_factor"] = system.Outputs.capacity_factor
                export["cross_sim_weather_file"] = weather_file
            else:
                export["cross_sim_error"] = "No weather file found"
        except Exception as e:
            export["cross_sim_error"] = str(e)

with open("$EXPORT_FILE", "w") as f:
    json.dump(export, f, indent=2)

print(json.dumps(export, indent=2))
PYEOF

chmod 666 "$EXPORT_FILE" 2>/dev/null || true
echo "=== Export complete ==="