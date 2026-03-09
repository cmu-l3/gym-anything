#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome IndexedDB Modification Task Setup ==="
echo "Task: Use DevTools to modify IndexedDB record status"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python WebSocket client for CDP verification
pip3 install -q websocket-client 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the task manager web application
echo "Creating Task Manager web application with IndexedDB..."
TASK_APP_DIR="/home/ga/Documents"
mkdir -p "$TASK_APP_DIR"

cat > "$TASK_APP_DIR/task_manager.html" << 'EOFHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Task Manager - IndexedDB Demo</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 800px;
            margin: 40px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #666;
            font-size: 14px;
            margin-bottom: 30px;
        }
        .task {
            padding: 15px;
            margin: 10px 0;
            border-radius: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: all 0.3s ease;
        }
        .task:hover {
            transform: translateX(5px);
        }
        .task.completed {
            background: linear-gradient(135deg, #d4edda 0%, #c3e6cb 100%);
            border-left: 4px solid #28a745;
        }
        .task.pending {
            background: linear-gradient(135deg, #fff3cd 0%, #ffeeba 100%);
            border-left: 4px solid #ffc107;
        }
        .task-info {
            flex: 1;
        }
        .task-title {
            font-weight: 600;
            font-size: 16px;
            margin-bottom: 5px;
        }
        .task-meta {
            font-size: 12px;
            color: #666;
        }
        .status-badge {
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
        }
        .status-badge.completed {
            background: #28a745;
            color: white;
        }
        .status-badge.pending {
            background: #ffc107;
            color: #333;
        }
        .info-box {
            background: #e7f3ff;
            border-left: 4px solid #2196F3;
            padding: 15px;
            margin-top: 20px;
            border-radius: 5px;
        }
        .info-box h3 {
            margin-top: 0;
            color: #1976D2;
            font-size: 16px;
        }
        .info-box p {
            margin: 5px 0;
            font-size: 14px;
            color: #555;
        }
        .info-box code {
            background: #fff;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            color: #d63384;
        }
        #loading {
            text-align: center;
            color: #666;
            padding: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📋 Task Manager</h1>
        <p class="subtitle">Development Task Tracker with IndexedDB Storage</p>
        
        <div id="loading">Loading tasks from IndexedDB...</div>
        <div id="tasks" style="display: none;"></div>
        
        <div class="info-box">
            <h3>🔍 DevTools Challenge</h3>
            <p><strong>Your Task:</strong> Open Chrome DevTools (F12) and navigate to the <strong>Application</strong> tab.</p>
            <p>1. Expand <code>IndexedDB → TaskManager → tasks</code></p>
            <p>2. Find the record with <code>id = 3</code> (Review PR #247)</p>
            <p>3. Double-click the <code>status</code> field and change it from <code>"pending"</code> to <code>"completed"</code></p>
            <p>4. Press Enter to save, then refresh this page to see the change!</p>
        </div>
    </div>

    <script>
        let db;
        
        // Initialize IndexedDB
        function initDB() {
            return new Promise((resolve, reject) => {
                const request = indexedDB.open('TaskManager', 1);
                
                request.onerror = () => reject(request.error);
                request.onsuccess = () => {
                    db = request.result;
                    resolve(db);
                };
                
                request.onupgradeneeded = (event) => {
                    db = event.target.result;
                    
                    // Create object store with id as keyPath
                    const objectStore = db.createObjectStore('tasks', { keyPath: 'id' });
                    
                    // Create indexes
                    objectStore.createIndex('status', 'status', { unique: false });
                    objectStore.createIndex('priority', 'priority', { unique: false });
                    
                    // Add initial task data
                    const initialTasks = [
                        {
                            id: 1,
                            title: 'Setup development environment',
                            status: 'completed',
                            priority: 'high',
                            description: 'Install Node.js, VS Code, and configure Git'
                        },
                        {
                            id: 2,
                            title: 'Write unit tests for API endpoints',
                            status: 'completed',
                            priority: 'medium',
                            description: 'Add Jest test coverage for all REST endpoints'
                        },
                        {
                            id: 3,
                            title: 'Review PR #247',
                            status: 'pending',
                            priority: 'high',
                            description: 'Code review for authentication refactoring'
                        },
                        {
                            id: 4,
                            title: 'Update documentation',
                            status: 'pending',
                            priority: 'low',
                            description: 'Add API documentation for new endpoints'
                        },
                        {
                            id: 5,
                            title: 'Fix performance issues in dashboard',
                            status: 'pending',
                            priority: 'high',
                            description: 'Optimize database queries causing slow load times'
                        }
                    ];
                    
                    initialTasks.forEach(task => {
                        objectStore.add(task);
                    });
                };
            });
        }
        
        // Load and display tasks
        function loadTasks() {
            const transaction = db.transaction(['tasks'], 'readonly');
            const objectStore = transaction.objectStore('tasks');
            const request = objectStore.getAll();
            
            request.onsuccess = () => {
                const tasks = request.result;
                displayTasks(tasks);
            };
            
            request.onerror = () => {
                console.error('Failed to load tasks:', request.error);
            };
        }
        
        // Display tasks in UI
        function displayTasks(tasks) {
            const container = document.getElementById('tasks');
            const loading = document.getElementById('loading');
            
            container.innerHTML = '';
            
            // Sort tasks: pending first, then by priority
            const priorityOrder = { high: 1, medium: 2, low: 3 };
            tasks.sort((a, b) => {
                if (a.status !== b.status) {
                    return a.status === 'pending' ? -1 : 1;
                }
                return priorityOrder[a.priority] - priorityOrder[b.priority];
            });
            
            tasks.forEach(task => {
                const taskDiv = document.createElement('div');
                taskDiv.className = `task ${task.status}`;
                taskDiv.innerHTML = `
                    <div class="task-info">
                        <div class="task-title">${task.title}</div>
                        <div class="task-meta">
                            Priority: ${task.priority} | ID: ${task.id}
                        </div>
                    </div>
                    <span class="status-badge ${task.status}">${task.status}</span>
                `;
                container.appendChild(taskDiv);
            });
            
            loading.style.display = 'none';
            container.style.display = 'block';
        }
        
        // Initialize on page load
        initDB().then(() => {
            console.log('IndexedDB initialized successfully');
            console.log('Database: TaskManager');
            console.log('Object Store: tasks');
            loadTasks();
        }).catch(error => {
            console.error('Failed to initialize IndexedDB:', error);
            document.getElementById('loading').innerHTML = 
                '<p style="color: red;">Failed to initialize database. Please refresh the page.</p>';
        });
        
        // Expose helper function for verification
        window.getTaskStatus = function(taskId) {
            return new Promise((resolve, reject) => {
                const transaction = db.transaction(['tasks'], 'readonly');
                const objectStore = transaction.objectStore('tasks');
                const request = objectStore.get(taskId);
                
                request.onsuccess = () => {
                    if (request.result) {
                        resolve(request.result.status);
                    } else {
                        reject(new Error('Task not found'));
                    }
                };
                
                request.onerror = () => reject(request.error);
            });
        };
    </script>
</body>
</html>
EOFHTML

chown ga:ga "$TASK_APP_DIR/task_manager.html"
echo "✓ Task Manager application created at: $TASK_APP_DIR/task_manager.html"

# Ensure Chrome is running
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the task manager application
TASK_APP_URL="file:///home/ga/Documents/task_manager.html"
echo "Navigating to: $TASK_APP_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TASK_APP_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Wait for page and IndexedDB to initialize
echo "Waiting for IndexedDB initialization..."
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Verify the page loaded correctly
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"task_manager.html"* ]]; then
        echo "✓ Task Manager application loaded successfully"
    else
        echo "⚠ Warning: Task Manager may not have loaded correctly"
        echo "  Active URL: $ACTIVE_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Record initial state for verification
echo "Recording initial IndexedDB state..."
mkdir -p /tmp/indexeddb_verification
echo "pending" > /tmp/indexeddb_verification/initial_status.txt
echo "3" > /tmp/indexeddb_verification/target_task_id.txt

echo "=== Setup complete ==="
echo "Chrome is displaying the Task Manager application"
echo ""
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Click on 'Application' tab"
echo "  3. Expand 'Storage' → 'IndexedDB' → 'TaskManager' → 'tasks'"
echo "  4. Locate record with id=3 (Review PR #247)"
echo "  5. Double-click the 'status' field value 'pending'"
echo "  6. Type 'completed' and press Enter"
echo ""
echo "The page can be refreshed to verify the change visually"