#!/bin/bash
set -e
echo "=== Setting up generate_delegate_methods task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define project paths
PROJECT_NAME="MessageServiceApp"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"
SRC_DIR="$PROJECT_DIR/src/com/messaging"

# Clean up any existing project
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/bin"
mkdir -p "$SRC_DIR/api"
mkdir -p "$SRC_DIR/impl"
mkdir -p "$SRC_DIR/decorator"
mkdir -p "$SRC_DIR/app"

# 1. Create MessageService Interface
cat > "$SRC_DIR/api/MessageService.java" << 'EOF'
package com.messaging.api;

public interface MessageService {
    void sendMessage(String to, String subject, String body);
    boolean deleteMessage(int messageId);
    String getMessage(int messageId);
    int getMessageCount();
    boolean isConnected();
    void connect(String server, int port);
}
EOF

# 2. Create EmailService Implementation
cat > "$SRC_DIR/impl/EmailService.java" << 'EOF'
package com.messaging.impl;

import java.util.HashMap;
import java.util.Map;
import com.messaging.api.MessageService;

public class EmailService implements MessageService {
    private Map<Integer, String> messages = new HashMap<>();
    private boolean connected = false;

    @Override
    public void sendMessage(String to, String subject, String body) {
        System.out.println("Email sent to " + to);
        messages.put(messages.size() + 1, subject);
    }

    @Override
    public boolean deleteMessage(int messageId) {
        return messages.remove(messageId) != null;
    }

    @Override
    public String getMessage(int messageId) {
        return messages.get(messageId);
    }

    @Override
    public int getMessageCount() {
        return messages.size();
    }

    @Override
    public boolean isConnected() {
        return connected;
    }

    @Override
    public void connect(String server, int port) {
        this.connected = true;
        System.out.println("Connected to " + server + ":" + port);
    }
}
EOF

# 3. Create LoggingMessageService (INCOMPLETE - The Target)
cat > "$SRC_DIR/decorator/LoggingMessageService.java" << 'EOF'
package com.messaging.decorator;

import com.messaging.api.MessageService;

public class LoggingMessageService implements MessageService {
    
    private final MessageService delegate;
    
    public LoggingMessageService(MessageService delegate) {
        this.delegate = delegate;
    }

    // TODO: Generate delegate methods here using Source > Generate Delegate Methods...
    // TODO: Add logging to sendMessage and getMessageCount
    
}
EOF

# 4. Create Main App
cat > "$SRC_DIR/app/Main.java" << 'EOF'
package com.messaging.app;

import com.messaging.api.MessageService;
import com.messaging.impl.EmailService;
import com.messaging.decorator.LoggingMessageService;

public class Main {
    public static void main(String[] args) {
        MessageService realService = new EmailService();
        // This will fail to compile until LoggingMessageService implements methods
        MessageService loggingService = new LoggingMessageService(realService);
        
        loggingService.connect("smtp.example.com", 587);
        loggingService.sendMessage("user@example.com", "Hello", "World");
        loggingService.getMessageCount();
    }
}
EOF

# 5. Create Eclipse .project file
cat > "$PROJECT_DIR/.project" << EOF
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

# 6. Create Eclipse .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Launch/Reset Eclipse
echo "Ensuring Eclipse is running..."
wait_for_eclipse 60 || echo "Starting Eclipse..."
if ! pgrep -f "eclipse" > /dev/null; then
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data $WORKSPACE_DIR > /tmp/eclipse.log 2>&1 &"
    wait_for_eclipse 120
fi

# Focus and maximize
focus_eclipse_window
sleep 2

# Force refresh of workspace logic (hacky but effective: touch .project)
touch "$PROJECT_DIR/.project"
sleep 2

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="