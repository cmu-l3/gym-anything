######################################################################
# export_result.ps1  -  post_task hook for sar_search_plan
# Closes BaseCamp, parses the exported GPX, writes result JSON
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_sar_export.log" -Append | Out-Null
Write-Host "=== Exporting sar_search_plan results ==="

. "C:\workspace\scripts\task_utils.ps1"
Close-BaseCamp
Start-Sleep -Seconds 3

# Read task start timestamp
$taskStart = 0
$tsFile = "C:\GarminTools\sar_search_plan_start_ts.txt"
if (Test-Path $tsFile) {
    $taskStart = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$gpxPath    = "C:\Users\Docker\Desktop\SAR_Middlesex_Fells_2024.gpx"
$resultPath = "C:\Users\Docker\sar_search_plan_result.json"

# Write Python parsing script to temp file
$pyScript = "$env:TEMP\parse_gpx_sar.py"
@'
import json, sys, os
import xml.etree.ElementTree as ET

task_start = int(sys.argv[1])
gpx_path   = sys.argv[2]
out_path   = sys.argv[3]

result = {
    "task_start":   task_start,
    "gpx_exists":   False,
    "gpx_mtime":    0,
    "gpx_is_new":   False,
    "waypoints":    [],
    "routes":       [],
    "tracks":       [],
    "parse_error":  "",
}

if os.path.exists(gpx_path):
    mtime = int(os.path.getmtime(gpx_path))
    result["gpx_exists"] = True
    result["gpx_mtime"]  = mtime
    result["gpx_is_new"] = (mtime >= task_start)
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        ns = root.tag.split("}")[0][1:] if "}" in root.tag else ""
        def tag(n): return "{%s}%s" % (ns, n) if ns else n
        def txt(el, c):
            ch = el.find(tag(c))
            return ch.text.strip() if ch is not None and ch.text else ""

        for wpt in root.findall(tag("wpt")):
            result["waypoints"].append({
                "name": txt(wpt, "name"),
                "lat":  float(wpt.get("lat", 0)),
                "lon":  float(wpt.get("lon", 0)),
                "sym":  txt(wpt, "sym"),
                "cmt":  txt(wpt, "cmt"),
                "desc": txt(wpt, "desc"),
            })

        for rte in root.findall(tag("rte")):
            pts = [txt(p, "name") for p in rte.findall(tag("rtept"))]
            result["routes"].append({"name": txt(rte, "name"), "points": pts})

        for trk in root.findall(tag("trk")):
            result["tracks"].append(txt(trk, "name"))

    except Exception as e:
        result["parse_error"] = str(e)

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
print("Export complete. GPX exists:", result["gpx_exists"])
'@ | Set-Content $pyScript -Encoding UTF8

python3 $pyScript $taskStart $gpxPath $resultPath 2>&1
Write-Host "Result written to: $resultPath"

Stop-Transcript | Out-Null
