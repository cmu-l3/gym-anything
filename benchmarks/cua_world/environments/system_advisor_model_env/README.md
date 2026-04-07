# NREL System Advisor Model (SAM) Environment

## Overview

This environment provides the NREL System Advisor Model (SAM) for renewable energy techno-economic analysis within the gym_anything framework. SAM is a free desktop application used by project managers, engineers, policy analysts, and researchers to investigate the technical, economic, and financial feasibility of renewable power generation projects.

## Software Information

- **Application**: NREL System Advisor Model (SAM)
- **Version**: 2025.4.16 Revision 1
- **Developer**: National Renewable Energy Laboratory (NREL)
- **License**: BSD-3-Clause
- **Official Website**: https://sam.nrel.gov/
- **Documentation**: https://samrepo.nrelcloud.org/help/index.html

## Supported Technologies

SAM can model various renewable energy systems:

### Power Generation
- **Photovoltaic Systems**: Residential rooftop to large utility-scale systems
- **Concentrating Solar Power (CSP)**: Parabolic trough, power tower, linear Fresnel systems
- **Wind Power**: Individual turbines to large wind farms
- **Geothermal**: Geothermal power systems
- **Biomass**: Biomass power generation

### Energy Storage
- **Battery Systems**: Lithium-ion, lead-acid, flow batteries
- **Applications**: Front-of-meter and behind-the-meter storage

### Industrial Applications
- **Process Heat**: Industrial process heat from solar thermal systems

### Financial Analysis
- **Performance Modeling**: Hourly system performance calculations
- **Economic Analysis**: Levelized cost of energy (LCOE), net present value (NPV), internal rate of return (IRR)
- **Financial Modeling**: Project cash flow, payback period, revenue projections
- **Incentive Analysis**: Tax credits, rebates, and incentive programs

## Environment Configuration

### Resources
- **CPU**: 4 cores
- **Memory**: 8 GB RAM
- **GPU**: Not required
- **Network**: Required for downloading weather data and software components
- **Resolution**: 1920x1080 (highres)

### Base Image
- Ubuntu 22.04 with GNOME desktop
- Systemd enabled for service management
- Preset: `ubuntu-gnome-systemd_highres`

### User Account
- **Username**: ga
- **Password**: password123
- **Permissions**: Sudo access (no password required)
- **Home Directory**: `/home/ga`
- **SAM Projects**: `/home/ga/Documents/SAM_Projects`
- **SAM Config**: `/home/ga/.SAM`

## Installation Details

SAM is installed via the official Linux installer (`.run` file) to `/opt/SAM`. The installation includes:

1. **SAM Application**: Main GUI application for project creation and analysis
2. **SSC Library**: System Simulation Core for performance calculations
3. **Weather Data**: Access to NSRDB and other weather databases
4. **Component Libraries**: Modules, inverters, batteries, and other equipment databases
5. **Financial Models**: Templates for various project financing structures

### Key Directories
- Application: `/opt/SAM`
- Binary: `/opt/SAM/sam`
- Symlink: `/usr/local/bin/sam`
- User Config: `/home/ga/.SAM`
- Projects: `/home/ga/Documents/SAM_Projects`

## Tasks

### create_residential_pv_system

**Difficulty**: Medium

**Description**: Create a new residential photovoltaic (PV) system project in SAM with specific configuration parameters including location, system size, module type, tilt, and azimuth.

**Objectives**:
1. Create project using 'Residential PV' template
2. Set location to Phoenix, Arizona, USA
3. Configure DC system size: 5.0 kW
4. Select standard premium efficiency monocrystalline module
5. Set array type to Fixed (roof mount)
6. Configure tilt: 20 degrees
7. Set azimuth: 180 degrees (South-facing)
8. Save project as 'Phoenix_Residential_5kW.sam'

**Verification Criteria**:
- Project file exists at `/home/ga/Documents/SAM_Projects/Phoenix_Residential_5kW.sam`
- File was created/modified during task execution
- File size > 5 KB (typical SAM project size)
- Location information contains "Phoenix"
- DC system size between 4.5-5.5 kW
- Tilt angle between 15-25 degrees
- Azimuth between 175-185 degrees

**Learning Outcomes**:
- Understanding SAM project structure and templates
- Configuring geographic location and weather data
- Setting up basic PV system parameters
- Saving and managing SAM project files

## File Formats

### SAM Project Files (.sam)
SAM project files use JSON format containing:
- System configuration parameters
- Component selections from libraries
- Financial model settings
- Weather data references
- Simulation results (if calculated)

### Key Configuration Fields
- `location`: Geographic location string
- `system_capacity`/`system_size`: DC system size in kW
- `tilt`/`array_tilt`: Array tilt angle in degrees
- `azimuth`/`array_azimuth`: Array azimuth in degrees (180 = South)
- Module, inverter, and battery specifications
- Financial parameters and incentives

## Verification Approach

### Two-Part Pattern
1. **Export Script** (`export_result.sh`): Runs inside VM
   - Counts SAM project files
   - Checks for expected file existence
   - Parses SAM JSON project file for configuration values
   - Verifies file modification timestamps
   - Exports data to `/tmp/task_result.json`

2. **Verifier** (`verifier.py`): Runs on host
   - Uses `copy_from_env()` to retrieve result JSON
   - Validates multiple criteria:
     - File existence (20 points)
     - File modification during task (20 points)
     - File size reasonable (10 points)
     - Location matches (15 points)
     - DC size in range (15 points)
     - Tilt angle in range (10 points)
     - Azimuth in range (10 points)
   - Requires ≥75% score and key criteria (file exists + modified) to pass

## Known Considerations

### SAM Application Behavior
- First launch may show startup dialogs - handled in setup script with Escape key
- SAM projects are JSON-based and can be parsed programmatically
- Configuration dialogs vary by project type (Residential, Commercial, Utility)
- Weather data is automatically downloaded when location is selected

### File Structure
- SAM project files contain comprehensive configuration in JSON format
- File size typically ranges from 5-50 KB depending on complexity
- Projects reference component libraries installed with SAM

### Common Field Names
SAM uses various field names depending on project type:
- System size: `system_capacity`, `system_size`, `dc_size`
- Tilt: `tilt`, `array_tilt`
- Azimuth: `azimuth`, `array_azimuth`

Verification scripts handle multiple possible field names for robustness.

## References

### Official Resources
- [SAM Website](https://sam.nrel.gov/)
- [SAM Documentation](https://samrepo.nrelcloud.org/help/index.html)
- [SAM GitHub Repository](https://github.com/NREL/SAM)
- [SAM Forum](https://sam.nrel.gov/forum.html)

### Related Technologies
- **NSRDB**: National Solar Radiation Database for weather data
- **SSC**: System Simulation Core library
- **PVWatts**: Online PV calculator (simplified version of SAM)

### Learning Resources
- [SAM Tutorial Videos](https://sam.nrel.gov/videos.html)
- [SAM Webinars](https://sam.nrel.gov/support/sam-webinars.html)
- [Sample Projects](https://sam.nrel.gov/support/sample-files.html)

## Future Task Ideas

Additional tasks that could be implemented:

1. **run_annual_simulation**: Execute annual simulation and verify energy production results
2. **compare_financing_options**: Create and compare multiple financing scenarios
3. **sensitivity_analysis**: Perform parametric sensitivity analysis on key variables
4. **battery_storage_system**: Add battery storage to existing PV system
5. **commercial_pv_project**: Create commercial-scale PV project with different financial model
6. **wind_farm_project**: Model wind farm with multiple turbines
7. **csp_power_tower**: Configure concentrating solar power tower system
8. **export_hourly_results**: Run simulation and export hourly performance data
9. **location_comparison**: Compare same system in multiple locations
10. **module_comparison**: Compare performance with different module technologies

## Development Notes

### Environment Setup
- SAM installer downloaded from NREL beta releases or main download page
- Installation path: `/opt/SAM`
- First launch handled automatically in `setup_sam.sh`
- Window maximization improves agent interaction

### Verification Strategy
- Multi-signal verification prevents gaming
- File modification timestamps distinguish new work from pre-existing files
- JSON parsing extracts actual configuration values
- Fallback to grep if jq unavailable
- Multiple possible field names handled for robustness

### Testing Workflow
1. Start environment: `env.reset()`
2. Verify SAM launches and is visible
3. Interact using `ask_cua.py` for VLM guidance + xdotool for actions
4. Complete task objectives
5. Verify with `env.verify()`
6. Check evidence in `evidence_docs/` folder

## Evidence Documentation

The `evidence_docs/` folder should contain:
- Screenshots of SAM running with project open
- Logs from installation and setup scripts
- Sample SAM project files
- Verification results showing successful task completion

This provides proof that the environment was tested with real SAM installation and actual tasks were completed interactively.
