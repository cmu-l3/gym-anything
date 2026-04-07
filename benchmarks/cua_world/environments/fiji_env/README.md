# Fiji Environment

This environment provides Fiji (Fiji Is Just ImageJ), a powerful distribution of ImageJ for scientific image analysis, particularly in biological and medical imaging.

## Overview

Fiji is an image processing package bundling ImageJ with a large collection of plugins to facilitate scientific image analysis. It is particularly useful for:

- Microscopy image analysis
- Biological image processing
- Cell counting and particle analysis
- 3D image stack processing
- Color deconvolution for histology
- Fluorescence image analysis

## Environment Details

- **Base Image**: Ubuntu GNOME with systemd (high resolution)
- **Application**: Fiji (latest version with JDK)
- **Resources**: 4 CPU cores, 6GB RAM
- **Resolution**: 1920x1080
- **Network**: Enabled (for downloading samples and updates)

## Installation

The environment automatically:

1. Installs Java 17 JDK (required for Fiji)
2. Downloads and installs Fiji from the official source
3. Installs image processing libraries (scikit-image, Pillow, NumPy, SciPy)
4. Downloads real microscopy sample images from:
   - Broad Bioimage Benchmark Collection (BBBC005)
   - Cell Image Library
   - Fiji built-in samples

## Sample Data

The environment includes **real microscopy data** from public repositories:

- **BBBC005**: Synthetic cell images with ground truth for validation
  - Source: Broad Bioimage Benchmark Collection
  - Type: Simulated fluorescence microscopy
  - Use case: Cell segmentation and counting

- **Cell Image Library samples**: Real fluorescence microscopy images
  - Source: https://www.cellimagelibrary.org/
  - Type: Biological cell imaging

- **Fiji built-in samples**: Including blobs, T1 Head CT scan, HeLa cells
  - Accessible via File > Open Samples menu

All sample images are stored in `~/Fiji_Data/raw/`

## Tasks

### 1. Z-Stack Projection (Easy)

**Task ID**: `z_stack_projection@1`

Create a maximum intensity projection from a 3D CT scan stack.

**Skills tested**:
- Opening sample images
- Understanding Z-stacks
- Creating projections
- Adjusting brightness/contrast
- Saving results
- Measuring image statistics

**Expected outputs**:
- Maximum intensity projection image (PNG)
- Measurement statistics (CSV)

### 2. Color Deconvolution (Medium)

**Task ID**: `color_deconvolution@1`

Separate multiple stains in a histology image using Fiji's Color Deconvolution plugin.

**Skills tested**:
- Working with color images
- Understanding histology staining
- Using specialized Fiji plugins
- Separating color channels
- Saving individual channels
- Analyzing separated components

**Expected outputs**:
- Separated color channel 1 (PNG)
- Separated color channel 2 (PNG)
- Channel 1 statistics (CSV)

## Usage

### Starting the environment

```python
from gym_anything.api import from_config

# Start environment with a specific task
env = from_config("examples/fiji_env", task_id="z_stack_projection")
obs = env.reset(seed=42)
```

### File Locations

- **Fiji Installation**: `/opt/fiji/`
- **Fiji Executable**: `/usr/local/bin/fiji`
- **User Data**: `/home/ga/Fiji_Data/`
  - `raw/`: Input images and samples
  - `processed/`: Intermediate processing results
  - `results/`: Final outputs
  - `measurements/`: Analysis results
- **Sample Images**: `/opt/fiji_samples/`

### Launching Fiji

Multiple ways to launch:

```bash
# From terminal
fiji

# Using launch script (optimized settings)
~/launch_fiji.sh

# Desktop shortcut (available on desktop)
```

## Key Features

1. **Real Data**: All sample images are from real microscopy datasets or official Fiji samples
2. **Pre-configured**: First-run dialogs disabled, preferences set
3. **Memory Optimized**: Java heap size set to 4GB for large images
4. **Utilities**: Image info script (`fiji-image-info`) for inspecting images

## Fiji Capabilities

Fiji includes powerful plugins for:

- **Segmentation**: Thresholding, watershed, active contours
- **Analysis**: Particle analysis, colocalization, tracking
- **Filters**: Gaussian blur, median, unsharp mask
- **Stacks**: Z-projection, reslicing, montages
- **Color**: Deconvolution, channel splitting, merging
- **3D**: Volume rendering, surface reconstruction
- **Machine Learning**: Trainable Weka Segmentation

## References

- **Fiji Website**: https://fiji.sc/
- **ImageJ Documentation**: https://imagej.net/
- **Broad Bioimage Benchmark Collection**: https://bbbc.broadinstitute.org/
- **Public Datasets**: https://imagej.net/plugins/public-data-sets

## License

Fiji is distributed under the GNU General Public License v3.0.

## Sources

This environment uses real microscopy data from:

1. [Broad Bioimage Benchmark Collection](https://bbbc.broadinstitute.org/) - BBBC005 synthetic cell images
2. [Cell Image Library](https://www.cellimagelibrary.org/) - Real biological cell images
3. [Fiji Built-in Samples](https://imagej.net/software/fiji/) - Official sample images including CT scans and fluorescence microscopy

All data sources are publicly available and commonly used for testing and validation in the scientific imaging community.
