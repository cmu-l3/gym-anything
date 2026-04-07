#!/bin/bash
echo "=== Setting up memory snapshot task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/heap_analysis.fxsnapshot

# Create the memory leak test HTML file
# This creates a realistic local test case for the agent to profile
cat > /home/ga/Documents/memory_leak.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Memory Leak Debugging Environment</title>
    <style>
        body { font-family: system-ui, sans-serif; padding: 2rem; max-width: 800px; margin: 0 auto; background: #f9f9fb; color: #15141a; }
        .card { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        button { padding: 12px 24px; font-size: 16px; cursor: pointer; background: #0060df; color: white; border: none; border-radius: 4px; transition: background 0.2s; }
        button:hover { background: #003eaa; }
        button:active { background: #002275; }
        #status { margin-top: 20px; padding: 10px; font-weight: 500; border-radius: 4px; }
        .success { background: #dff0d8; color: #3c763d; border: 1px solid #d6e9c6; }
        .pending { background: #fcf8e3; color: #8a6d3b; border: 1px solid #faebcc; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Memory Leak Generator</h1>
        <p>This page simulates a detached DOM tree and JS heap memory leak for DevTools analysis.</p>
        
        <button id="leakBtn">Generate Memory Leak</button>
        <div id="status">Ready. Click the button to simulate the leak.</div>
    </div>

    <script>
        // Attach to window so it isn't garbage collected by the SpiderMonkey engine
        window.leakedObjects = [];

        document.getElementById('leakBtn').addEventListener('click', function() {
            const status = document.getElementById('status');
            status.className = 'pending';
            status.innerText = 'Generating heap allocations...';
            
            // Disable button to prevent multiple clicks
            this.disabled = true;

            // Create a large number of objects with a specific verifiable signature
            setTimeout(() => {
                for (let i = 0; i < 50000; i++) {
                    window.leakedObjects.push({
                        id: i,
                        data: "LEAKED_STRING_DATA_" + Math.random().toString(36).substring(2) + "_PADDING_" + "A".repeat(200),
                        timestamp: Date.now(),
                        detachedNode: document.createElement('div')
                    });
                }
                status.className = 'success';
                status.innerText = 'Memory leak generated! 50,000 objects allocated to the JS heap.';
            }, 500);
        });
    </script>
</body>
</html>
EOF

# Fix permissions
chown ga:ga /home/ga/Documents/memory_leak.html

# Start Firefox with the target page
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox file:///home/ga/Documents/memory_leak.html &"
    sleep 5
else
    # If already running, open a new tab with the target page
    su - ga -c "DISPLAY=:1 firefox -new-tab file:///home/ga/Documents/memory_leak.html &"
    sleep 3
fi

# Wait for the Firefox window to appear
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Memory Leak"; then
        break
    fi
    sleep 1
done

# Focus and maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Memory Leak" 2>/dev/null || true

# Take an initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="