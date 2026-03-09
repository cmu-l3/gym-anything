#!/bin/bash
echo "=== Setting up Verify Levee Freeboard Compliance task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie Project
restore_muncie_project
PROJECT_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
GT_DIR="/var/lib/hec_ras/ground_truth"

mkdir -p "$RESULTS_DIR"
mkdir -p "$GT_DIR"

# 2. Ensure simulation results exist (needed to generate consistent ground truth)
# We pre-run the simulation so we can generate a survey that definitely has failing points based on THIS simulation.
if [ ! -f "$PROJECT_DIR/Muncie.p04.hdf" ]; then
    echo "Pre-running HEC-RAS simulation to generate ground truth..."
    # Launch in background but wait for it
    cd "$PROJECT_DIR"
    # Use RasUnsteady from PATH
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$PROJECT_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04" > /tmp/hec_run.log 2>&1
    
    # Rename output to standard hdf
    if [ -f "Muncie.p04.tmp.hdf" ]; then
        cp "Muncie.p04.tmp.hdf" "Muncie.p04.hdf"
    fi
else
    echo "Simulation results already exist."
fi

# 3. Generate Dynamic Survey Data (Ground Truth)
# We use a python script to read the geometry/results and create a survey file
# that forces some segments to fail.

cat > /tmp/generate_survey.py << 'PYEOF'
import h5py
import numpy as np
import pandas as pd
import os
import random

project_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
hdf_file = os.path.join(project_dir, "Muncie.p04.hdf")
survey_file = os.path.join(project_dir, "levee_survey.csv")
gt_file = "/var/lib/hec_ras/ground_truth/levee_compliance_gt.csv"

try:
    with h5py.File(hdf_file, 'r') as f:
        # 1. Get River Stations and Max WSE
        # Paths depend on HEC-RAS version, trying standard 6.x paths
        # Geometry River Stations
        try:
            stations = f['Geometry/Cross Sections/Attributes'][:] 
            # Attributes is a compound type, usually column 'River Station'
            # But sometimes it's simpler to get just names if available.
            # Let's try reading the 1D arrays directly if possible, or parsing 2D
            
            # Fallback to reading sorted station names if strict structure fails
            # Actually, standard path for WSE is:
            # Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
            
            wse_data = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'][:]
            # Max over time (axis 0 is time, axis 1 is cross section)
            max_wse = np.max(wse_data, axis=0)
            
            # We need the station values (float) for interpolation
            # Typically in Geometry/Cross Sections/River Stations as strings or floats
            # Let's use a simpler approach: 
            # If we can't easily parse specific HDF structure in this script, generate a reasonable synthetic profile
            # assuming Muncie range approx 23000 down to 0 ft.
            
            # BETTER: Use the actual data if we can find the station map.
            # Often stored in 'Geometry/Cross Sections/River Stations'
            st_path = 'Geometry/Cross Sections/River Stations'
            if st_path in f:
                raw_stations = f[st_path][:]
                # Convert bytes to string then float
                stations_float = []
                for s in raw_stations:
                    try:
                        s_str = s.decode('utf-8').strip()
                        stations_float.append(float(s_str))
                    except:
                        pass
                stations_float = np.array(stations_float)
            else:
                # Fallback Muncie stations (approximate known range)
                stations_float = np.linspace(23000, 1000, len(max_wse))
                
        except Exception as e:
            print(f"Error reading HDF structure: {e}")
            # Fallback for demo purposes if HDF read fails (shouldn't happens if sim ran)
            stations_float = np.linspace(20000, 1000, 100)
            max_wse = np.linspace(950, 930, 100) # Dummy gradient

        # Ensure sorted descending (upstream to downstream)
        if stations_float[0] < stations_float[-1]:
             # If ascending, flip everything
             stations_float = stations_float[::-1]
             max_wse = max_wse[::-1]

        # 2. Generate Survey Points (misaligned with model stations)
        # Create survey stations every 500 ft
        min_s = stations_float.min()
        max_s = stations_float.max()
        survey_stations = np.arange(np.floor(min_s/500)*500, np.ceil(max_s/500)*500, 500)[::-1]
        
        # Interpolate WSE to survey stations
        # numpy.interp expects x to be increasing
        interp_wse = np.interp(survey_stations, stations_float[::-1], max_wse[::-1])
        
        # 3. Create Levee Elevations with Pass/Fail zones
        levee_elevs = []
        statuses = []
        freeboards = []
        
        # Define a "fail zone" in the middle
        fail_zone_start = max_s - (max_s - min_s) * 0.4
        fail_zone_end = max_s - (max_s - min_s) * 0.6
        
        for s, wse in zip(survey_stations, interp_wse):
            if fail_zone_start >= s >= fail_zone_end:
                # Create a failure (Freeboard < 3.0)
                # E.g., Freeboard = 1.5 ft
                fb = 1.5 + random.uniform(-0.5, 0.5)
                levee_z = wse + fb
                status = "FAIL"
            else:
                # Create a pass (Freeboard > 3.0)
                # E.g., Freeboard = 4.5 ft
                fb = 4.5 + random.uniform(-0.5, 1.5)
                levee_z = wse + fb
                status = "PASS"
            
            levee_elevs.append(np.round(levee_z, 2))
            freeboards.append(fb)
            statuses.append(status)
            
        # 4. Save Agent File (Input)
        df_agent = pd.DataFrame({
            'Station_ft': survey_stations,
            'Levee_Top_Elev_ft': levee_elevs
        })
        df_agent.to_csv(survey_file, index=False)
        print(f"Generated survey file at {survey_file}")
        
        # 5. Save Ground Truth File (Hidden)
        df_gt = pd.DataFrame({
            'Station_ft': survey_stations,
            'Levee_Top_Elev_ft': levee_elevs,
            'Modeled_WSE_ft': np.round(interp_wse, 2),
            'Freeboard_ft': np.round(freeboards, 2),
            'Status': statuses
        })
        df_gt.to_csv(gt_file, index=False)
        print(f"Generated ground truth at {gt_file}")

except Exception as e:
    print(f"CRITICAL ERROR generating data: {e}")
PYEOF

# Run the python script
su - ga -c "python3 /tmp/generate_survey.py"

# Verify CSV generation
if [ ! -f "/home/ga/Documents/hec_ras_projects/Muncie/levee_survey.csv" ]; then
    echo "ERROR: Survey generation failed. Creating fallback dummy."
    echo "Station_ft,Levee_Top_Elev_ft" > /home/ga/Documents/hec_ras_projects/Muncie/levee_survey.csv
    echo "10000,950.0" >> /home/ga/Documents/hec_ras_projects/Muncie/levee_survey.csv
fi

# Set permissions
chown ga:ga "$PROJECT_DIR/levee_survey.csv"
chmod 644 "$PROJECT_DIR/levee_survey.csv"
chmod 600 "$GT_DIR/levee_compliance_gt.csv" 2>/dev/null || true

# 4. Set Initial State
date +%s > /tmp/task_start_time.txt

# Open terminal in project dir
launch_terminal "$PROJECT_DIR"

# Open file explorer for visibility
su - ga -c "DISPLAY=:1 nautilus '$PROJECT_DIR' >/dev/null 2>&1 &"
sleep 2
DISPLAY=:1 wmctrl -a "Muncie" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="