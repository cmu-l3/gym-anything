#!/bin/bash
set -e
echo "=== Setting up JPMS Module Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define project paths
PROJECT_DIR="/home/ga/eclipse-workspace/ModularApp"
SRC_DIR="$PROJECT_DIR/src/com/appcore"

# Clean up any previous runs
rm -rf "$PROJECT_DIR"
rm -f /home/ga/module_report.txt

# Create directories
mkdir -p "$SRC_DIR/api"
mkdir -p "$SRC_DIR/model"
mkdir -p "$SRC_DIR/data"
mkdir -p "$SRC_DIR/logging"
mkdir -p "$PROJECT_DIR/bin"
mkdir -p "$PROJECT_DIR/.settings"

# 1. Create HttpApiClient.java (uses java.net.http)
cat > "$SRC_DIR/api/HttpApiClient.java" << 'EOF'
package com.appcore.api;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import com.appcore.model.User;

public class HttpApiClient {
    private final HttpClient client;
    private final String baseUrl;

    public HttpApiClient(String baseUrl) {
        this.baseUrl = baseUrl;
        this.client = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .version(HttpClient.Version.HTTP_2)
                .build();
    }

    public String fetchUserData(int userId) throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(baseUrl + "/users/" + userId))
                .header("Accept", "application/json")
                .timeout(Duration.ofSeconds(30))
                .GET()
                .build();

        HttpResponse<String> response = client.send(request,
                HttpResponse.BodyHandlers.ofString());
        return response.body();
    }
}
EOF

# 2. Create User.java (POJO)
cat > "$SRC_DIR/model/User.java" << 'EOF'
package com.appcore.model;

import java.util.Objects;

public class User {
    private String name;
    private String email;

    public User(String name, String email) {
        this.name = name;
        this.email = email;
    }

    public String getName() { return name; }
    public String getEmail() { return email; }
}
EOF

# 3. Create DatabaseConfig.java (uses java.sql)
cat > "$SRC_DIR/data/DatabaseConfig.java" << 'EOF'
package com.appcore.data;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

public class DatabaseConfig {
    private final String jdbcUrl;
    private final Properties props;

    public DatabaseConfig(String jdbcUrl) {
        this.jdbcUrl = jdbcUrl;
        this.props = new Properties();
    }

    public Connection getConnection() throws SQLException {
        return DriverManager.getConnection(jdbcUrl, props);
    }
}
EOF

# 4. Create AppLogger.java (uses java.logging)
cat > "$SRC_DIR/logging/AppLogger.java" << 'EOF'
package com.appcore.logging;

import java.util.logging.Level;
import java.util.logging.Logger;

public class AppLogger {
    private static final Logger LOGGER = Logger.getLogger("com.appcore");

    public static void info(String msg) {
        LOGGER.info(msg);
    }

    public static void setLevel(Level level) {
        LOGGER.setLevel(level);
    }
}
EOF

# Create Eclipse .project file
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>ModularApp</name>
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

# Create Eclipse .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="module" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="bin"/>
</classpath>
EOF

# Create Java compiler settings (Java 17)
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'EOF'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
org.eclipse.jdt.core.compiler.release=enabled
EOF

# Fix ownership
chown -R ga:ga "$PROJECT_DIR"

# Ensure Eclipse is running
if ! pgrep -f "eclipse" > /dev/null; then
    echo "Starting Eclipse..."
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace > /dev/null 2>&1 &"
    sleep 30
fi

# Wait for Eclipse window
wait_for_eclipse 60

# Maximize Eclipse
focus_eclipse_window
sleep 2

# Dismiss dialogs
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="