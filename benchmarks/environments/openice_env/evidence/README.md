# OpenICE Environment Documentation

## Overview

OpenICE (Open-source Integrated Clinical Environment) is a medical device interoperability platform developed by the MD PnP (Medical Device "Plug-and-Play") program at Massachusetts General Hospital. It enables medical devices to communicate and share data in clinical settings.

**GitHub Repository**: [mdpnp/mdpnp](https://github.com/mdpnp/mdpnp)

## Environment Details

- **Environment ID**: `openice_env@0.1`
- **Base Image**: `ubuntu-gnome-systemd_highres`
- **Resources**: 4 CPU cores, 8GB RAM, network enabled
- **Application**: OpenICE Demo Application (Supervisor mode)

## OpenICE Features

1. **Supervisor Mode**: Hosts clinical applications and displays connected devices
2. **Device Adapters**: Creates virtual/simulated medical devices
3. **Clinical Applications**: Demo apps for vital signs monitoring, patient ID, etc.
4. **Real-time Data**: Displays waveforms and numeric vital signs

## Tasks

### 1. create_simulated_device
- **Difficulty**: Easy
- **Description**: Create a simulated Multiparameter Monitor device adapter
- **Steps**: Click "Create ICE Device Adapter" → Select "Simulated" → Select "Multiparameter Monitor" → Click "Start"

### 2. view_device_vitals
- **Difficulty**: Medium
- **Description**: Create a device and view its vital signs data
- **Steps**: Create a device → Click on device icon → Observe vital signs waveforms and values

### 3. launch_clinical_app
- **Difficulty**: Easy
- **Description**: Launch a clinical demonstration application
- **Steps**: Click on an app icon (Vital Signs, Patient ID, etc.) → Observe the app → Exit

## Installation Notes

### Requirements
- Java 17 (OpenJDK)
- Gradle build system
- JavaFX dependencies

### Build Time
OpenICE requires a Gradle build on first run, which can take **5-10 minutes** depending on network speed and system resources. This build downloads dependencies and compiles the application.

### Known Issues

1. **Long Build Time**: First run takes significant time due to Gradle build
2. **Memory Requirements**: Gradle build requires at least 2GB heap space
3. **Network Dependency**: Initial build requires internet access for dependency downloads

## Verification Strategy

Verification uses:
1. **Window detection**: Check for OpenICE/device windows using wmctrl
2. **Process detection**: Check for Java processes running demo-apps
3. **Log analysis**: Check OpenICE logs for device/app activity
4. **Timestamp tracking**: Record task start/end times to prevent gaming

## Sources

- [OpenICE Official Website](https://www.openice.info/)
- [OpenICE User Introduction](https://www.openice.info/docs/1_overview.html)
- [OpenICE Supervisor Overview](https://www.openice.info/docs/2_supervisor.html)
- [Demo Applications Manual](https://www.openice.info/docs/3_apps.html)
- [MD PnP GitHub](https://github.com/mdpnp/mdpnp)
