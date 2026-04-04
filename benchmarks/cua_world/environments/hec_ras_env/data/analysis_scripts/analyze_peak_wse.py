#!/usr/bin/env python3
"""Analyze peak water surface elevation from HEC-RAS HDF5 results.

Reads a HEC-RAS plan HDF5 file and extracts:
- Peak water surface elevation (WSE) across all cells
- Time of peak WSE
- Location of peak WSE
- Summary statistics

Usage:
    python3 analyze_peak_wse.py <plan_hdf_file> [output_csv]

Example:
    python3 analyze_peak_wse.py Muncie.p04.hdf peak_wse_results.csv
"""

import sys
import os
import h5py
import numpy as np

def find_results_path(hdf_file):
    """Find the path to unsteady time series results in the HDF5 file."""
    candidates = [
        "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series",
        "Results/Unsteady/Output/Output Blocks/DSS Profile Output/Unsteady Time Series",
    ]
    for path in candidates:
        if path in hdf_file:
            return path
    # Search for it
    result = []
    def visitor(name, obj):
        if "Unsteady Time Series" in name and isinstance(obj, h5py.Group):
            result.append(name)
    hdf_file.visititems(visitor)
    return result[0] if result else None

def analyze_peak_wse(hdf_path, output_csv=None):
    """Analyze peak water surface elevation from HEC-RAS HDF5 results."""
    if not os.path.exists(hdf_path):
        print(f"ERROR: File not found: {hdf_path}")
        return False

    print(f"Opening HDF5 file: {hdf_path}")
    print(f"File size: {os.path.getsize(hdf_path) / 1024 / 1024:.1f} MB")
    print()

    with h5py.File(hdf_path, "r") as f:
        # Print top-level structure
        print("=== HDF5 File Structure ===")
        for key in f.keys():
            print(f"  /{key}")

        # Find results path
        ts_path = find_results_path(f)
        if ts_path is None:
            print("ERROR: Could not find unsteady time series results")
            print("Available paths:")
            f.visititems(lambda name, obj: print(f"  {name}") if isinstance(obj, h5py.Group) else None)
            return False

        print(f"\nResults path: {ts_path}")

        # Look for 2D flow areas
        flow_areas_2d = f"{ts_path}/2D Flow Areas"
        flow_areas_1d = f"{ts_path}/Cross Sections"

        results_data = []

        if flow_areas_2d in f:
            print("\n=== 2D Flow Area Results ===")
            for area_name in f[flow_areas_2d].keys():
                area_path = f"{flow_areas_2d}/{area_name}"
                print(f"\nFlow Area: {area_name}")
                print(f"  Datasets: {list(f[area_path].keys())}")

                wse_path = f"{area_path}/Water Surface"
                if wse_path in f:
                    wse = f[wse_path][:]
                    print(f"  WSE array shape: {wse.shape} (timesteps x cells)")

                    # Filter out invalid values
                    valid_mask = np.isfinite(wse) & (wse > -9000)
                    if valid_mask.any():
                        valid_wse = np.where(valid_mask, wse, np.nan)
                        peak_wse = np.nanmax(valid_wse)
                        peak_idx = np.unravel_index(np.nanargmax(valid_wse), valid_wse.shape)
                        mean_peak = np.nanmax(valid_wse, axis=0)  # peak per cell
                        mean_peak_valid = mean_peak[np.isfinite(mean_peak)]

                        print(f"\n  === Peak Water Surface Elevation ===")
                        print(f"  Overall Peak WSE:   {peak_wse:.3f}")
                        print(f"  Peak timestep:      {peak_idx[0]}")
                        print(f"  Peak cell index:    {peak_idx[1]}")
                        print(f"  Mean Peak WSE:      {np.nanmean(mean_peak_valid):.3f}")
                        print(f"  Min Peak WSE:       {np.nanmin(mean_peak_valid):.3f}")
                        print(f"  Max Peak WSE:       {np.nanmax(mean_peak_valid):.3f}")
                        print(f"  Std Dev Peak WSE:   {np.nanstd(mean_peak_valid):.3f}")
                        print(f"  Number of cells:    {wse.shape[1]}")
                        print(f"  Number of timesteps: {wse.shape[0]}")

                        results_data.append({
                            'area': area_name,
                            'peak_wse': peak_wse,
                            'peak_timestep': peak_idx[0],
                            'peak_cell': peak_idx[1],
                            'mean_peak': np.nanmean(mean_peak_valid),
                            'num_cells': wse.shape[1],
                            'num_timesteps': wse.shape[0]
                        })

        if flow_areas_1d in f:
            print("\n=== 1D Cross Section Results ===")
            try:
                for xs_name in list(f[flow_areas_1d].keys())[:10]:
                    xs_path = f"{flow_areas_1d}/{xs_name}"
                    obj = f[xs_path]
                    if isinstance(obj, h5py.Group) and "Water Surface" in obj:
                        wse = obj["Water Surface"][:]
                        valid = wse[np.isfinite(wse) & (wse > -9000)]
                        if len(valid) > 0:
                            print(f"  {xs_name}: Peak WSE = {np.max(valid):.3f}")
            except (TypeError, KeyError) as e:
                print(f"  (Skipping 1D cross sections: {e})")

        # Check summary output
        summary_path = "Results/Unsteady/Output/Output Blocks/Summary Output"
        if summary_path in f:
            print("\n=== Summary Output ===")
            for key in f[summary_path].keys():
                print(f"  {key}")

        # Write CSV output
        if output_csv and results_data:
            with open(output_csv, 'w') as csvf:
                csvf.write("Area,Peak_WSE,Peak_Timestep,Peak_Cell,Mean_Peak_WSE,Num_Cells,Num_Timesteps\n")
                for r in results_data:
                    csvf.write(f"{r['area']},{r['peak_wse']:.3f},{r['peak_timestep']},"
                              f"{r['peak_cell']},{r['mean_peak']:.3f},{r['num_cells']},"
                              f"{r['num_timesteps']}\n")
            print(f"\nResults written to: {output_csv}")

    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_peak_wse.py <plan_hdf_file> [output_csv]")
        print("Example: python3 analyze_peak_wse.py Muncie.p04.hdf peak_wse_results.csv")
        sys.exit(1)

    hdf_path = sys.argv[1]
    output_csv = sys.argv[2] if len(sys.argv) > 2 else None

    success = analyze_peak_wse(hdf_path, output_csv)
    sys.exit(0 if success else 1)
