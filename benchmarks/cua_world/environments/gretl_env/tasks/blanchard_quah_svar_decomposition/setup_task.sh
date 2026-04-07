#!/bin/bash
set -e
echo "=== Setting up Blanchard-Quah SVAR Decomposition Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# =====================================================================
# Clean up previous artifacts BEFORE recording timestamp
# =====================================================================
rm -rf /home/ga/Documents/gretl_output
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Record task start time (after cleanup so stale files can't cheat)
date +%s > /tmp/task_start_time.txt

# =====================================================================
# Ensure usa.gdt is available
# =====================================================================
USA_GDT="/home/ga/Documents/gretl_data/usa.gdt"
mkdir -p /home/ga/Documents/gretl_data

if [ ! -f "$USA_GDT" ]; then
    if [ -f "/opt/gretl_data/poe5/usa.gdt" ]; then
        cp "/opt/gretl_data/poe5/usa.gdt" "$USA_GDT"
    elif [ -f "/usr/share/gretl/data/poe5/usa.gdt" ]; then
        cp "/usr/share/gretl/data/poe5/usa.gdt" "$USA_GDT"
    else
        echo "Creating usa.gdt from embedded data..."
        cat > "$USA_GDT" << 'GRETLDATA'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gretldata SYSTEM "gretldata.dtd">
<gretldata name="usa" frequency="4" startobs="1984:1" endobs="2009:3" type="time-series">
<variables count="2">
<variable name="gdp" label="Real GDP, billions of chained 2005 dollars"/>
<variable name="inf" label="Inflation rate (quarterly % change in CPI, annualized)"/>
</variables>
<observations count="103" labels="false">
<obs>6386.9 4.6</obs> <obs>6497.5 4.1</obs> <obs>6568.1 3.7</obs> <obs>6622.7 3.5</obs>
<obs>6710.2 3.8</obs> <obs>6783.1 3.6</obs> <obs>6894.1 3.2</obs> <obs>6942.5 3.5</obs>
<obs>7019.0 1.9</obs> <obs>7048.8 1.4</obs> <obs>7097.3 1.8</obs> <obs>7133.0 2.1</obs>
<obs>7185.0 3.1</obs> <obs>7259.4 3.3</obs> <obs>7326.3 3.5</obs> <obs>7430.7 4.0</obs>
<obs>7469.7 2.6</obs> <obs>7568.2 3.2</obs> <obs>7617.2 3.7</obs> <obs>7710.0 4.0</obs>
<obs>7793.1 3.3</obs> <obs>7862.6 4.3</obs> <obs>7924.9 3.5</obs> <obs>7965.8 3.2</obs>
<obs>8062.0 4.2</obs> <obs>8127.3 3.8</obs> <obs>8160.0 4.1</obs> <obs>8090.5 5.5</obs>
<obs>8031.5 3.3</obs> <obs>8095.5 2.7</obs> <obs>8147.2 2.9</obs> <obs>8202.2 2.7</obs>
<obs>8292.0 1.7</obs> <obs>8371.3 2.9</obs> <obs>8449.2 2.7</obs> <obs>8536.8 2.8</obs>
<obs>8552.2 2.5</obs> <obs>8614.0 2.1</obs> <obs>8665.1 1.9</obs> <obs>8751.7 2.2</obs>
<obs>8816.0 1.9</obs> <obs>8903.3 2.5</obs> <obs>8966.3 2.8</obs> <obs>9086.0 2.2</obs>
<obs>9144.3 2.5</obs> <obs>9181.7 2.6</obs> <obs>9252.6 1.8</obs> <obs>9310.8 1.9</obs>
<obs>9384.4 2.4</obs> <obs>9536.8 1.9</obs> <obs>9638.5 2.2</obs> <obs>9706.7 1.8</obs>
<obs>9790.2 2.3</obs> <obs>9868.9 1.5</obs> <obs>9991.2 1.5</obs> <obs>10183.0 1.6</obs>
<obs>10291.5 1.7</obs> <obs>10368.6 2.3</obs> <obs>10486.2 2.4</obs> <obs>10660.1 2.9</obs>
<obs>10678.3 3.3</obs> <obs>10826.9 2.7</obs> <obs>10834.4 2.9</obs> <obs>10905.0 2.8</obs>
<obs>10875.0 3.7</obs> <obs>10926.3 3.9</obs> <obs>10899.0 2.6</obs> <obs>10940.7 0.9</obs>
<obs>11006.1 1.2</obs> <obs>11069.9 2.5</obs> <obs>11116.8 2.2</obs> <obs>11130.6 2.0</obs>
<obs>11174.1 3.5</obs> <obs>11312.8 1.9</obs> <obs>11518.3 1.9</obs> <obs>11632.9 1.6</obs>
<obs>11703.9 2.6</obs> <obs>11781.5 3.8</obs> <obs>11867.8 2.6</obs> <obs>11964.6 3.4</obs>
<obs>12093.8 3.0</obs> <obs>12166.3 4.1</obs> <obs>12239.5 2.5</obs> <obs>12274.6 4.7</obs>
<obs>12437.4 2.1</obs> <obs>12501.9 4.9</obs> <obs>12524.3 1.9</obs> <obs>12613.6 1.4</obs>
<obs>12638.4 4.0</obs> <obs>12726.7 3.5</obs> <obs>12882.3 2.6</obs> <obs>12933.1 3.9</obs>
<obs>12918.3 4.4</obs> <obs>12988.6 3.4</obs> <obs>13121.3 5.3</obs> <obs>13110.1 6.8</obs>
<obs>12938.5 2.1</obs> <obs>12760.3 -8.8</obs> <obs>12711.0 1.9</obs> <obs>12808.9 3.6</obs>
<obs>12938.5 2.1</obs> <obs>12760.3 -8.8</obs> <obs>12711.0 1.9</obs>
</observations>
</gretldata>
GRETLDATA
    fi
fi
chown ga:ga "$USA_GDT"

# =====================================================================
# Kill any existing gretl and launch fresh
# =====================================================================
pkill -f "gretl" 2>/dev/null || true
sleep 2

echo "Launching Gretl with usa.gdt..."
su - ga -c "DISPLAY=:1 setsid gretl '$USA_GDT' >/dev/null 2>&1 &"

# Wait for gretl window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "gretl"; then
        echo "Gretl window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "gretl" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "gretl" 2>/dev/null || true

# Dismiss any startup dialogs
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Blanchard-Quah SVAR task setup complete ==="
