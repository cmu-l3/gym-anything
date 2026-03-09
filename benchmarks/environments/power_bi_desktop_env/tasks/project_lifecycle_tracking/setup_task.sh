#!/bin/bash
set -e
echo "=== Setting up Project Lifecycle Tracking Task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Generate Real Data (Python)
# We use python3 to generate a realistic CSV file
cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
import random

stages = ["Planning", "Foundation", "Framing", "Systems", "Finishing", "Complete"]
managers = ["J. Smith", "A. Davis", "M. Garcia", "R. Wilson"]

data = []
for i in range(1, 51):
    stage = random.choice(stages)
    # Budget between 50k and 500k, rounded to 1000
    budget = round(random.uniform(50000, 500000), -3)
    
    # Cost variance logic
    if stage == "Complete":
        # Complete projects are usually close to budget (0.9 to 1.1)
        variance = random.uniform(0.9, 1.1)
    elif stage == "Planning":
        # Planning has low cost incurred
        variance = random.uniform(0.0, 0.1)
    else:
        # In progress projects vary
        variance = random.uniform(0.3, 0.95)
    
    actual_cost = round(budget * variance, 2)
    
    data.append([
        f"Proj-{1000+i}",
        f"Site {1000+i} - {random.choice(['Tower', 'Plaza', 'Complex', 'Hub'])}",
        stage,
        int(budget),
        actual_cost,
        random.choice(managers)
    ])

df = pd.DataFrame(data, columns=["Project_ID", "Project_Name", "Stage", "Budget", "Actual_Cost", "Manager"])
output_path = "C:\\Users\\Docker\\Desktop\\construction_projects.csv"
# Windows path adjustment for WSL/Linux environment if needed, but here we write to where PBI can see it
# Assuming mapped drives or shared folder. In this env, C: is accessible via specific mount or we write to linux path that maps to Desktop.
# The environment description says "C:\Users\Docker\Desktop" is standard.
# We will write to the standard linux path for the Desktop in this container.
linux_path = "/home/ga/Desktop/construction_projects.csv"
# Try standard location if /home/ga/Desktop doesn't exist (depends on env)
if not os.path.exists("/home/ga/Desktop"):
    os.makedirs("/home/ga/Desktop", exist_ok=True)
    
df.to_csv(linux_path, index=False)
print(f"Data generated at {linux_path}")
EOF

# Install pandas if needed (usually present in data science envs, but minimal python might need it)
# pip install pandas > /dev/null 2>&1 || true

python3 /tmp/generate_data.py

# 3. Clean up previous run artifacts
rm -f "/home/ga/Desktop/Construction_Status.pbix" 2>/dev/null || true

# 4. Start Power BI Desktop (Optional: Start empty to save load time)
# Using the alias or path from environment
if ! pgrep -f "PBIDesktop" > /dev/null; then
    echo "Starting Power BI Desktop..."
    # This assumes the environment has a way to launch PBI. 
    # If not, the agent will launch it. 
    # We'll leave it closed to let the agent start fresh, 
    # or start it if we want to speed up. 
    # Let's ensure it's NOT running to force a clean state.
    pkill -f "PBIDesktop" || true
fi

# 5. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="