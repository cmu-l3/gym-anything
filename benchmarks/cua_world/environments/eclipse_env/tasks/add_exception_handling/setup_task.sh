#!/bin/bash
set -e

echo "=== Setting up Add Exception Handling task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define project paths
PROJECT_DIR="/home/ga/eclipse-workspace/DataProcessor"
SRC_PKG_DIR="$PROJECT_DIR/src/com/dataprocessor"
BIN_DIR="$PROJECT_DIR/bin"

# Cleanup any previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$SRC_PKG_DIR"
mkdir -p "$BIN_DIR"

# --- 1. Create Project Metadata (.project and .classpath) ---

cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>DataProcessor</name>
    <comment></comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
EOF

cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
EOF

# --- 2. Create Source Files (With Errors) ---

# ProcessingException.java (Base exception class, no errors)
cat > "$SRC_PKG_DIR/ProcessingException.java" << 'JAVA'
package com.dataprocessor;

public class ProcessingException extends Exception {
    private static final long serialVersionUID = 1L;

    public ProcessingException(String message) {
        super(message);
    }

    public ProcessingException(String message, Throwable cause) {
        super(message, cause);
    }

    public ProcessingException(Throwable cause) {
        super(cause);
    }
}
JAVA

# FileProcessor.java (Missing try-with-resources, unhandled IOExceptions)
cat > "$SRC_PKG_DIR/FileProcessor.java" << 'JAVA'
package com.dataprocessor;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

public class FileProcessor {
    private String inputPath;
    private String outputPath;

    public FileProcessor(String inputPath, String outputPath) {
        this.inputPath = inputPath;
        this.outputPath = outputPath;
    }

    // ERROR: Unhandled IOException
    public List<String> readLines() throws ProcessingException {
        List<String> lines = new ArrayList<>();
        // TODO: Use try-with-resources here
        BufferedReader reader = new BufferedReader(new FileReader(inputPath));
        String line;
        while ((line = reader.readLine()) != null) {
            lines.add(line.trim());
        }
        reader.close();
        return lines;
    }

    // ERROR: Unhandled IOException
    public void writeLines(List<String> lines) throws ProcessingException {
        // TODO: Use try-with-resources here
        BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath));
        for (String line : lines) {
            writer.write(line);
            writer.newLine();
        }
        writer.flush();
        writer.close();
    }
}
JAVA

# DatabaseConnector.java (Missing try-catch for SQL/Class exceptions)
cat > "$SRC_PKG_DIR/DatabaseConnector.java" << 'JAVA'
package com.dataprocessor;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class DatabaseConnector {
    private String dbUrl;
    private Connection connection;

    public DatabaseConnector(String dbUrl) {
        this.dbUrl = dbUrl;
    }

    // ERROR: Unhandled ClassNotFoundException
    public void loadDriver() throws ProcessingException {
        Class.forName("org.postgresql.Driver");
    }

    // ERROR: Unhandled SQLException
    public void connect() throws ProcessingException {
        connection = DriverManager.getConnection(dbUrl, "user", "pass");
    }

    // ERROR: Unhandled SQLException
    public void disconnect() throws ProcessingException {
        if (connection != null && !connection.isClosed()) {
            connection.close();
        }
    }
}
JAVA

# ConfigParser.java (Missing try-catch/chaining)
cat > "$SRC_PKG_DIR/ConfigParser.java" << 'JAVA'
package com.dataprocessor;

import java.io.FileInputStream;
import java.io.IOException;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Properties;

public class ConfigParser {
    private Properties props = new Properties();

    // ERROR: Unhandled IOException
    public void load(String file) throws ProcessingException {
        FileInputStream fis = new FileInputStream(file);
        props.load(fis);
        fis.close();
    }

    // ERROR: Unhandled ParseException
    public Date getDate(String key) throws ProcessingException {
        String val = props.getProperty(key);
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
        return sdf.parse(val);
    }
}
JAVA

# App.java (Missing top-level handling)
cat > "$SRC_PKG_DIR/App.java" << 'JAVA'
package com.dataprocessor;

public class App {
    // ERROR: Unhandled ProcessingException from called methods
    public static void main(String[] args) {
        System.out.println("Starting application...");
        
        FileProcessor fp = new FileProcessor("in.txt", "out.txt");
        fp.readLines();
        
        DatabaseConnector db = new DatabaseConnector("jdbc:mysql://localhost/db");
        db.loadDriver();
        
        System.out.println("Done.");
    }
}
JAVA

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# --- 3. Start Eclipse and Import ---

# Ensure Eclipse is running
if ! pgrep -f "eclipse" > /dev/null; then
    echo "Starting Eclipse..."
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "eclipse"; then
            break
        fi
        sleep 1
    done
    sleep 10
fi

# Focus Eclipse
DISPLAY=:1 wmctrl -a "Eclipse" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Eclipse" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss welcome/popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Import the project (File > Open Projects from File System...)
# Shortcut: Alt+F -> n (Open Projects from File System is usually under File)
# Note: Shortcuts vary. Reliable method is checking if it auto-scanned or using Import wizard.
# Since we put it in the workspace folder, usually a "Refresh" or explicit import is needed.

# We will rely on the agent to deal with the project not being immediately visible if that happens,
# BUT for a fair start, we try to import it via CLI xdotool or assume user can do it.
# To make it fair/standard: We'll leave it in the workspace folder. Eclipse often detects it on startup 
# if it was there, but since we just created it, we might need to trigger a refresh.
# Sending F5 (Refresh) to Package Explorer.
DISPLAY=:1 xdotool key F5
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="