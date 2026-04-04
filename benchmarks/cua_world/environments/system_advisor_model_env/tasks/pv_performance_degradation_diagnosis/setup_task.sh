#!/bin/bash
echo "=== Setting up pv_performance_degradation_diagnosis task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/LasVegas_Performance_Diagnosis.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs
rm -f /home/ga/*.py /home/ga/diag_*.py /home/ga/sam_*.py /home/ga/pv_diag_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time (BEFORE creating scenario data)
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Create the client system report (scenario scaffolding for the forensic diagnosis task).
# All values are grounded in real NREL PVWatts outputs for Las Vegas 25 kW systems and
# published NREL degradation/soiling research (Jordan & Kurtz 2012; Gostein et al. 2014).
# Ground truth: soiling=8%/yr (missed Year 4 cleaning), degradation=0.9%/yr (hot desert site).
cat > /home/ga/client_system_report.json << 'REPORT_EOF'
{
  "report_title": "PV System Performance Review - Las Vegas Commercial Rooftop",
  "client_id": "LV-2024-C847",
  "site": {
    "city": "Las Vegas",
    "state": "NV",
    "latitude": 36.17,
    "longitude": -115.14,
    "elevation_m": 648
  },
  "system_specifications": {
    "nameplate_capacity_kw_dc": 25.0,
    "module_technology": "Monocrystalline Silicon",
    "module_efficiency_pct": 20.0,
    "inverter_efficiency_pct": 96.5,
    "dc_ac_ratio": 1.20,
    "tilt_deg": 20,
    "azimuth_deg": 180,
    "installation_year": 2020,
    "commissioning_report_year1_expected_kwh": 42500
  },
  "observed_annual_production_kwh": {
    "year_1_2020_2021": 42180,
    "year_2_2021_2022": 41050,
    "year_3_2022_2023": 39420,
    "year_4_2023_2024": 35290
  },
  "performance_concern": "Year 4 production (35,290 kWh) is approximately 17% below expected Year 4 output. Standard 0.5%/yr degradation would only account for ~2% loss. Client requests root cause analysis.",
  "notes": "Site is a commercial rooftop near the Las Vegas Strip. Cleaning history: annual cleaning performed in Years 1-3. Year 4 cleaning was deferred due to budget constraints. Local dust events from desert windstorms recorded in spring 2024."
}
REPORT_EOF

chown ga:ga /home/ga/client_system_report.json

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="
