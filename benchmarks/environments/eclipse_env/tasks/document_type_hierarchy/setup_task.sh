#!/bin/bash
set -e

echo "=== Setting up Document Type Hierarchy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Define workspace paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="MessageSystem"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Remove any existing project
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/com/msgsys/core"
mkdir -p "$PROJECT_DIR/src/com/msgsys/plugins"
mkdir -p "$PROJECT_DIR/src/com/msgsys/legacy"
mkdir -p "$PROJECT_DIR/bin"

# 1. Create .project file (Standard Eclipse metadata)
cat > "$PROJECT_DIR/.project" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$PROJECT_NAME</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

# 2. Create .classpath file
cat > "$PROJECT_DIR/.classpath" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/java-17-openjdk-amd64"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# 3. Create IMessageHandler interface (The Root)
cat > "$PROJECT_DIR/src/com/msgsys/core/IMessageHandler.java" <<EOF
package com.msgsys.core;

/**
 * Core interface for all message processing components in the system.
 * Any class implementing this can receive and route system messages.
 */
public interface IMessageHandler {
    /**
     * Process a single message.
     * @param msg The message payload
     * @return true if processed successfully
     */
    boolean handleMessage(String msg);
    
    /**
     * @return The unique identifier of this handler
     */
    String getHandlerId();
}
EOF

# 4. Create Direct Implementations (Easy to find via simple search)
cat > "$PROJECT_DIR/src/com/msgsys/plugins/EmailHandler.java" <<EOF
package com.msgsys.plugins;

import com.msgsys.core.IMessageHandler;

/**
 * Sends system notifications via SMTP email to registered administrators.
 * Used for critical system alerts.
 */
public class EmailHandler implements IMessageHandler {
    @Override
    public boolean handleMessage(String msg) {
        return true;
    }
    
    @Override
    public String getHandlerId() {
        return "EMAIL_V1";
    }
}
EOF

cat > "$PROJECT_DIR/src/com/msgsys/plugins/SMSHandler.java" <<EOF
package com.msgsys.plugins;

import com.msgsys.core.IMessageHandler;

/**
 * Dispatches short text messages via the Twilio gateway.
 * Intended for urgent, time-sensitive notifications.
 */
public class SMSHandler implements IMessageHandler {
    @Override
    public boolean handleMessage(String msg) {
        return true;
    }
    
    @Override
    public String getHandlerId() {
        return "SMS_GW";
    }
}
EOF

# 5. Create Abstract Base Class (The "Hidden" Link)
cat > "$PROJECT_DIR/src/com/msgsys/core/AbstractLoggingHandler.java" <<EOF
package com.msgsys.core;

/**
 * Base class for handlers that need to persist message content to storage.
 * Provides common IO utilities and timestamp generation.
 */
public abstract class AbstractLoggingHandler implements IMessageHandler {
    
    protected void logTimestamp() {
        System.out.println(System.currentTimeMillis());
    }
    
    @Override
    public abstract boolean handleMessage(String msg);
}
EOF

# 6. Create Indirect Implementations (Harder to find without hierarchy tools)
cat > "$PROJECT_DIR/src/com/msgsys/legacy/AuditLogHandler.java" <<EOF
package com.msgsys.legacy;

import com.msgsys.core.AbstractLoggingHandler;

/**
 * Writes message payloads to the immutable compliance audit log file.
 * Required for financial regulation adherence.
 */
public class AuditLogHandler extends AbstractLoggingHandler {
    @Override
    public boolean handleMessage(String msg) {
        logTimestamp();
        return true;
    }
    
    @Override
    public String getHandlerId() {
        return "AUDIT_COMPLIANCE";
    }
}
EOF

cat > "$PROJECT_DIR/src/com/msgsys/legacy/MetricsHandler.java" <<EOF
package com.msgsys.legacy;

import com.msgsys.core.AbstractLoggingHandler;

/**
 * Aggregates message throughput statistics and sends them to Datadog.
 * Does not store message content, only metadata.
 */
public class MetricsHandler extends AbstractLoggingHandler {
    @Override
    public boolean handleMessage(String msg) {
        return true;
    }
    
    @Override
    public String getHandlerId() {
        return "DD_METRICS";
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse and ensure it's ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Maximize and focus
focus_eclipse_window
sleep 2

# Dismiss welcome/tips
dismiss_dialogs 3
close_welcome_tab

# Open the Interface file to give the agent a starting point
# We use xdotool to open the 'Open Resource' dialog (Ctrl+Shift+R)
DISPLAY=:1 xdotool key ctrl+shift+r
sleep 1
DISPLAY=:1 xdotool type "IMessageHandler"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="