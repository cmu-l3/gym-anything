#!/bin/bash
set -e
echo "=== Setting up resolve_merge_conflicts task ==="

source /workspace/scripts/task_utils.sh

# Configuration
PROJECT_NAME="chinook-java"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR"

# 1. Create Base Maven Project Structure
echo "Creating project structure..."
mkdir -p "$PROJECT_DIR/src/main/java/com/chinook/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/chinook/service"

# Create base files (common ancestor)

# pom.xml (Base)
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.chinook</groupId>
  <artifactId>chinook-java</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.11</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOF

# Track.java (Base)
cat > "$PROJECT_DIR/src/main/java/com/chinook/model/Track.java" << 'EOF'
package com.chinook.model;

public class Track {
    private int id;
    private String name;
    private String albumName;
    private int milliseconds;
    private double unitPrice;

    public Track(int id, String name, int milliseconds) {
        this.id = id;
        this.name = name;
        this.milliseconds = milliseconds;
    }

    public String getName() { return name; }
    public int getMilliseconds() { return milliseconds; }
    
    @Override
    public String toString() {
        return "Track [id=" + id + ", name=" + name + "]";
    }
}
EOF

# PlaylistService.java (Base)
cat > "$PROJECT_DIR/src/main/java/com/chinook/service/PlaylistService.java" << 'EOF'
package com.chinook.service;

import com.chinook.model.Track;
import java.util.List;
import java.util.ArrayList;

public class PlaylistService {
    private List<Track> tracks = new ArrayList<>();

    public void addTrack(Track track) {
        tracks.add(track);
    }

    public int getTrackCount() {
        return tracks.size();
    }
}
EOF

# Eclipse configuration files
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>chinook-java</name>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOF

cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOF

# Initialize Git and create Base Commit
cd "$PROJECT_DIR"
git init
git config user.name "Dev One"
git config user.email "dev1@example.com"
git add .
git commit -m "Initial commit"

# 2. Create Feature Branch (Add CSV Export)
git checkout -b feature/playlist-export

# Modify pom.xml (Add OpenCSV)
sed -i '/<dependencies>/a \    <dependency>\n      <groupId>com.opencsv</groupId>\n      <artifactId>opencsv</artifactId>\n      <version>5.9</version>\n    </dependency>' pom.xml

# Modify Track.java (Add CSV support and album name to toString)
cat > "$PROJECT_DIR/src/main/java/com/chinook/model/Track.java" << 'EOF'
package com.chinook.model;

public class Track {
    private int id;
    private String name;
    private String albumName;
    private int milliseconds;
    private double unitPrice;

    public Track(int id, String name, int milliseconds) {
        this.id = id;
        this.name = name;
        this.milliseconds = milliseconds;
    }

    public String getName() { return name; }
    public int getMilliseconds() { return milliseconds; }
    
    public String[] toCsvRow() {
        return new String[] { String.valueOf(id), name, String.valueOf(milliseconds) };
    }

    @Override
    public String toString() {
        return "Track [id=" + id + ", name=" + name + ", album=" + albumName + "]";
    }
}
EOF

# Modify PlaylistService.java (Add CSV Export)
cat > "$PROJECT_DIR/src/main/java/com/chinook/service/PlaylistService.java" << 'EOF'
package com.chinook.service;

import com.chinook.model.Track;
import java.util.List;
import java.util.ArrayList;
import java.io.FileWriter;
import java.io.IOException;

public class PlaylistService {
    private List<Track> tracks = new ArrayList<>();

    public void addTrack(Track track) {
        tracks.add(track);
    }

    public int getTrackCount() {
        return tracks.size();
    }

    public void exportToCsv(String filename) throws IOException {
        try (FileWriter writer = new FileWriter(filename)) {
            for (Track t : tracks) {
                writer.write(t.toString() + "\n");
            }
        }
    }
}
EOF

git add .
git commit -m "Add playlist export feature"

# 3. Switch back to Main and Create Conflicts
git checkout main

# Modify pom.xml (Add Gson - Conflict!)
sed -i '/<dependencies>/a \    <dependency>\n      <groupId>com.google.code.gson</groupId>\n      <artifactId>gson</artifactId>\n      <version>2.10.1</version>\n    </dependency>' pom.xml

# Modify Track.java (Add Streaming Quality - Conflict!)
cat > "$PROJECT_DIR/src/main/java/com/chinook/model/Track.java" << 'EOF'
package com.chinook.model;

public class Track {
    private int id;
    private String name;
    private String albumName;
    private int milliseconds;
    private double unitPrice;

    public enum StreamingQuality { SD, HD, ULTRA_HD }

    public Track(int id, String name, int milliseconds) {
        this.id = id;
        this.name = name;
        this.milliseconds = milliseconds;
    }

    public String getName() { return name; }
    public int getMilliseconds() { return milliseconds; }
    
    public StreamingQuality getStreamingQuality() {
        return milliseconds > 300000 ? StreamingQuality.HD : StreamingQuality.SD;
    }

    @Override
    public String toString() {
        return "Track [id=" + id + ", name=" + name + "]";
    }
}
EOF

# Modify PlaylistService.java (Add Duration calc - Conflict!)
cat > "$PROJECT_DIR/src/main/java/com/chinook/service/PlaylistService.java" << 'EOF'
package com.chinook.service;

import com.chinook.model.Track;
import java.util.List;
import java.util.ArrayList;
import java.time.Duration;

public class PlaylistService {
    private List<Track> tracks = new ArrayList<>();

    public void addTrack(Track track) {
        tracks.add(track);
    }

    public int getTrackCount() {
        return tracks.size();
    }

    public Duration getPlaylistDuration() {
        long totalMillis = tracks.stream().mapToLong(Track::getMilliseconds).sum();
        return Duration.ofMillis(totalMillis);
    }
}
EOF

git add .
git commit -m "Add streaming quality features"

# 4. Trigger the Conflict
git checkout feature/playlist-export
# This will fail with conflicts, but we force it to happen and ignore the exit code
git merge main || true

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record timestamps
date +%s > /tmp/task_start_time.txt
find "$PROJECT_DIR" -type f -exec stat -c %Y {} + > /tmp/initial_timestamps.txt

# 5. Launch Eclipse
echo "Launching Eclipse..."
if ! pgrep -f "eclipse" > /dev/null; then
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data $WORKSPACE_DIR > /tmp/eclipse.log 2>&1 &"
    
    # Wait for Eclipse
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "eclipse"; then
            echo "Eclipse started"
            break
        fi
        sleep 2
    done
fi

# Focus and Maximize
DISPLAY=:1 wmctrl -r "Eclipse" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Eclipse" 2>/dev/null || true

# Wait a bit for project to render
sleep 5

# Take initial screenshot (should show red conflict markers)
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="