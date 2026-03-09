#!/bin/bash
echo "=== Exporting verify_menu_order_workflow result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (before killing app)
take_screenshot /tmp/task_final.png

# 2. Kill Floreant to unlock the embedded Derby database
# (Embedded Derby locks the DB files; we must stop the app to query them via JDBC)
echo "Stopping Floreant POS to unlock database..."
kill_floreant
sleep 3

# 3. Compile and Run Java DB Verifier
# We create a small Java program to query the Derby DB and output JSON
echo "Preparing DB verification tool..."

CAT_JAR=$(ls /opt/floreantpos/lib/derby*.jar 2>/dev/null | tr '\n' ':')
CLASSPATH=".:$CAT_JAR"

cat > CheckDb.java << 'EOF'
import java.sql.*;
import java.util.*;
import java.io.*;
import java.text.SimpleDateFormat;

public class CheckDb {
    public static void main(String[] args) {
        String dbPath = "/opt/floreantpos/database/derby-server";
        String jdbcUrl = "jdbc:derby:" + dbPath + ";create=false";
        long taskStartTime = 0;
        
        try {
             File timeFile = new File("/tmp/task_start_time.txt");
             if (timeFile.exists()) {
                 Scanner scanner = new Scanner(timeFile);
                 if (scanner.hasNextLong()) {
                     taskStartTime = scanner.nextLong() * 1000; // Convert to ms
                 }
                 scanner.close();
             }
        } catch (Exception e) { e.printStackTrace(); }

        try (Connection conn = DriverManager.getConnection(jdbcUrl);
             Statement stmt = conn.createStatement()) {
            
            System.out.println("{");
            
            // 1. Check Modifier Group
            boolean modGroupExists = false;
            try (ResultSet rs = stmt.executeQuery("SELECT * FROM MENU_MODIFIER_GROUP WHERE NAME = 'Burger Toppings'")) {
                if (rs.next()) modGroupExists = true;
            }
            System.out.println("  \"mod_group_exists\": " + modGroupExists + ",");
            
            // 2. Check Modifiers
            List<String> modifiersFound = new ArrayList<>();
            try (ResultSet rs = stmt.executeQuery("SELECT NAME, PRICE FROM MENU_MODIFIER WHERE NAME IN ('Bacon', 'Avocado', 'Extra Cheese')")) {
                while (rs.next()) {
                    modifiersFound.add(String.format("{\"name\": \"%s\", \"price\": %.2f}", rs.getString("NAME"), rs.getDouble("PRICE")));
                }
            }
            System.out.println("  \"modifiers_found\": " + modifiersFound.toString() + ",");

            // 3. Check Menu Item
            boolean itemExists = false;
            double itemPrice = 0.0;
            try (ResultSet rs = stmt.executeQuery("SELECT * FROM MENU_ITEM WHERE NAME = 'Build-Your-Own Burger'")) {
                if (rs.next()) {
                    itemExists = true;
                    itemPrice = rs.getDouble("PRICE");
                }
            }
            System.out.println("  \"menu_item_exists\": " + itemExists + ",");
            System.out.println("  \"menu_item_price\": " + itemPrice + ",");

            // 4. Check Ticket (Order)
            // Look for tickets created after task start
            // Note: Floreant stores dates as Timestamp or Long. Adjust query as needed.
            // Derby TIMESTAMP comparison syntax:
            // We'll just fetch recent tickets and filter in Java to be safe about formats
            
            boolean ticketFound = false;
            double ticketTotal = 0.0;
            List<String> ticketItems = new ArrayList<>();
            
            try (ResultSet rs = stmt.executeQuery("SELECT ID, CREATE_DATE, TOTAL_AMOUNT FROM TICKET ORDER BY ID DESC FETCH FIRST 10 ROWS ONLY")) {
                while (rs.next()) {
                    Timestamp ts = rs.getTimestamp("CREATE_DATE");
                    if (ts != null && ts.getTime() > taskStartTime) {
                        // Found a candidate ticket
                        int ticketId = rs.getInt("ID");
                        
                        // Check if this ticket contains our burger
                        Statement subStmt = conn.createStatement();
                        ResultSet subRs = subStmt.executeQuery("SELECT NAME FROM TICKET_ITEM WHERE TICKET_ID = " + ticketId);
                        boolean hasBurger = false;
                        while(subRs.next()) {
                            String iName = subRs.getString("NAME");
                            ticketItems.add("\"" + iName + "\"");
                            if (iName.contains("Build-Your-Own Burger")) hasBurger = true;
                        }
                        subRs.close();
                        subStmt.close();
                        
                        if (hasBurger) {
                            ticketFound = true;
                            ticketTotal = rs.getDouble("TOTAL_AMOUNT");
                            break; // Stop at the first valid ticket found
                        }
                    }
                }
            }
            System.out.println("  \"ticket_found\": " + ticketFound + ",");
            System.out.println("  \"ticket_total\": " + ticketTotal + ",");
            System.out.println("  \"ticket_items\": " + ticketItems.toString());
            
            System.out.println("}");

        } catch (SQLException e) {
            System.out.println("{ \"error\": \"" + e.getMessage().replace("\"", "'") + "\" }");
            e.printStackTrace();
        }
    }
}
EOF

# Compile and run
javac -cp "$CLASSPATH" CheckDb.java
if [ $? -eq 0 ]; then
    echo "Running DB Verification..."
    java -cp "$CLASSPATH" CheckDb > /tmp/db_result.json
else
    echo "Compilation failed. Creating fallback result."
    echo "{ \"error\": \"Compilation failed\" }" > /tmp/db_result.json
fi

# Merge results
cat > /tmp/task_result.json << EOF
{
    "db_verification": $(cat /tmp/db_result.json),
    "timestamp": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Cleanup
rm -f CheckDb.java CheckDb.class

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="