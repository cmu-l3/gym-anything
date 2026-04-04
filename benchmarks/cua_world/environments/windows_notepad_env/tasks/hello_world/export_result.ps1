# Export results for verification
# Copies the result file to workspace for verification

$ResultDir = "C:\workspace\results"
New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null

# Copy hello.txt from Desktop to results if it exists
$HelloPath = "C:\Users\Docker\Desktop\hello.txt"
if (Test-Path $HelloPath) {
    Copy-Item $HelloPath "$ResultDir\result_hello.txt"
    Write-Host "Result exported successfully"
} else {
    Write-Host "No hello.txt found on Desktop"
}

# Also check common alternative locations
$DocsPath = "C:\Users\Docker\Documents\hello.txt"
if (Test-Path $DocsPath) {
    Copy-Item $DocsPath "$ResultDir\result_hello_docs.txt"
}
