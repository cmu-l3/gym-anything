# Export script for commercial_truck_route_plan
# Closes BaseCamp, parses exported GPX, writes result JSON

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting commercial_truck_route_plan Result ==="

$resultPath  = "C:\Users\Docker\commercial_truck_route_plan_result.json"
$gpxPath     = "C:\Users\Docker\Desktop\BostonFallRiver_FreightRoute.gpx"
$startTsFile = "C:\GarminTools\commercial_truck_route_plan_start_ts.txt"

# Read task start timestamp
$taskStart = 0
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}
Write-Host "Task start timestamp: $taskStart"

# Close BaseCamp gracefully so it flushes any in-progress edits
Close-BaseCamp
Start-Sleep -Seconds 3

# Check GPX file
$gpxExists = Test-Path $gpxPath
$gpxIsNew  = $false
if ($gpxExists) {
    $fi       = Get-Item $gpxPath
    $gpxMtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
    $gpxIsNew = ($gpxMtime -ge $taskStart)
    Write-Host "GPX found: $gpxPath (mtime=$gpxMtime, task_start=$taskStart, is_new=$gpxIsNew)"
} else {
    Write-Host "GPX NOT found: $gpxPath"
}

# Write Python parser to TEMP and run it
$pyScript = "$env:TEMP\parse_gpx_truck.py"
@"
import sys, json, xml.etree.ElementTree as ET

task_start = int(sys.argv[1])
gpx_path   = sys.argv[2]
result_path = sys.argv[3]
gpx_exists = False
gpx_is_new = False

try:
    import os
    if os.path.exists(gpx_path):
        gpx_exists = True
        mtime = int(os.path.getmtime(gpx_path))
        gpx_is_new = (mtime >= task_start)
except Exception:
    pass

waypoints   = []
routes      = []
track_count = 0

if gpx_exists:
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        ns   = root.tag.split('}')[0][1:] if '}' in root.tag else ''
        def tag(n): return ('{%s}%s' % (ns, n)) if ns else n
        def txt(el, c):
            ch = el.find(tag(c))
            return ch.text.strip() if ch is not None and ch.text else ''

        for wpt in root.findall(tag('wpt')):
            waypoints.append({
                'name': txt(wpt, 'name'),
                'sym':  txt(wpt, 'sym'),
                'cmt':  txt(wpt, 'cmt') or txt(wpt, 'desc'),
                'lat':  float(wpt.get('lat', 0)),
                'lon':  float(wpt.get('lon', 0)),
            })

        for rte in root.findall(tag('rte')):
            pts = [txt(rp, 'name') for rp in rte.findall(tag('rtept'))]
            routes.append({'name': txt(rte, 'name'), 'points': pts})

        track_count = len(root.findall(tag('trk')))
    except Exception as e:
        pass

result = {
    'gpx_exists':   gpx_exists,
    'gpx_is_new':   gpx_is_new,
    'task_start':   task_start,
    'waypoints':    waypoints,
    'routes':       routes,
    'track_count':  track_count,
}
with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
print('Parse complete. Waypoints=%d, Routes=%d' % (len(waypoints), len(routes)))
"@ | Out-File -FilePath $pyScript -Encoding UTF8 -Force

python3 $pyScript $taskStart $gpxPath $resultPath

if (Test-Path $resultPath) {
    Write-Host "Result JSON written: $resultPath"
} else {
    # Fallback: write minimal JSON so verifier gets a gate-fail (score=0)
    @{
        gpx_exists  = $gpxExists
        gpx_is_new  = $gpxIsNew
        task_start  = $taskStart
        waypoints   = @()
        routes      = @()
        track_count = 0
    } | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Fallback result JSON written (no Python parse)."
}

Write-Host "=== Export Complete: commercial_truck_route_plan ==="
