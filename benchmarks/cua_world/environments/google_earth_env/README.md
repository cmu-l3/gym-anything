# Google Earth Pro Environment

A Gym-Anything environment for Google Earth Pro desktop application tasks including geographic navigation, measurement, placemark creation, and screenshot capture.

## Overview

Google Earth Pro is a free desktop application that provides satellite imagery, aerial photography, and GIS data. This environment enables agents to interact with Google Earth Pro through mouse and keyboard actions.

**Note:** Google Earth Pro has been completely free since January 2015.

## Tasks

| Task | Description |
|------|-------------|
| `navigate_to_location` | Navigate to the Eiffel Tower in Paris |
| `search_coordinates` | Search for specific latitude/longitude coordinates |
| `measure_distance` | Measure distance between two landmarks |
| `create_placemark` | Create and save a placemark at a location |
| `take_screenshot` | Capture screenshot of a geographic view |

## Environment Details

- **Base Image:** `ubuntu-gnome-systemd_highres`
- **Resolution:** 1920x1080
- **Network:** Required (for satellite imagery)
- **VNC Port:** 5954

## Usage

```bash
# Run a specific task
python loop.py --env google_earth_env --task navigate_to_location

# Run all tasks
python loop.py --env google_earth_env --task all
```

## Requirements

- Network connectivity for satellite imagery loading
- Sufficient memory (4GB recommended)
- Display server (X11)

## File Structure

```
google_earth_env/
├── env.json                    # Environment configuration
├── README.md                   # This file
├── scripts/
│   ├── install_google_earth.sh # Installation script (pre_start hook)
│   └── setup_google_earth.sh   # Setup script (post_start hook)
├── config/                     # Optional configuration files
├── tasks/
│   ├── verification_utils.py   # Shared verification utilities
│   ├── navigate_to_location/
│   ├── search_coordinates/
│   ├── measure_distance/
│   ├── create_placemark/
│   └── take_screenshot/
└── utils/                      # Optional utilities
```

## Verification

Tasks are verified through:
- Screenshot analysis for visual confirmation
- Google Earth state files in `~/.googleearth/`
- Window title/state detection via wmctrl/xdotool
