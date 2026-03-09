#!/usr/bin/env python3
"""Plot flood hydrograph from HEC-RAS HDF5 results.

Reads a HEC-RAS plan HDF5 file and creates a matplotlib plot showing:
- Water surface elevation over time at a specified cell/cross section
- Peak water surface elevation marker
- Saves the plot as a PNG file

Usage:
    python3 plot_flood_hydrograph.py <plan_hdf_file> [output_png]

Example:
    python3 plot_flood_hydrograph.py Muncie.p04.hdf flood_hydrograph.png
"""

import sys
import os
import h5py
import numpy as np
import matplotlib
# Use TkAgg for interactive display if DISPLAY is set, otherwise Agg for headless
if os.environ.get('DISPLAY'):
    try:
        matplotlib.use('TkAgg')
    except ImportError:
        matplotlib.use('Agg')
else:
    matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime, timedelta


def find_wse_data(hdf_file):
    """Find water surface elevation data in the HDF5 file."""
    # Try 2D flow areas first
    base_paths = [
        "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series",
        "Results/Unsteady/Output/Output Blocks/DSS Profile Output/Unsteady Time Series",
    ]

    for base in base_paths:
        path_2d = f"{base}/2D Flow Areas"
        if path_2d in hdf_file:
            for area in hdf_file[path_2d].keys():
                wse_path = f"{path_2d}/{area}/Water Surface"
                if wse_path in hdf_file:
                    return hdf_file[wse_path][:], area, "2D"

        path_1d = f"{base}/Cross Sections"
        if path_1d in hdf_file:
            xs_names = list(hdf_file[path_1d].keys())
            if xs_names:
                for xs in xs_names:
                    wse_path = f"{path_1d}/{xs}/Water Surface"
                    if wse_path in hdf_file:
                        return hdf_file[wse_path][:], xs, "1D"

    return None, None, None


def parse_time_data(hdf_file):
    """Try to extract time information from the HDF5 file."""
    time_paths = [
        "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Time",
        "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Time Date Stamp",
    ]
    for path in time_paths:
        if path in hdf_file:
            data = hdf_file[path][:]
            if data.dtype.kind in ('U', 'S', 'O'):
                # String timestamps
                timestamps = []
                for t in data:
                    t_str = t.decode() if isinstance(t, bytes) else str(t)
                    for fmt in ["%d%b%Y %H:%M:%S", "%d%b%Y %H%M", "%Y-%m-%d %H:%M:%S",
                                "%d%b%Y  %H:%M:%S", "%d %b %Y %H:%M:%S"]:
                        try:
                            timestamps.append(datetime.strptime(t_str.strip(), fmt))
                            break
                        except ValueError:
                            continue
                if timestamps:
                    return timestamps
            else:
                # Numeric timestamps (hours or seconds from start)
                return data
    return None


def plot_flood_hydrograph(hdf_path, output_png=None):
    """Create a flood hydrograph plot from HEC-RAS results."""
    if not os.path.exists(hdf_path):
        print(f"ERROR: File not found: {hdf_path}")
        return False

    print(f"Opening: {hdf_path}")

    with h5py.File(hdf_path, "r") as f:
        wse_data, location_name, dim_type = find_wse_data(f)
        time_data = parse_time_data(f)

        if wse_data is None:
            print("ERROR: No water surface elevation data found")
            return False

        print(f"Found {dim_type} results for: {location_name}")
        print(f"WSE shape: {wse_data.shape}")

        # For 2D data, pick the cell with the most dynamic WSE (highest range)
        if wse_data.ndim == 2:
            valid = np.where(np.isfinite(wse_data) & (wse_data > -9000), wse_data, np.nan)
            wse_range = np.nanmax(valid, axis=0) - np.nanmin(valid, axis=0)
            cell_idx = np.nanargmax(wse_range)
            wse_series = valid[:, cell_idx]
            cell_range = wse_range[cell_idx]
            subtitle = f"Cell {cell_idx} (max flood range: {cell_range:.2f} ft)"
        else:
            wse_series = wse_data
            subtitle = location_name

        # Create time axis
        if time_data is not None:
            if isinstance(time_data, list) and isinstance(time_data[0], datetime):
                x_data = time_data[:len(wse_series)]
                x_label = "Date/Time"
            else:
                x_data = np.arange(len(wse_series))
                x_label = "Timestep"
        else:
            x_data = np.arange(len(wse_series))
            x_label = "Timestep"

        # Find peak
        valid_series = wse_series[np.isfinite(wse_series)]
        if len(valid_series) == 0:
            print("ERROR: No valid WSE data")
            return False

        peak_val = np.nanmax(wse_series)
        peak_idx = np.nanargmax(wse_series)

        # Create the plot
        fig, ax = plt.subplots(figsize=(12, 6))

        ax.plot(x_data[:len(wse_series)], wse_series, 'b-', linewidth=1.5, label='Water Surface Elevation')
        ax.plot(x_data[peak_idx], peak_val, 'r^', markersize=12, label=f'Peak WSE: {peak_val:.2f}')

        ax.set_xlabel(x_label, fontsize=12)
        ax.set_ylabel('Water Surface Elevation', fontsize=12)
        ax.set_title(f'Flood Hydrograph - {location_name}\n{subtitle}', fontsize=14)
        ax.legend(fontsize=11)
        ax.grid(True, alpha=0.3)

        if isinstance(x_data[0], datetime) if isinstance(x_data, list) else False:
            fig.autofmt_xdate()

        plt.tight_layout()

        # Save or show
        if output_png:
            fig.savefig(output_png, dpi=150, bbox_inches='tight')
            print(f"Plot saved to: {output_png}")
        else:
            output_png = os.path.join(os.path.dirname(hdf_path), "flood_hydrograph.png")
            fig.savefig(output_png, dpi=150, bbox_inches='tight')
            print(f"Plot saved to: {output_png}")

        plt.show()

        print(f"\n=== Hydrograph Summary ===")
        print(f"Peak WSE:        {peak_val:.3f}")
        print(f"Peak timestep:   {peak_idx}")
        print(f"Min WSE:         {np.nanmin(wse_series):.3f}")
        print(f"Mean WSE:        {np.nanmean(wse_series[np.isfinite(wse_series)]):.3f}")
        print(f"Total timesteps: {len(wse_series)}")

    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 plot_flood_hydrograph.py <plan_hdf_file> [output_png]")
        print("Example: python3 plot_flood_hydrograph.py Muncie.p04.hdf flood_hydrograph.png")
        sys.exit(1)

    hdf_path = sys.argv[1]
    output_png = sys.argv[2] if len(sys.argv) > 2 else None

    success = plot_flood_hydrograph(hdf_path, output_png)
    sys.exit(0 if success else 1)
