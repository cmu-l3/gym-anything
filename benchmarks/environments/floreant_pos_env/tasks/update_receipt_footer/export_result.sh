#!/bin/bash
echo "=== Exporting update_receipt_footer results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Kill Floreant POS to release the Derby Database lock
# (Derby embedded driver cannot be accessed if another process holds the lock)
kill_floreant
sleep 3

# 3. Extract data from Derby DB using Java
# We compile a tiny Java class on the fly to query the DB
echo "Compiling DB extractor..."

cat > /tmp/GetFooter.java << 'JAVAEOF'
import java.sql.*;
import java.io.FileWriter;
import java.io.IOException;

public class GetFooter {
    public static void main(String[] args) {
        String dbPath = args[0];
        String url = "jdbc:derby:" + dbPath;
        String footer = "";
        boolean found = false;

        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            try (Connection conn = DriverManager.getConnection(url);
                 Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT TICKET_FOOTER_MESSAGE FROM RESTAURANT")) {
                
                if (rs.next()) {
                    footer = rs.getString(1);
                    if (footer == null) footer = "";
                    found = true;
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }

        // Write simple JSON output
        try (FileWriter writer = new FileWriter("/tmp/db_result.json")) {
            // Escape quotes for JSON
            String safeFooter = footer.replace("\\", "\\\\").replace("\"", "\\\"");
            writer.write(String.format("{\"found\": %b, \"footer_message\": \"%s\"}", found, safeFooter));
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
JAVAEOF

# Locate Derby JARs
DERBY_LIB="/opt/floreantpos/lib"
CLASSPATH=".:$DERBY_LIB/derby.jar:$DERBY_LIB/derbyclient.jar"
DB_PATH="/opt/floreantpos/database/derby-server/posdb"

# Compile and Run
cd /tmp
/usr/lib/jvm/java-11-openjdk-amd64/bin/javac -cp "$CLASSPATH" GetFooter.java
if [ $? -eq 0 ]; then
    echo "Running DB extractor..."
    /usr/lib/jvm/java-11-openjdk-amd64/bin/java -cp "$CLASSPATH" GetFooter "$DB_PATH"
else
    echo "Compilation failed."
    echo '{"found": false, "footer_message": "", "error": "compilation_failed"}' > /tmp/db_result.json
fi

# 4. Check if DB files were modified
DB_MODIFIED="false"
DB_DIR=$(dirname "$DB_PATH")
# Find the most recently modified file in the DB directory
LATEST_DB_FILE=$(find "$DB_DIR" -type f -printf '%T@\n' | sort -n | tail -1 | cut -d. -f1)
if [ -n "$LATEST_DB_FILE" ] && [ "$LATEST_DB_FILE" -gt "$TASK_START" ]; then
    DB_MODIFIED="true"
fi

# 5. Create Final JSON Result
DB_JSON=$(cat /tmp/db_result.json 2>/dev/null || echo '{"found":false}')

# Merge info using python for safety
python3 -c "
import json
import sys

try:
    db_data = json.loads('''$DB_JSON''')
except:
    db_data = {'found': False, 'footer_message': ''}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'db_modified_during_task': $DB_MODIFIED,
    'screenshot_path': '/tmp/task_final.png',
    'db_data': db_data
}
print(json.dumps(result))
" > /tmp/task_result.json

# Cleanup
rm -f /tmp/GetFooter.java /tmp/GetFooter.class /tmp/db_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="