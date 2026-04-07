###############################################################################
# setup_task.ps1 — pre_task hook for survey_data_quality_control
# Downloads 150 real USGS NED 10m points for Boulder County, CO,
# injects 6 obvious outliers (elevation spikes), writes QC protocol.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_survey_qc.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up survey_data_quality_control task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Remove pre-existing output files ──
    Write-Host "[1/6] Cleaning up stale output files..."
    Remove-Item "C:\Users\Docker\Desktop\BoulderQC\cleaned_survey.csv" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\Desktop\BoulderQC\QC_Report.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\survey_data_quality_control_result.json" -Force -ErrorAction SilentlyContinue

    # ── 2. Record task start timestamp (AFTER cleanup) ──
    Write-Host "[2/6] Recording task start timestamp..."
    (Get-Date).ToString("o") | Set-Content -Path "C:\Users\Docker\survey_qc_start.txt" -Encoding utf8

    # ── 3. Infrastructure ──
    Write-Host "[3/6] Starting infrastructure..."
    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers
    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    $projDir = "C:\Users\Docker\Desktop\BoulderQC"
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    $pyPath = "C:\Users\Docker\download_boulder_survey.py"
    @'
import json, math, time, sys, urllib.request

def latlon_to_utm13n(lat, lon):
    a = 6378137.0; f = 1/298.257223563; b = a*(1-f); e2 = 1-(b/a)**2
    k0 = 0.9996; lr = math.radians(lat); nr = math.radians(lon); l0 = math.radians(-105)
    N = a / math.sqrt(1 - e2*math.sin(lr)**2)
    T = math.tan(lr)**2; C = e2/(1-e2)*math.cos(lr)**2; A = math.cos(lr)*(nr-l0)
    M = a*((1-e2/4-3*e2**2/64-5*e2**3/256)*lr
           -(3*e2/8+3*e2**2/32+45*e2**3/1024)*math.sin(2*lr)
           +(15*e2**2/256+45*e2**3/1024)*math.sin(4*lr)
           -(35*e2**3/3072)*math.sin(6*lr))
    E = k0*N*(A+(1-T+C)*A**3/6+(5-18*T+T**2+72*C-58*e2/(1-e2))*A**5/120)+500000
    Nv = k0*(M+N*math.tan(lr)*(A**2/2+(5-T+9*C+4*C**2)*A**4/24
             +(61-58*T+T**2+600*C-330*e2/(1-e2))*A**6/720))
    return round(E, 3), round(Nv, 3)

# Boulder County, CO — foothills west of Boulder city
# 150 points in 1.5 batches (100 + 50)
# Grid 1: 40.000-40.009N, 105.280-105.289W (100 pts)
grid1 = [(40.000+i*0.001, -105.280-j*0.001) for i in range(10) for j in range(10)]
# Grid 2: 40.010-40.014N, 105.290-105.299W (50 pts)
grid2 = [(40.010+i*0.001, -105.290-j*0.001) for i in range(5) for j in range(10)]

clean_points = []
pt_num = 1

for grid_idx, grid in enumerate([grid1, grid2], 1):
    locs = "|".join(f"{lat},{lon}" for lat, lon in grid)
    url = f"https://api.opentopodata.org/v1/ned10m?locations={locs}"
    print(f"Fetching grid {grid_idx}/2 ({len(grid)} pts)...", flush=True)
    success = False
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TopoCal-Gym/1.0"})
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = json.loads(resp.read())
            if data.get("status") == "OK":
                for r, (lat, lon) in zip(data["results"], grid):
                    elev = r.get("elevation")
                    if elev is None or float(elev) <= 0:
                        elev = 1700.0 + (lat-40.0)*4000 + abs(lon+105.28)*2000 + pt_num*0.4
                    E, Nv = latlon_to_utm13n(lat, lon)
                    clean_points.append([pt_num, E, Nv, round(float(elev), 3), "TOPO"])
                    pt_num += 1
                success = True
                break
        except Exception as exc:
            print(f"  Attempt {attempt+1} failed: {exc}", flush=True)
            time.sleep(2)
    if not success:
        print(f"  WARNING: Synthetic elevations for grid {grid_idx}", flush=True)
        for lat, lon in grid:
            E, Nv = latlon_to_utm13n(lat, lon)
            elev = 1700.0 + (lat-40.0)*3500 + abs(lon+105.28)*1800 + pt_num*0.5
            clean_points.append([pt_num, E, Nv, round(elev, 3), "TOPO"])
            pt_num += 1
    time.sleep(1.2)

# Compute mean elevation of clean data
elevs = [p[3] for p in clean_points if p[3] > 100]
mean_e = sum(elevs)/len(elevs) if elevs else 1800.0
print(f"Clean points: {len(clean_points)}  mean_elev={mean_e:.1f}m", flush=True)

# Inject 6 outlier points at fixed point numbers 51-56
# These will be interleaved: replace the existing points at positions 50-55
# with points that have egregious elevation errors.
outlier_specs = [
    # (pt_num, easting_offset, northing_offset, elevation_error)
    (51, 0.0,   0.0,  +350.0),  # spike up by 350m
    (52, 10.0,  5.0,  +420.0),  # spike up by 420m
    (53, -5.0,  15.0, -380.0),  # spike down by 380m
    (54, 20.0, -10.0, +290.0),  # spike up by 290m
    (55, -15.0,  0.0, -310.0),  # spike down by 310m
    (56, 5.0,   20.0, +470.0),  # spike up by 470m
]
# Find the base point near each outlier index
outlier_ids = set()
for pt_idx_1based, e_off, n_off, elev_err in outlier_specs:
    idx = pt_idx_1based - 1  # 0-based
    if 0 <= idx < len(clean_points):
        base = clean_points[idx]
        new_elev = round(base[3] + elev_err, 3)
        clean_points[idx] = [base[0], base[1]+e_off, base[2]+n_off, new_elev, "TOPO"]
        outlier_ids.add(base[0])

# All 156 points = 150 clean + 6 outlier replacements (outliers are the 6 replaced points)
all_points = clean_points  # 150 total (100 + 50 + 6 outliers injected in-place)

out_csv = r"C:\Users\Docker\Desktop\BoulderQC\raw_survey.csv"
with open(out_csv, "w", encoding="utf-8") as f:
    f.write("PointNumber,Easting,Northing,Elevation,Code\n")
    for p in all_points:
        f.write(f"{p[0]},{p[1]},{p[2]},{p[3]},{p[4]}\n")
print(f"Wrote {len(all_points)} points (incl. 6 outliers) to {out_csv}", flush=True)

# Write the QC protocol
out_qc = r"C:\Users\Docker\Desktop\BoulderQC\QC_Protocol.txt"
with open(out_qc, "w", encoding="utf-8") as f:
    f.write("SURVEY DATA QUALITY CONTROL PROTOCOL\n")
    f.write("="*60 + "\n\n")
    f.write("Client: Boulder County Engineering Department\n")
    f.write("Project: Open Space Topographic Survey\n")
    f.write("Location: Boulder County, Colorado\n")
    f.write("Coordinate System: UTM Zone 13N (EPSG:26913), meters\n")
    f.write(f"Input File: raw_survey.csv ({len(all_points)} field points)\n\n")
    f.write("QC CRITERIA\n")
    f.write("-"*40 + "\n")
    f.write("1. Elevation Spike Detection:\n")
    f.write("   Any point whose elevation differs by more than 50 metres\n")
    f.write("   from the mean of its neighbouring points (within 200m radius)\n")
    f.write("   is flagged as an outlier and must be removed.\n\n")
    f.write(f"2. Expected elevation range for this area: {mean_e-80:.0f}m to {mean_e+80:.0f}m\n")
    f.write("   Points outside this range should be visually inspected and\n")
    f.write("   removed if not physically plausible.\n\n")
    f.write("3. Duplicate point check:\n")
    f.write("   Remove any duplicate point numbers.\n\n")
    f.write("SURVEY DATA FORMAT\n")
    f.write("-"*40 + "\n")
    f.write("File: raw_survey.csv\n")
    f.write("Encoding: UTF-8, comma-separated\n")
    f.write("Columns: PointNumber, Easting (m), Northing (m), Elevation (m), Code\n\n")
    f.write("REQUIRED DELIVERABLES\n")
    f.write("-"*40 + "\n")
    f.write("1. Cleaned survey data:\n")
    f.write("   File: C:\\Users\\Docker\\Desktop\\BoulderQC\\cleaned_survey.csv\n")
    f.write("   (same CSV format, outlier points removed)\n\n")
    f.write("2. QC Report:\n")
    f.write("   File: C:\\Users\\Docker\\Desktop\\BoulderQC\\QC_Report.txt\n")
    f.write("   Must include: original count, removed count, removed point IDs,\n")
    f.write("   their coordinates and elevations, reason for removal.\n")

print("Setup complete.", flush=True)
'@ | Set-Content -Path $pyPath -Encoding utf8

    Write-Host "[4/6] Running data download and injection script..."
    python.exe "$pyPath"
    if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: Python exited $LASTEXITCODE" }

    Write-Host "[5/6] Launching TopoCal..."
    $launched = Start-TopoCalInteractive -WaitSeconds 12
    if (-not $launched) { Write-Host "WARNING: TopoCal not yet visible" }
    Start-Sleep -Seconds 2
    Set-TopoCalForeground | Out-Null

    Write-Host "[6/6] Cleaning up edge killer..."
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== Setup Complete ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
