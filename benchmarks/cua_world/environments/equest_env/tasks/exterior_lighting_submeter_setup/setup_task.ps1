# Setup script for exterior_lighting_submeter_setup task.
# Imports the 4StoreyBuilding BDL model into eQUEST.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_exterior_lighting_submeter_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {