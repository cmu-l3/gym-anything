#!/bin/bash
echo "=== Exporting assign_key_card_to_employee result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -f "floreantpos.jar" > /dev/null && echo "true" || echo "false")

# --------------------------------------------------------------------------
# Verify Database State (Java)
# --------------------------------------------------------------------------

# We need to momentarily stop Floreant or use a read-only connection if possible.
# Derby embedded usually locks the DB. For verification reliability, we stop the app.
# In a real scenario, we might try to query while running if server mode was enabled,
# but Floreant default is embedded single-user.

echo "Stopping Floreant POS for database verification..."
pkill -f "floreantpos.jar" 2>/dev/null || true
sleep 3

# Create Java Verifier
cat > /tmp/VerifyKey.java << 'JAVAEOF'
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import org.json.simple.JSONObject; // Not available, use manual JSON string construction

public class VerifyKey {
    public static void main(String[] args) {
        String dbURL = "jdbc:derby:/opt/floreantpos/database/derby-server/posdb";
        boolean userFound = false;
        String actualKey = "";
        
        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            Connection conn = DriverManager.getConnection(dbURL);
            
            PreparedStatement stmt = conn.prepareStatement("SELECT SECRET_KEY FROM USERS WHERE FIRST_NAME = ? AND LAST_NAME = ?");
            stmt.setString(1, "John");
            stmt.setString(2, "Doe");
            ResultSet rs = stmt.executeQuery();
            
            if (rs.next()) {
                userFound = true;
                actualKey = rs.getString("SECRET_KEY");
                if (actualKey == null) actualKey = "";
            }
            conn.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
        
        // Output JSON
        System.out.print("{");
        System.out.print("\"user_found\": " + userFound + ",");
        System.out.print("\"actual_key\": \"" + actualKey.trim() + "\"");
        System.out.print("}");
    }
}
JAVAEOF

# Compile and Run Verifier
DERBY_JAR=$(find /opt/floreantpos -name "derby.jar" | head -1)
DB_RESULT="{}"

if [ -f "$DERBY_JAR" ]; then
    cd /tmp
    /usr/lib/jvm/java-11-openjdk-amd64/bin/javac VerifyKey.java
    # Run and capture output
    DB_RESULT=$(/usr/lib/jvm/java-11-openjdk-amd64/bin/java -cp ".:$DERBY_JAR" VerifyKey)
fi

echo "DB Result: $DB_RESULT"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_result": $DB_RESULT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="