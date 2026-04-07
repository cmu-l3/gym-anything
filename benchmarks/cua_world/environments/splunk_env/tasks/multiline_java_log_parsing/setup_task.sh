#!/bin/bash
echo "=== Setting up multiline_java_log_parsing task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure target directory exists
mkdir -p /home/ga/Documents

# Create the multi-line Java log file
# Contains exactly 5 logical events but spans 17 lines total.
cat > /home/ga/Documents/java_errors.log << 'EOF'
2024-03-08 10:15:30,123 ERROR [main] com.example.App: Connection failed
java.net.ConnectException: Connection refused
    at java.net.PlainSocketImpl.socketConnect(Native Method)
    at java.net.AbstractPlainSocketImpl.doConnect(AbstractPlainSocketImpl.java:350)
2024-03-08 10:16:45,456 INFO  [main] com.example.App: Retrying connection...
2024-03-08 10:17:01,789 ERROR [main] com.example.App: Authentication failed
javax.naming.AuthenticationException: [LDAP: error code 49 - Invalid Credentials]
    at com.sun.jndi.ldap.LdapCtx.mapErrorCode(LdapCtx.java:3135)
    at com.sun.jndi.ldap.LdapCtx.processReturnCode(LdapCtx.java:3081)
    at com.sun.jndi.ldap.LdapCtx.processReturnCode(LdapCtx.java:2888)
2024-03-08 10:18:12,001 WARN  [main] com.example.App: Using fallback mechanism
2024-03-08 10:19:05,222 ERROR [worker-1] com.example.Task: NullPointerException encountered
java.lang.NullPointerException
    at com.example.Task.execute(Task.java:42)
    at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
    at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
    at java.lang.Thread.run(Thread.java:748)
EOF

# Set proper ownership
chown -R ga:ga /home/ga/Documents

echo "Created /home/ga/Documents/java_errors.log with 17 lines (5 logical events)."

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="