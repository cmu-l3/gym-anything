# Task: Automated Processing Pipeline

## Occupation
Remote Sensing Technician — establishing operational satellite monitoring workflows.

## Industry
Operational Earth Observation / Satellite Monitoring

## Scenario
A remote sensing technician must create a fully automated, non-interactive processing pipeline for satellite imagery. The agent must discover SNAP's command-line capabilities (GPT — Graph Processing Tool at /opt/snap/bin/gpt, or snappy Python API), write a processing graph or script, and execute it to produce output products — all without using the SNAP GUI.

## Data
- **Source**: Landsat multispectral imagery from github.com/opengeos/data
- **File**: landsat_multispectral.tif (4 bands: SWIR1, NIR, Red, Green)

## What Makes This Very Hard
- Agent must discover that SNAP has CLI tools (GPT) beyond the GUI
- Agent must write a valid GPT graph XML or snappy Python script
- Agent must figure out GPT graph XML syntax (operator nodes, sources, parameters)
- Agent must execute the pipeline from a terminal
- No SNAP GUI is launched — agent starts with just a terminal
- Fundamentally different skill set: scripting + automation rather than GUI interaction

## Verification (6 criteria, 100 pts, pass at 70)
1. Pipeline definition file exists (XML or script) (15 pts)
2. Graph/script has data read operation (15 pts)
3. Graph/script has processing operation (20 pts)
4. Graph/script has data write operation (10 pts)
5. Output product created after task start (20 pts)
6. Output product contains spectral index band (20 pts)
