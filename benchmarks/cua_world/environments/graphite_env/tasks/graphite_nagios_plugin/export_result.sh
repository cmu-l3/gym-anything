#!/bin/bash
echo "=== Exporting graphite_nagios_plugin result ==="

# Execute the verifier tests locally inside the container to safely capture outputs
cat > /tmp/test_plugin.py << 'EOF'
import json, os, subprocess

script_path = "/home/ga/check_graphite_metric.py"

result = {
    "script_exists": os.path.isfile(script_path),
    "script_executable": os.access(script_path, os.X_OK),
    "tests": {}
}

if result["script_exists"]:
    # Define test parameters
    tests = {
        "ok": ["python3", script_path, "--target", "constantLine(50)", "--warning", "70", "--critical", "90"],
        "warning": ["python3", script_path, "--target", "constantLine(80)", "--warning", "70", "--critical", "90"],
        "critical": ["python3", script_path, "--target", "constantLine(95)", "--warning", "70", "--critical", "90"],
        "unknown": ["python3", script_path, "--target", "does.not.exist.metric", "--warning", "70", "--critical", "90"],
        "url_encode": ["python3", script_path, "--target", "scale(constantLine(50), 1.5)", "--warning", "70", "--critical", "90"],
        "real_metric": ["python3", script_path, "--target", "servers.ec2_instance_1.cpu.utilization", "--warning", "0", "--critical", "200", "--minutes", "5"]
    }
    
    # Run tests and collect stdout, stderr, and exit codes
    for name, cmd in tests.items():
        try:
            p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            result["tests"][name] = {
                "exit_code": p.returncode,
                "stdout": p.stdout.decode('utf-8', errors='replace').strip(),
                "stderr": p.stderr.decode('utf-8', errors='replace').strip()
            }
        except subprocess.TimeoutExpired:
            result["tests"][name] = {"exit_code": -1, "stdout": "", "stderr": "Execution Timeout", "timeout": True}
        except Exception as e:
            result["tests"][name] = {"exit_code": -1, "stdout": "", "stderr": str(e)}

with open('/tmp/graphite_nagios_plugin_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/graphite_nagios_plugin_result.json")
EOF

python3 /tmp/test_plugin.py

echo "=== Export complete ==="