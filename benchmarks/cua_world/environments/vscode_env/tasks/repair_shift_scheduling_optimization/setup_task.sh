#!/bin/bash
set -e
echo "=== Setting up Shift Scheduling Optimization Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure pip dependencies (ortools, pandas)
su - ga -c "pip3 install ortools pandas --no-cache-dir"

WORKSPACE_DIR="/home/ga/workspace/nurse_scheduling"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# 1. Generate realistic data
cat > "$WORKSPACE_DIR/data/nurses.csv" << 'EOF'
nurse_id,type,name,vacation_days
0,FT,Alice,2;3
1,FT,Bob,5;6
2,FT,Charlie,10;11
3,FT,Diana,0;1
4,FT,Edward,13
5,FT,Fiona,7;8
6,FT,George,1;2
7,FT,Hannah,9;10
8,FT,Ian,4;5
9,FT,Julia,12;13
10,PT,Kevin,6
11,PT,Luna,3;4
12,PT,Mason,8;9
13,PT,Nora,0
14,PT,Oscar,11
EOF

cat > "$WORKSPACE_DIR/data/demand.csv" << 'EOF'
day,shift,demand
0,0,3
0,1,3
0,2,2
1,0,3
1,1,3
1,2,2
2,0,3
2,1,3
2,2,2
3,0,3
3,1,3
3,2,2
4,0,3
4,1,3
4,2,2
5,0,3
5,1,3
5,2,2
6,0,3
6,1,3
6,2,2
7,0,3
7,1,3
7,2,2
8,0,3
8,1,3
8,2,2
9,0,3
9,1,3
9,2,2
10,0,3
10,1,3
10,2,2
11,0,3
11,1,3
11,2,2
12,0,3
12,1,3
12,2,2
13,0,3
13,1,3
13,2,2
EOF

# 2. Write the rules document
cat > "$WORKSPACE_DIR/README_RULES.md" << 'EOF'
# Hospital Nursing Schedule Rules

Our unit has 15 nurses (10 Full-Time, 5 Part-Time) and operates 3 shifts per day (0: Morning, 1: Evening, 2: Night) over a 14-day period.

The scheduling script must enforce the following rules:

1. **Coverage (Hard Constraint):** We must meet or exceed the required number of nurses per shift, as defined in `demand.csv`.
2. **Turnaround Time (Hard Constraint):** If a nurse works a Night shift (Shift 2), they CANNOT work a Morning shift (Shift 0) the immediately following day.
3. **Consecutive Days (Hard Constraint):** The labor union strictly prohibits any nurse from working 6 consecutive days.
4. **Weekly Minimums (Hard Constraint):** Full-Time (FT) nurses must work a minimum of 4 shifts in any rolling 7-day window.
5. **Vacation Requests (Soft Constraint / Objective):** We try to honor vacation requests. For every shift a nurse is scheduled on one of their requested vacation days, we add a penalty of 100 to the objective function. The solver must MINIMIZE this penalty.
EOF

# 3. Create the buggy model script
cat > "$WORKSPACE_DIR/schedule_model.py" << 'EOF'
import pandas as pd
from ortools.sat.python import cp_model
import csv

def main():
    nurses_df = pd.read_csv('data/nurses.csv')
    demand_df = pd.read_csv('data/demand.csv')

    num_nurses = len(nurses_df)
    num_days = 14
    num_shifts = 3

    all_nurses = range(num_nurses)
    all_days = range(num_days)
    all_shifts = range(num_shifts)

    # Parse vacation requests
    vacation_requests = {n: [] for n in all_nurses}
    for i, row in nurses_df.iterrows():
        if pd.notna(row['vacation_days']):
            days_off = [int(d) for d in str(row['vacation_days']).split(';') if str(d).strip()]
            vacation_requests[i] = days_off

    ft_nurses = nurses_df.index[nurses_df['type'] == 'FT'].tolist()

    model = cp_model.CpModel()

    # Variables: shifts[(n, d, s)] is 1 if nurse n works shift s on day d
    shifts = {}
    for n in all_nurses:
        for d in all_days:
            for s in all_shifts:
                shifts[(n, d, s)] = model.NewBoolVar(f'shift_n{n}_d{d}_s{s}')

    # Default Rule: Each nurse works at most one shift per day
    for n in all_nurses:
        for d in all_days:
            model.Add(sum(shifts[(n, d, s)] for s in all_shifts) <= 1)

    # BUG 1: Coverage
    for d in all_days:
        for s in all_shifts:
            demand = int(demand_df[(demand_df['day'] == d) & (demand_df['shift'] == s)]['demand'].iloc[0])
            model.Add(sum(shifts[(n, d, s)] for n in all_nurses) <= demand)

    # BUG 2: Turnaround Time 
    for n in all_nurses:
        for d in all_days:
            # Shift 2 is Night, Shift 0 is Morning
            model.Add(shifts[(n, d, 2)] + shifts[(n, d, 0)] <= 1)

    # BUG 3: Consecutive Days 
    for n in all_nurses:
        for d in range(num_days - 5):
            model.Add(sum(shifts[(n, d+i, s)] for i in range(6) for s in all_shifts) <= 6)

    # BUG 4: Weekly Minimums
    for n in ft_nurses:
        for d in range(num_days - 6):
            model.Add(sum(shifts[(n, d+i, s)] for i in range(7) for s in all_shifts) >= 1)

    # BUG 5: Objective Function (Minimize vacation request violations)
    model.Minimize(0)

    # Solve
    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = 30.0
    status = solver.Solve(model)

    if status == cp_model.OPTIMAL or status == cp_model.FEASIBLE:
        print("Solution found! Saving to schedule.csv")
        with open('schedule.csv', 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Nurse', 'Day', 'Shift'])
            for d in all_days:
                for n in all_nurses:
                    for s in all_shifts:
                        if solver.Value(shifts[(n, d, s)]) == 1:
                            writer.writerow([n, d, s])
    else:
        print("No solution found!")

if __name__ == '__main__':
    main()
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# 4. Generate initial broken schedule so there is something to fix
su - ga -c "cd $WORKSPACE_DIR && python3 schedule_model.py > /dev/null 2>&1" || true

# Update start time again so the pre-generated schedule is technically older
sleep 2
date +%s > /tmp/task_start_time.txt

# 5. Launch VS Code
if ! pgrep -f "code.*--ms-enable-electron" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Maximize and Focus
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="