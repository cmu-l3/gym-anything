#!/bin/bash
set -e
echo "=== Setting up implement_log_parser task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/log-analyzer"

# 1. Create Project Structure
echo "Creating project structure..."
mkdir -p "$PROJECT_DIR/src/main/java/com/loganalyzer"
mkdir -p "$PROJECT_DIR/src/main/resources"
mkdir -p "$PROJECT_DIR/src/test/java/com/loganalyzer"
mkdir -p "$PROJECT_DIR/output"

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.loganalyzer</groupId>
    <artifactId>log-analyzer</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# 3. Create POJOs and Main class (Complete)
# LogEntry.java
cat > "$PROJECT_DIR/src/main/java/com/loganalyzer/LogEntry.java" << 'JAVAEOF'
package com.loganalyzer;

import java.time.LocalDateTime;

public class LogEntry {
    private final String host;
    private final LocalDateTime timestamp;
    private final String method;
    private final String path;
    private final int statusCode;
    private final long bytes;

    public LogEntry(String host, LocalDateTime timestamp, String method, String path, int statusCode, long bytes) {
        this.host = host;
        this.timestamp = timestamp;
        this.method = method;
        this.path = path;
        this.statusCode = statusCode;
        this.bytes = bytes;
    }

    public String getHost() { return host; }
    public LocalDateTime getTimestamp() { return timestamp; }
    public String getMethod() { return method; }
    public String getPath() { return path; }
    public int getStatusCode() { return statusCode; }
    public long getBytes() { return bytes; }
}
JAVAEOF

# AnalysisReport.java
cat > "$PROJECT_DIR/src/main/java/com/loganalyzer/AnalysisReport.java" << 'JAVAEOF'
package com.loganalyzer;

import java.util.List;
import java.util.Map;

public class AnalysisReport {
    private final int totalRequests;
    private final int uniqueHosts;
    private final Map<Integer, Long> statusCodeCounts;
    private final List<Map.Entry<String, Long>> topPaths;
    private final long totalBytes;
    private final double averageBytes;

    public AnalysisReport(int totalRequests, int uniqueHosts, Map<Integer, Long> statusCodeCounts,
                          List<Map.Entry<String, Long>> topPaths, long totalBytes, double averageBytes) {
        this.totalRequests = totalRequests;
        this.uniqueHosts = uniqueHosts;
        this.statusCodeCounts = statusCodeCounts;
        this.topPaths = topPaths;
        this.totalBytes = totalBytes;
        this.averageBytes = averageBytes;
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append("=== Traffic Analysis Report ===\n");
        sb.append("Total Requests: ").append(totalRequests).append("\n");
        sb.append("Unique Hosts: ").append(uniqueHosts).append("\n");
        sb.append("Total Bytes Transferred: ").append(totalBytes).append("\n");
        sb.append("Average Response Size: ").append(String.format("%.2f", averageBytes)).append(" bytes\n");
        
        sb.append("\nStatus Codes:\n");
        statusCodeCounts.forEach((code, count) -> sb.append(code).append(": ").append(count).append("\n"));
        
        sb.append("\nTop 10 Paths:\n");
        topPaths.forEach(entry -> sb.append(entry.getKey()).append(" - ").append(entry.getValue()).append(" hits\n"));
        
        return sb.toString();
    }
}
JAVAEOF

# Main.java
cat > "$PROJECT_DIR/src/main/java/com/loganalyzer/Main.java" << 'JAVAEOF'
package com.loganalyzer;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        try {
            LogParser parser = new LogParser();
            Path logFile = Paths.get("src/main/resources/access.log");
            
            System.out.println("Parsing log file...");
            List<LogEntry> entries = parser.parseLogFile(logFile);
            System.out.println("Parsed " + entries.size() + " entries.");

            LogAnalyzer analyzer = new LogAnalyzer();
            AnalysisReport report = analyzer.analyze(entries);
            
            System.out.println("Generating report...");
            Path outputPath = Paths.get("output/report.txt");
            Files.createDirectories(outputPath.getParent());
            Files.writeString(outputPath, report.toString());
            
            System.out.println("Report saved to " + outputPath.toAbsolutePath());
            System.out.println(report);
            
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
JAVAEOF

# 4. Create Stubs (Task for Agent)
# LogParser.java
cat > "$PROJECT_DIR/src/main/java/com/loganalyzer/LogParser.java" << 'JAVAEOF'
package com.loganalyzer;

import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import java.util.ArrayList;
import java.util.regex.Pattern;
import java.util.regex.Matcher;

public class LogParser {
    
    // TODO: Define regex pattern for Common Log Format
    // Example: host - - [date] "request" status bytes
    private static final Pattern LOG_PATTERN = Pattern.compile("");

    public LogEntry parseLogLine(String line) {
        // TODO: Implement regex parsing
        // 1. Match line against regex
        // 2. Extract groups
        // 3. Parse timestamp (Format: dd/MMM/yyyy:HH:mm:ss Z)
        // 4. Return new LogEntry
        // Return null if line doesn't match
        return null;
    }

    public List<LogEntry> parseLogFile(Path filePath) throws IOException {
        List<LogEntry> entries = new ArrayList<>();
        // TODO: Read file line by line, parse each line, add non-null entries to list
        return entries;
    }
}
JAVAEOF

# LogAnalyzer.java
cat > "$PROJECT_DIR/src/main/java/com/loganalyzer/LogAnalyzer.java" << 'JAVAEOF'
package com.loganalyzer;

import java.util.List;
import java.util.Map;
import java.util.HashMap;

public class LogAnalyzer {

    public AnalysisReport analyze(List<LogEntry> entries) {
        // TODO: Implement analysis logic
        // 1. Calculate total requests
        // 2. Count unique hosts
        // 3. Count status codes
        // 4. Find top 10 most frequent paths
        // 5. Calculate total and average bytes
        
        return new AnalysisReport(0, 0, new HashMap<>(), new ArrayList<>(), 0, 0.0);
    }
}
JAVAEOF

# 5. Create Tests
# LogParserTest.java
cat > "$PROJECT_DIR/src/test/java/com/loganalyzer/LogParserTest.java" << 'JAVAEOF'
package com.loganalyzer;

import org.junit.Test;
import static org.junit.Assert.*;
import java.time.LocalDateTime;

public class LogParserTest {

    private final LogParser parser = new LogParser();

    @Test
    public void testParseValidLine() {
        String line = "199.72.81.55 - - [01/Jul/1995:00:00:01 -0400] \"GET /history/apollo/ HTTP/1.0\" 200 6245";
        LogEntry entry = parser.parseLogLine(line);
        
        assertNotNull("Entry should not be null", entry);
        assertEquals("199.72.81.55", entry.getHost());
        assertEquals(200, entry.getStatusCode());
        assertEquals(6245, entry.getBytes());
        assertEquals("/history/apollo/", entry.getPath());
        assertEquals("GET", entry.getMethod());
        assertEquals(1, entry.getTimestamp().getSecond());
    }

    @Test
    public void testParseLineWithHyphenBytes() {
        String line = "unicomp6.unicomp.net - - [01/Jul/1995:00:00:06 -0400] \"GET /shuttle/countdown/ HTTP/1.0\" 200 -";
        LogEntry entry = parser.parseLogLine(line);
        
        assertNotNull(entry);
        assertEquals(0, entry.getBytes());
    }

    @Test
    public void testParseMalformedLine() {
        String line = "This is not a log line";
        LogEntry entry = parser.parseLogLine(line);
        assertNull(entry);
    }
}
JAVAEOF

# LogAnalyzerTest.java
cat > "$PROJECT_DIR/src/test/java/com/loganalyzer/LogAnalyzerTest.java" << 'JAVAEOF'
package com.loganalyzer;

import org.junit.Test;
import static org.junit.Assert.*;
import java.util.Arrays;
import java.util.List;
import java.time.LocalDateTime;

public class LogAnalyzerTest {

    private final LogAnalyzer analyzer = new LogAnalyzer();

    private List<LogEntry> createSampleData() {
        LocalDateTime now = LocalDateTime.now();
        return Arrays.asList(
            new LogEntry("host1", now, "GET", "/index.html", 200, 100),
            new LogEntry("host1", now, "GET", "/img.png", 200, 200),
            new LogEntry("host2", now, "GET", "/index.html", 404, 0),
            new LogEntry("host3", now, "GET", "/about.html", 200, 150)
        );
    }

    @Test
    public void testAnalyzeTotalRequests() {
        AnalysisReport report = analyzer.analyze(createSampleData());
        assertTrue("Total requests should be 4", report.toString().contains("Total Requests: 4"));
    }

    @Test
    public void testAnalyzeUniqueHosts() {
        AnalysisReport report = analyzer.analyze(createSampleData());
        assertTrue("Unique hosts should be 3", report.toString().contains("Unique Hosts: 3"));
    }

    @Test
    public void testAnalyzeStatusCodes() {
        AnalysisReport report = analyzer.analyze(createSampleData());
        String output = report.toString();
        assertTrue(output.contains("200: 3"));
        assertTrue(output.contains("404: 1"));
    }
}
JAVAEOF

# 6. Prepare Data (Real NASA Logs)
# Try to use cached data or generate representative real data
echo "Preparing log data..."

# Using a heredoc with REAL lines from the dataset to ensure availability
# (Downloading 200MB dataset for a simple parser task is overkill and flaky in isolated envs)
cat > "$PROJECT_DIR/src/main/resources/access.log" << 'LOGEOF'
199.72.81.55 - - [01/Jul/1995:00:00:01 -0400] "GET /history/apollo/ HTTP/1.0" 200 6245
unicomp6.unicomp.net - - [01/Jul/1995:00:00:06 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
199.120.110.21 - - [01/Jul/1995:00:00:09 -0400] "GET /shuttle/missions/sts-73/mission-sts-73.html HTTP/1.0" 200 4085
burger.letters.com - - [01/Jul/1995:00:00:11 -0400] "GET /shuttle/countdown/liftoff.html HTTP/1.0" 304 0
199.120.110.21 - - [01/Jul/1995:00:00:11 -0400] "GET /shuttle/missions/sts-73/sts-73-patch-small.gif HTTP/1.0" 200 4179
burger.letters.com - - [01/Jul/1995:00:00:12 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 304 0
burger.letters.com - - [01/Jul/1995:00:00:12 -0400] "GET /shuttle/countdown/video/livevideo.gif HTTP/1.0" 200 0
205.212.115.106 - - [01/Jul/1995:00:00:12 -0400] "GET /shuttle/countdown/countdown.html HTTP/1.0" 200 3985
d104.aa.net - - [01/Jul/1995:00:00:13 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
129.94.144.152 - - [01/Jul/1995:00:00:13 -0400] "GET / HTTP/1.0" 200 7074
unicomp6.unicomp.net - - [01/Jul/1995:00:00:14 -0400] "GET /shuttle/countdown/count.gif HTTP/1.0" 200 40310
unicomp6.unicomp.net - - [01/Jul/1995:00:00:14 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 200 786
unicomp6.unicomp.net - - [01/Jul/1995:00:00:14 -0400] "GET /images/KSC-logosmall.gif HTTP/1.0" 200 1204
d104.aa.net - - [01/Jul/1995:00:00:15 -0400] "GET /shuttle/countdown/count.gif HTTP/1.0" 200 40310
d104.aa.net - - [01/Jul/1995:00:00:15 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 200 786
d104.aa.net - - [01/Jul/1995:00:00:15 -0400] "GET /images/KSC-logosmall.gif HTTP/1.0" 200 1204
129.94.144.152 - - [01/Jul/1995:00:00:15 -0400] "GET /images/ksclogo-medium.gif HTTP/1.0" 304 0
199.120.110.21 - - [01/Jul/1995:00:00:17 -0400] "GET /images/launch-logo.gif HTTP/1.0" 200 1713
ppptp-0.cs.nott.ac.uk - - [01/Jul/1995:00:00:17 -0400] "GET / HTTP/1.0" 200 7074
129.94.144.152 - - [01/Jul/1995:00:00:17 -0400] "GET /history/apollo/images/apollo-logo1.gif HTTP/1.0" 200 1173
199.120.110.21 - - [01/Jul/1995:00:00:18 -0400] "GET /history/apollo/images/apollo-logo1.gif HTTP/1.0" 200 1173
205.189.154.54 - - [01/Jul/1995:00:00:24 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
rjl.sw.stratus.com - - [01/Jul/1995:00:00:25 -0400] "GET /shuttle/missions/sts-71/mission-sts-71.html HTTP/1.0" 200 13591
ix-sac6-20.ix.netcom.com - - [01/Jul/1995:00:00:29 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
slppp6.intermind.net - - [01/Jul/1995:00:00:30 -0400] "GET /history/apollo/apollo-13/apollo-13.html HTTP/1.0" 200 17611
163.206.89.4 - - [01/Jul/1995:00:00:32 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
163.206.89.4 - - [01/Jul/1995:00:00:34 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 200 786
163.206.89.4 - - [01/Jul/1995:00:00:34 -0400] "GET /images/KSC-logosmall.gif HTTP/1.0" 200 1204
piweba3y.prodigy.com - - [01/Jul/1995:00:00:35 -0400] "GET /images/launch-logo.gif HTTP/1.0" 200 1713
slppp6.intermind.net - - [01/Jul/1995:00:00:35 -0400] "GET /history/apollo/apollo-13/apollo-13-patch-small.gif HTTP/1.0" 200 12859
slppp6.intermind.net - - [01/Jul/1995:00:00:37 -0400] "GET /history/apollo/images/apollo-logo1.gif HTTP/1.0" 200 1173
ix-sac6-20.ix.netcom.com - - [01/Jul/1995:00:00:38 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 200 786
ix-sac6-20.ix.netcom.com - - [01/Jul/1995:00:00:39 -0400] "GET /images/KSC-logosmall.gif HTTP/1.0" 200 1204
ix-sac6-20.ix.netcom.com - - [01/Jul/1995:00:00:39 -0400] "GET /shuttle/countdown/count.gif HTTP/1.0" 200 40310
133.43.96.45 - - [01/Jul/1995:00:00:40 -0400] "GET /shuttle/missions/sts-71/mission-sts-71.html HTTP/1.0" 200 13591
205.189.154.54 - - [01/Jul/1995:00:00:40 -0400] "GET /shuttle/countdown/count.gif HTTP/1.0" 200 40310
205.189.154.54 - - [01/Jul/1995:00:00:40 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 200 786
205.189.154.54 - - [01/Jul/1995:00:00:40 -0400] "GET /images/KSC-logosmall.gif HTTP/1.0" 200 1204
mtv-ym05-18.ix.netcom.com - - [01/Jul/1995:00:00:40 -0400] "GET /images/launch-logo.gif HTTP/1.0" 200 1713
133.43.96.45 - - [01/Jul/1995:00:00:41 -0400] "GET /shuttle/missions/sts-71/sts-71-patch-small.gif HTTP/1.0" 200 5096
133.43.96.45 - - [01/Jul/1995:00:00:42 -0400] "GET /images/launch-logo.gif HTTP/1.0" 200 1713
133.43.96.45 - - [01/Jul/1995:00:00:42 -0400] "GET /history/apollo/images/apollo-logo1.gif HTTP/1.0" 200 1173
piweba3y.prodigy.com - - [01/Jul/1995:00:00:42 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
www-a1.proxy.aol.com - - [01/Jul/1995:00:00:43 -0400] "GET /shuttle/missions/sts-71/mission-sts-71.html HTTP/1.0" 200 13591
piweba3y.prodigy.com - - [01/Jul/1995:00:00:43 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 200 786
piweba3y.prodigy.com - - [01/Jul/1995:00:00:43 -0400] "GET /images/KSC-logosmall.gif HTTP/1.0" 200 1204
piweba3y.prodigy.com - - [01/Jul/1995:00:00:43 -0400] "GET /shuttle/countdown/count.gif HTTP/1.0" 200 40310
rjl.sw.stratus.com - - [01/Jul/1995:00:00:44 -0400] "GET /images/launch-logo.gif HTTP/1.0" 200 1713
rjl.sw.stratus.com - - [01/Jul/1995:00:00:44 -0400] "GET /shuttle/missions/sts-71/sts-71-patch-small.gif HTTP/1.0" 200 5096
rjl.sw.stratus.com - - [01/Jul/1995:00:00:45 -0400] "GET /history/apollo/images/apollo-logo1.gif HTTP/1.0" 200 1173
sfi.com - - [01/Jul/1995:00:00:45 -0400] "GET /shuttle/missions/sts-71/mission-sts-71.html HTTP/1.0" 200 13591
205.252.144.203 - - [01/Jul/1995:00:00:46 -0400] "GET /shuttle/missions/sts-71/mission-sts-71.html HTTP/1.0" 200 13591
LOGEOF
# Repeat the log content to simulate a larger file (~2000 lines)
for i in {1..40}; do
    cat "$PROJECT_DIR/src/main/resources/access.log" >> "$PROJECT_DIR/src/main/resources/access_temp.log"
done
mv "$PROJECT_DIR/src/main/resources/access_temp.log" "$PROJECT_DIR/src/main/resources/access.log"
echo "Created log file with $(wc -l < $PROJECT_DIR/src/main/resources/access.log) lines"

# 7. Set Ownership
chown -R ga:ga "$PROJECT_DIR"

# 8. Start IntelliJ and load project
echo "Starting IntelliJ..."
setup_intellij_project "$PROJECT_DIR" "log-analyzer" 120

# 9. Record Task Start Time
date +%s > /tmp/task_start_time.txt
echo "Setup complete."

# 10. Initial Screenshot
take_screenshot /tmp/task_start.png