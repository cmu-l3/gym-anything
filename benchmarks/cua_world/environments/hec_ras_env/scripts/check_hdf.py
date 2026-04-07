import h5py
import numpy as np
import os
import sys

hdf_paths = [
    "/opt/hec-ras/examples/Muncie/Muncie.p04.hdf",
    "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf",
    "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
]

for p in hdf_paths:
    print("Checking", p, os.path.exists(p))

found = None
for p in hdf_paths:
    if os.path.exists(p):
        found = p
        break

if not found:
    print("Could not find Muncie HDF file.")
    sys.exit(0)

print(f"Reading {found}")

with h5py.File(found, 'r') as f:
    base_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections"
    
    if base_path not in f:
        print(f"Path {base_path} not found in HDF")
        sys.exit(0)
        
    xs_group = f[base_path]
    ground_truth = {}
    
    for rs_name in xs_group.keys():
        rs_data = xs_group[rs_name]
        
        shear_ds_name = None
        for key in rs_data.keys():
            if "Shear" in key and "Channel" in key:
                shear_ds_name = key
                break
        
        if not shear_ds_name:
            for key in rs_data.keys():
                if "Shear Stress" in key:
                    shear_ds_name = key
                    break
        
        if shear_ds_name:
            data = rs_data[shear_ds_name][()]
            max_shear = float(np.max(data))
            ground_truth[rs_name] = max_shear

    print(f"Extracted {len(ground_truth)} stations.")
    if ground_truth:
        max_rs = max(ground_truth, key=ground_truth.get)
        print(f"Station with Max Shear: {max_rs} ({ground_truth[max_rs]} lb/sq ft)")
