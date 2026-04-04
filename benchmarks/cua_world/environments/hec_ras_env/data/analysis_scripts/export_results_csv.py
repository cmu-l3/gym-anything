#!/usr/bin/env python3
"""Export HEC-RAS HDF5 simulation results to CSV format.

Reads a HEC-RAS plan HDF5 file and exports key results to CSV files:
- Water surface elevation time series
- Peak values per cell/cross section
- Summary statistics

Usage:
    python3 export_results_csv.py <plan_hdf_file> [output_directory]

Example:
    python3 export_results_csv.py Muncie.p04.hdf /home/ga/Documents/hec_ras_results/
"""

import sys
import os
import h5py
import numpy as np


def export_results(hdf_path, output_dir=None):
    """Export HEC-RAS results to CSV files."""
    if not os.path.exists(hdf_path):
        print(f"ERROR: File not found: {hdf_path}")
        return False

    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(hdf_path))

    os.makedirs(output_dir, exist_ok=True)

    print(f"Opening: {hdf_path}")
    print(f"Output directory: {output_dir}")

    with h5py.File(hdf_path, "r") as f:
        # Print structure overview
        print("\n=== HDF5 Structure ===")
        def print_structure(name, obj):
            if isinstance(obj, h5py.Dataset):
                print(f"  Dataset: {name}  shape={obj.shape}  dtype={obj.dtype}")
        f.visititems(print_structure)

        base_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series"
        if base_path not in f:
            print("ERROR: No unsteady time series found")
            return False

        # Export 2D flow area results
        flow_2d_path = f"{base_path}/2D Flow Areas"
        if flow_2d_path in f:
            for area_name in f[flow_2d_path].keys():
                area_path = f"{flow_2d_path}/{area_name}"
                print(f"\n--- Exporting 2D Flow Area: {area_name} ---")

                for dataset_name in f[area_path].keys():
                    ds = f[f"{area_path}/{dataset_name}"]
                    if not isinstance(ds, h5py.Dataset):
                        continue

                    data = ds[:]
                    if data.ndim == 2 and data.shape[0] > 1:
                        # Time series data: export peak per cell
                        valid = np.where(np.isfinite(data) & (data > -9000), data, np.nan)
                        peak_vals = np.nanmax(valid, axis=0)
                        peak_times = np.nanargmax(valid, axis=0)

                        csv_name = f"{area_name}_{dataset_name.replace(' ', '_')}_peaks.csv"
                        csv_path = os.path.join(output_dir, csv_name)
                        with open(csv_path, 'w') as csvf:
                            csvf.write("Cell_Index,Peak_Value,Peak_Timestep\n")
                            for i in range(len(peak_vals)):
                                if np.isfinite(peak_vals[i]):
                                    csvf.write(f"{i},{peak_vals[i]:.4f},{peak_times[i]}\n")
                        print(f"  Exported: {csv_name} ({np.sum(np.isfinite(peak_vals))} cells)")

                        # Also export summary statistics
                        valid_peaks = peak_vals[np.isfinite(peak_vals)]
                        if len(valid_peaks) > 0:
                            print(f"    Min: {np.min(valid_peaks):.3f}")
                            print(f"    Max: {np.max(valid_peaks):.3f}")
                            print(f"    Mean: {np.mean(valid_peaks):.3f}")
                            print(f"    Std: {np.std(valid_peaks):.3f}")

        # Export 1D cross section results
        xs_path = f"{base_path}/Cross Sections"
        if xs_path in f:
            xs_names = list(f[xs_path].keys())
            print(f"\n--- Exporting 1D Cross Sections ({len(xs_names)} sections) ---")

            csv_path = os.path.join(output_dir, "cross_section_peak_wse.csv")
            with open(csv_path, 'w') as csvf:
                csvf.write("Cross_Section,Peak_WSE,Peak_Timestep,Min_WSE,Mean_WSE\n")
                for xs_name in xs_names:
                    wse_path = f"{xs_path}/{xs_name}/Water Surface"
                    if wse_path in f:
                        wse = f[wse_path][:]
                        valid = wse[np.isfinite(wse) & (wse > -9000)]
                        if len(valid) > 0:
                            peak_wse = np.max(valid)
                            peak_ts = np.argmax(wse)
                            csvf.write(f"{xs_name},{peak_wse:.4f},{peak_ts},{np.min(valid):.4f},{np.mean(valid):.4f}\n")
            print(f"  Exported: cross_section_peak_wse.csv ({len(xs_names)} sections)")

        # Export summary output if available
        summary_path = "Results/Unsteady/Output/Output Blocks/Summary Output"
        if summary_path in f:
            print("\n--- Exporting Summary Output ---")
            for group_name in f[summary_path].keys():
                group_path = f"{summary_path}/{group_name}"
                if isinstance(f[group_path], h5py.Group):
                    for area_name in f[group_path].keys():
                        area_path = f"{group_path}/{area_name}"
                        for ds_name in f[area_path].keys():
                            ds = f[f"{area_path}/{ds_name}"]
                            if isinstance(ds, h5py.Dataset):
                                data = ds[:]
                                valid = data[np.isfinite(data) & (data > -9000)]
                                if len(valid) > 0:
                                    csv_name = f"summary_{area_name}_{ds_name.replace(' ', '_')}.csv"
                                    csv_path = os.path.join(output_dir, csv_name)
                                    with open(csv_path, 'w') as csvf:
                                        csvf.write("Index,Value\n")
                                        for i, v in enumerate(data.flat):
                                            if np.isfinite(v) and v > -9000:
                                                csvf.write(f"{i},{v:.4f}\n")
                                    print(f"  Exported: {csv_name}")

    print(f"\n=== Export Complete ===")
    print(f"Output files in: {output_dir}")
    for fname in sorted(os.listdir(output_dir)):
        if fname.endswith('.csv'):
            fsize = os.path.getsize(os.path.join(output_dir, fname))
            print(f"  {fname} ({fsize} bytes)")

    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 export_results_csv.py <plan_hdf_file> [output_directory]")
        print("Example: python3 export_results_csv.py Muncie.p04.hdf ./results/")
        sys.exit(1)

    hdf_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else None

    success = export_results(hdf_path, output_dir)
    sys.exit(0 if success else 1)
