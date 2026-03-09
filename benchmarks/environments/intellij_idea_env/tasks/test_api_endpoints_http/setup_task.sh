#!/bin/bash
echo "=== Setting up API Testing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
rm -f /tmp/library_server_access.log

# 1. Create the Project Directory structure manually
# (Simulating a fresh project)
PROJECT_DIR="/home/ga/IdeaProjects/LibraryClient"
mkdir -p "$PROJECT_DIR/src"
mkdir -p "$PROJECT_DIR/.idea"
chown -R ga:ga "/home/ga/IdeaProjects"

# 2. Create the Background Server Code
# Using Java's built-in HttpServer to avoid external dependencies
cat > /tmp/SimpleLibraryServer.java << 'EOF'
import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;
import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.time.Instant;

public class SimpleLibraryServer {
    private static final List<String> books = new ArrayList<>();
    private static final String LOG_FILE = "/tmp/library_server_access.log";

    public static void main(String[] args) throws IOException {
        // Pre-load data
        books.add("{\"id\": 1, \"title\": \"Design Patterns\", \"author\": \"Gamma et al.\", \"year\": 1994}");
        books.add("{\"id\": 2, \"title\": \"Clean Code\", \"author\": \"Robert C. Martin\", \"year\": 2008}");
        books.add("{\"id\": 3, \"title\": \"The Pragmatic Programmer\", \"author\": \"Hunt & Thomas\", \"year\": 1999}");

        HttpServer server = HttpServer.create(new InetSocketAddress(8081), 0);
        server.createContext("/api/books", new BooksHandler());
        server.setExecutor(null);
        server.start();
        System.out.println("Server started on port 8081");
        log("SERVER_STARTED", "Port 8081");
    }

    private static void log(String type, String details) {
        try (FileWriter fw = new FileWriter(LOG_FILE, true);
             BufferedWriter bw = new BufferedWriter(fw)) {
            bw.write(Instant.now().toString() + "\t" + type + "\t" + details);
            bw.newLine();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    static class BooksHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange t) throws IOException {
            String method = t.getRequestMethod();
            String path = t.getRequestURI().getPath();
            
            // Log the request for verification
            log("REQUEST", method + " " + path);

            if ("GET".equals(method)) {
                String response = "[" + String.join(",", books) + "]";
                sendResponse(t, 200, response);
            } else if ("POST".equals(method)) {
                // Read body
                InputStreamReader isr = new InputStreamReader(t.getRequestBody(), StandardCharsets.UTF_8);
                BufferedReader br = new BufferedReader(isr);
                StringBuilder body = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) body.append(line);
                
                String bodyStr = body.toString();
                log("BODY", bodyStr); // Log body for verification

                if (bodyStr.contains("{") && bodyStr.contains("}")) {
                    books.add(bodyStr);
                    sendResponse(t, 201, "{\"status\": \"Created\", \"id\": " + books.size() + "}");
                } else {
                    sendResponse(t, 400, "{\"error\": \"Invalid JSON\"}");
                }
            } else {
                sendResponse(t, 405, "Method Not Allowed");
            }
        }

        private void sendResponse(HttpExchange t, int statusCode, String response) throws IOException {
            t.getResponseHeaders().set("Content-Type", "application/json");
            byte[] bytes = response.getBytes(StandardCharsets.UTF_8);
            t.sendResponseHeaders(statusCode, bytes.length);
            OutputStream os = t.getResponseBody();
            os.write(bytes);
            os.close();
        }
    }
}
EOF

# 3. Compile and Run the Server
echo "Compiling and starting background server..."
javac /tmp/SimpleLibraryServer.java
nohup java -cp /tmp SimpleLibraryServer > /tmp/server_stdout.log 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > /tmp/server_pid.txt

# Wait for server port
for i in {1..10}; do
    if netstat -tulpn | grep -q 8081; then
        echo "Server is listening on 8081"
        break
    fi
    sleep 1
done

# 4. Open IntelliJ with the empty project
echo "Opening IntelliJ..."
setup_intellij_project "$PROJECT_DIR" "LibraryClient" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="