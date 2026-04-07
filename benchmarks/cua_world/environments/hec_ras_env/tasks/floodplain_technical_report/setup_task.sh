#!/bin/bash
# setup_task.sh — floodplain_technical_report
# Occupation: Civil Engineer / Hydraulic Engineer (O*NET 17-2051.00)
# Prepares baseline simulation results, critical infrastructure input file,
# backs up geometry, and launches terminal for the agent.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up floodplain_technical_report task ==="

# ----------------------------------------------------------------
# 1. Restore clean Muncie project and pre-run baseline simulation
# ----------------------------------------------------------------
restore_muncie_project
run_simulation_if_needed

# Restore clean HDF template so the agent can re-run the simulation
# for the sensitivity analysis. Baseline results are in Muncie.p04.hdf;
# the clean template (no output) goes back into Muncie.p04.tmp.hdf.
cp "${MUNCIE_DIR}/wrk_source/Muncie.p04.tmp.hdf" "${MUNCIE_DIR}/Muncie.p04.tmp.hdf"
chown ga:ga "${MUNCIE_DIR}/Muncie.p04.tmp.hdf"
echo "Restored clean HDF template for re-run capability"

# ----------------------------------------------------------------
# 2. Back up original b04 boundary condition file
#    (agent will modify it for the flow sensitivity check)
# ----------------------------------------------------------------
cp "${MUNCIE_DIR}/Muncie.b04" "${MUNCIE_DIR}/Muncie.b04.original_backup"

# ----------------------------------------------------------------
# 3. Clean stale outputs BEFORE recording timestamp
# ----------------------------------------------------------------
mkdir -p "${RESULTS_DIR}"
rm -f "${RESULTS_DIR}/floodplain_profile.csv"
rm -f "${RESULTS_DIR}/infrastructure_impact.csv"
rm -f "${RESULTS_DIR}/report_summary.txt"
chown -R ga:ga "${RESULTS_DIR}"

# ----------------------------------------------------------------
# 4. Record task start time (AFTER cleaning, BEFORE agent interaction)
# ----------------------------------------------------------------
date +%s > /tmp/task_start_floodplain
TASK_START=$(cat /tmp/task_start_floodplain)

# ----------------------------------------------------------------
# 5. Create critical infrastructure input CSV
#    Muncie reach stations range from 237.6 (DS) to 15696.2 (US).
#    Stations chosen between actual cross-section locations to
#    require genuine linear interpolation.
#    FFE values set to produce a realistic mix of FLOODED and SAFE.
# ----------------------------------------------------------------
cat > /home/ga/Documents/critical_infrastructure.csv << 'INFRA_EOF'
Facility_Name,River_Station,First_Floor_Elevation_ft
Ball_Memorial_Hospital,15100.0,957.00
Muncie_Central_High_School,13650.0,946.00
Delaware_County_Courthouse,11500.0,948.50
Riverside_Elementary,9700.0,943.00
White_River_WWTP,7750.0,946.50
Ball_State_University,5500.0,940.00
Muncie_Fire_Station_4,3100.0,943.00
Cardinal_Greenway_Trailhead,1600.0,935.00
INFRA_EOF

chown ga:ga /home/ga/Documents/critical_infrastructure.csv

# ----------------------------------------------------------------
# 6. Extract and save baseline ground truth from the pre-run
#    simulation. The export_result.sh will use this to compare
#    against the agent's outputs.
# ----------------------------------------------------------------
python3 << 'GTEOF'
import h5py
import numpy as np
import json
import os
import sys
import csv

muncie_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
hdf_path = os.path.join(muncie_dir, "Muncie.p04.hdf")
if not os.path.exists(hdf_path):
    hdf_path = os.path.join(muncie_dir, "Muncie.p04.tmp.hdf")

gt = {"error": None, "stations": [], "baseline_wse": [], "baseline_velocity": [],
      "bed_elevations": [], "num_cross_sections": 0}

try:
    with h5py.File(hdf_path, 'r') as f:
        # --- Cross-section River Stations ---
        # Stations are stored in the Attributes structured array under the 'RS' field
        attr_path = "Geometry/Cross Sections/Attributes"
        if attr_path in f:
            attrs = f[attr_path][:]
            stations = []
            for s in attrs['RS']:
                if isinstance(s, bytes):
                    stations.append(float(s.decode('utf-8').strip()))
                else:
                    stations.append(float(s))
            gt["stations"] = stations
            gt["num_cross_sections"] = len(stations)
        else:
            gt["error"] = "Geometry/Cross Sections/Attributes not found"

        # --- Peak WSE (max over time for each cross-section) ---
        wse_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface"
        if wse_path in f:
            wse_ts = f[wse_path][:]  # shape: (timesteps, cross_sections)
            max_wse = np.max(wse_ts, axis=0)
            gt["baseline_wse"] = [round(float(w), 4) for w in max_wse]

        # --- Max channel velocity (max over time) ---
        vel_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Velocity Total"
        if vel_path in f:
            vel_ts = f[vel_path][:]
            max_vel = np.max(vel_ts, axis=0)
            gt["baseline_velocity"] = [round(float(v), 4) for v in max_vel]

        # --- Minimum channel bed elevation ---
        # Compute from station elevation profile data (min elevation per XS)
        elev_path = "Geometry/Cross Sections/Station Elevation Values"
        info_path = "Geometry/Cross Sections/Station Elevation Info"
        if elev_path in f and info_path in f:
            elev_vals = f[elev_path][:]  # flat array of (station, elevation) pairs
            elev_info = f[info_path][:]  # (start_index, count) per cross-section
            bed_elevs = []
            for i in range(len(elev_info)):
                start = int(elev_info[i][0])
                count = int(elev_info[i][1])
                xs_elevs = elev_vals[start:start+count]
                # elevations are in column 1 of each pair
                if len(xs_elevs.shape) == 2 and xs_elevs.shape[1] >= 2:
                    min_elev = float(np.min(xs_elevs[:, 1]))
                else:
                    min_elev = float(np.min(xs_elevs))
                bed_elevs.append(round(min_elev, 4))
            gt["bed_elevations"] = bed_elevs
            gt["bed_elev_source"] = "Station Elevation Values (computed min)"

    # --- Compute interpolated WSE for infrastructure facilities ---
    infra_csv = "/home/ga/Documents/critical_infrastructure.csv"
    if os.path.exists(infra_csv) and gt["stations"] and gt["baseline_wse"]:
        stations_arr = np.array(gt["stations"])
        wse_arr = np.array(gt["baseline_wse"])
        sort_idx = np.argsort(stations_arr)
        x_sorted = stations_arr[sort_idx]
        y_sorted = wse_arr[sort_idx]

        infra_results = []
        with open(infra_csv, 'r') as csvf:
            reader = csv.DictReader(csvf)
            for row in reader:
                rs = float(row["River_Station"])
                ffe = float(row["First_Floor_Elevation_ft"])
                interp_wse = float(np.interp(rs, x_sorted, y_sorted))
                flood_depth = interp_wse - ffe
                status = "FLOODED" if flood_depth > 0 else "SAFE"
                infra_results.append({
                    "Facility_Name": row["Facility_Name"],
                    "River_Station": rs,
                    "FFE_ft": ffe,
                    "Interpolated_WSE_ft": round(interp_wse, 2),
                    "Flood_Depth_ft": round(flood_depth, 2),
                    "Status": status
                })
        gt["infrastructure_gt"] = infra_results
        gt["facilities_flooded"] = sum(1 for r in infra_results if r["Status"] == "FLOODED")
        gt["facilities_safe"] = sum(1 for r in infra_results if r["Status"] == "SAFE")

    # --- Compute baseline flood depths ---
    if gt["baseline_wse"] and gt["bed_elevations"]:
        gt["flood_depths"] = [round(w - b, 4) for w, b in zip(gt["baseline_wse"], gt["bed_elevations"])]
        gt["max_flood_depth"] = round(max(gt["flood_depths"]), 4)
        max_idx = gt["flood_depths"].index(max(gt["flood_depths"]))
        gt["max_flood_depth_station"] = gt["stations"][max_idx]

except Exception as e:
    gt["error"] = str(e)

with open("/tmp/floodplain_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

n_xs = gt.get("num_cross_sections", 0)
n_wse = len(gt.get("baseline_wse", []))
n_vel = len(gt.get("baseline_velocity", []))
n_bed = len(gt.get("bed_elevations", []))
print(f"Ground truth saved: {n_xs} cross-sections, {n_wse} WSE, {n_vel} velocity, {n_bed} bed elev")
if gt.get("error"):
    print(f"WARNING: {gt['error']}")
GTEOF

# ----------------------------------------------------------------
# 7. Open terminal in Muncie project directory
# ----------------------------------------------------------------
echo "Opening terminal..."
launch_terminal "${MUNCIE_DIR}"
sleep 2

# Display task context in the terminal
DISPLAY=:1 xdotool type --clearmodifiers --delay 20 \
    "echo '=== Floodplain Technical Report Task ===' && ls -la *.hdf *.x04 *.b04 && echo '' && echo '--- Infrastructure Data ---' && cat ~/Documents/critical_infrastructure.csv"
sleep 0.5
DISPLAY=:1 xdotool key --clearmodifiers Return
sleep 4

take_screenshot "/tmp/floodplain_task_start.png"

echo "=== floodplain_technical_report setup complete ==="
exit 0
