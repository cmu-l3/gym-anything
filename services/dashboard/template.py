"""
Complete Master Dashboard Template with all features:
- Activity log
- Endpoint statistics with latencies
- Timeline charts
- Per-environment details
- System health
"""

DASHBOARD_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gym-Anything Master Dashboard</title>

    <!-- Bootstrap 5 CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">

    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">

    <!-- Chart.js -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>

    <style>
        :root {
            --primary-color: #0d6efd;
            --success-color: #198754;
            --warning-color: #ffc107;
            --danger-color: #dc3545;
            --info-color: #0dcaf0;
            --dark-bg: #212529;
            --card-bg: #ffffff;
        }

        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }

        .dashboard-container {
            background-color: #f8f9fa;
            min-height: 100vh;
            padding: 20px;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 15px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
        }

        .header h1 {
            font-size: 2.5rem;
            font-weight: 700;
            margin-bottom: 10px;
        }

        .stat-card {
            background: var(--card-bg);
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.08);
            transition: transform 0.3s, box-shadow 0.3s;
            margin-bottom: 20px;
            position: relative;
            overflow: hidden;
        }

        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.15);
        }

        .stat-value {
            font-size: 2.5rem;
            font-weight: 700;
            margin: 10px 0;
        }

        .stat-label {
            color: #6c757d;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .stat-icon {
            font-size: 2.5rem;
            opacity: 0.2;
            position: absolute;
            right: 20px;
            top: 20px;
        }

        .section-card {
            background: var(--card-bg);
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.08);
            margin-bottom: 25px;
        }

        .section-title {
            font-size: 1.3rem;
            font-weight: 600;
            margin-bottom: 20px;
            color: #495057;
        }

        .data-table {
            width: 100%;
            font-size: 0.9rem;
        }

        .data-table th {
            background-color: #f1f3f5;
            font-weight: 600;
            padding: 10px;
            border: none;
            white-space: nowrap;
        }

        .data-table td {
            padding: 10px;
            border-bottom: 1px solid #e9ecef;
            vertical-align: middle;
        }

        .data-table tr:hover {
            background-color: #f8f9fa;
        }

        .status-badge {
            padding: 4px 10px;
            border-radius: 20px;
            font-weight: 600;
            font-size: 0.75rem;
        }

        .status-healthy { background-color: #d4edda; color: #155724; }
        .status-unhealthy { background-color: #fff3cd; color: #856404; }
        .status-dead { background-color: #f8d7da; color: #721c24; }
        .status-draining { background-color: #d1ecf1; color: #0c5460; }

        .refresh-indicator {
            display: inline-block;
            margin-left: 10px;
            color: rgba(255,255,255,0.8);
            font-size: 0.9rem;
        }

        .chart-container {
            position: relative;
            height: 280px;
        }

        .activity-log {
            max-height: 400px;
            overflow-y: auto;
        }

        .activity-item {
            padding: 10px 12px;
            border-left: 4px solid #dee2e6;
            margin-bottom: 8px;
            background-color: #f8f9fa;
            border-radius: 0 5px 5px 0;
            font-size: 0.85rem;
        }

        .activity-item.env_created { border-left-color: var(--primary-color); }
        .activity-item.env_closed { border-left-color: var(--warning-color); }
        .activity-item.env_reset { border-left-color: var(--info-color); }
        .activity-item.request_error { border-left-color: var(--danger-color); background-color: #fff5f5; }
        .activity-item.worker_registered { border-left-color: var(--success-color); }
        .activity-item.worker_deregistered { border-left-color: var(--danger-color); }

        .progress-thin { height: 6px; border-radius: 3px; }

        .action-btn {
            padding: 3px 8px;
            font-size: 0.75rem;
            border-radius: 4px;
            margin-right: 3px;
        }

        .latency-good { color: var(--success-color); }
        .latency-warn { color: var(--warning-color); }
        .latency-bad { color: var(--danger-color); }

        .worker-id-cell {
            max-width: 120px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-family: monospace;
            font-size: 0.8rem;
        }

        .env-id-cell {
            max-width: 180px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-family: monospace;
            font-size: 0.8rem;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }

        .updating-pulse {
            animation: pulse 1.5s ease-in-out infinite;
        }

        .health-indicator {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            display: inline-block;
            margin-right: 6px;
        }

        .health-good { background-color: var(--success-color); }
        .health-warning { background-color: var(--warning-color); }
        .health-critical { background-color: var(--danger-color); }

        .nav-tabs .nav-link {
            color: #495057;
            border: none;
            padding: 10px 20px;
        }

        .nav-tabs .nav-link.active {
            background-color: #667eea;
            color: white;
            border-radius: 8px 8px 0 0;
        }

        .tab-content {
            border: 1px solid #dee2e6;
            border-top: none;
            border-radius: 0 0 8px 8px;
            padding: 20px;
            background: white;
        }

        @media (max-width: 768px) {
            .stat-value { font-size: 1.8rem; }
            .header h1 { font-size: 1.5rem; }
            .chart-container { height: 220px; }
        }
    </style>
</head>
<body>
    <div class="dashboard-container">
        <!-- Header -->
        <div class="header">
            <div class="d-flex justify-content-between align-items-center flex-wrap">
                <div>
                    <h1><i class="bi bi-diagram-3-fill"></i> Gym-Anything Master</h1>
                    <p class="mb-0">Distributed Environment Orchestration Dashboard</p>
                </div>
                <div class="d-flex gap-3 align-items-center flex-wrap mt-2 mt-md-0">
                    <span class="refresh-indicator" id="refreshIndicator">
                        <i class="bi bi-arrow-clockwise"></i>
                        Auto-refresh: <span id="refreshCountdown">5</span>s
                    </span>
                    <button class="btn btn-outline-light btn-sm" onclick="refreshData()">
                        <i class="bi bi-arrow-clockwise"></i> Refresh
                    </button>
                </div>
            </div>
        </div>

        <!-- Overview Cards Row 1 -->
        <div class="row">
            <div class="col-lg-2 col-md-4 col-sm-6">
                <div class="stat-card">
                    <i class="bi bi-server stat-icon text-primary"></i>
                    <div class="stat-label">Workers</div>
                    <div class="stat-value text-primary" id="totalWorkers">-</div>
                    <small id="workerBreakdown" class="text-muted">-</small>
                </div>
            </div>
            <div class="col-lg-2 col-md-4 col-sm-6">
                <div class="stat-card">
                    <i class="bi bi-boxes stat-icon text-success"></i>
                    <div class="stat-label">Environments</div>
                    <div class="stat-value text-success" id="totalEnvs">-</div>
                    <small class="text-muted">Capacity: <span id="envCapacity">-</span></small>
                </div>
            </div>
            <div class="col-lg-2 col-md-4 col-sm-6">
                <div class="stat-card">
                    <i class="bi bi-hdd-network stat-icon text-info"></i>
                    <div class="stat-label">Nodes</div>
                    <div class="stat-value text-info" id="totalHostnames">-</div>
                    <small class="text-muted">Physical hosts</small>
                </div>
            </div>
            <div class="col-lg-2 col-md-4 col-sm-6">
                <div class="stat-card">
                    <i class="bi bi-arrow-repeat stat-icon text-warning"></i>
                    <div class="stat-label">Requests</div>
                    <div class="stat-value text-warning" id="totalRequests">-</div>
                    <small class="text-muted">Total processed</small>
                </div>
            </div>
            <div class="col-lg-2 col-md-4 col-sm-6">
                <div class="stat-card">
                    <i class="bi bi-exclamation-triangle stat-icon text-danger"></i>
                    <div class="stat-label">Error Rate</div>
                    <div class="stat-value text-danger" id="errorRate">-</div>
                    <small class="text-muted"><span id="totalErrors">0</span> errors</small>
                </div>
            </div>
            <div class="col-lg-2 col-md-4 col-sm-6">
                <div class="stat-card">
                    <i class="bi bi-clock-history stat-icon" style="color: #6f42c1;"></i>
                    <div class="stat-label">Uptime</div>
                    <div class="stat-value" style="color: #6f42c1; font-size: 1.5rem;" id="uptime">-</div>
                    <small class="text-muted" id="lastUpdate">-</small>
                </div>
            </div>
        </div>

        <!-- Charts Row -->
        <div class="row">
            <div class="col-lg-4">
                <div class="section-card">
                    <h2 class="section-title"><i class="bi bi-graph-up-arrow"></i> Active Environments</h2>
                    <div class="chart-container">
                        <canvas id="envsTimelineChart"></canvas>
                    </div>
                </div>
            </div>
            <div class="col-lg-4">
                <div class="section-card">
                    <h2 class="section-title"><i class="bi bi-speedometer2"></i> Requests/min</h2>
                    <div class="chart-container">
                        <canvas id="requestsChart"></canvas>
                    </div>
                </div>
            </div>
            <div class="col-lg-4">
                <div class="section-card">
                    <h2 class="section-title"><i class="bi bi-bar-chart-fill"></i> Endpoint Latencies</h2>
                    <div class="chart-container">
                        <canvas id="latencyChart"></canvas>
                    </div>
                </div>
            </div>
        </div>

        <!-- Endpoint Statistics -->
        <div class="section-card">
            <h2 class="section-title">
                <i class="bi bi-speedometer"></i> Endpoint Statistics
            </h2>
            <div class="table-responsive">
                <table class="data-table table table-hover">
                    <thead>
                        <tr>
                            <th>Endpoint</th>
                            <th>Requests</th>
                            <th>Success</th>
                            <th>Errors</th>
                            <th>Error Rate</th>
                            <th>Avg Latency</th>
                            <th>P50</th>
                            <th>P95</th>
                            <th>P99</th>
                        </tr>
                    </thead>
                    <tbody id="endpointTable">
                        <tr><td colspan="9" class="text-center text-muted">No endpoint data yet</td></tr>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Tabs for Workers/Hostnames/Environments -->
        <div class="section-card">
            <ul class="nav nav-tabs" id="mainTabs" role="tablist">
                <li class="nav-item">
                    <button class="nav-link active" data-bs-toggle="tab" data-bs-target="#workersTab">
                        <i class="bi bi-cpu"></i> Workers <span class="badge bg-primary" id="workerCount">0</span>
                    </button>
                </li>
                <li class="nav-item">
                    <button class="nav-link" data-bs-toggle="tab" data-bs-target="#hostnamesTab">
                        <i class="bi bi-hdd-stack"></i> Hostnames <span class="badge bg-info" id="hostnameCount">0</span>
                    </button>
                </li>
                <li class="nav-item">
                    <button class="nav-link" data-bs-toggle="tab" data-bs-target="#envsTab">
                        <i class="bi bi-boxes"></i> Environments <span class="badge bg-success" id="envCount">0</span>
                    </button>
                </li>
            </ul>
            <div class="tab-content">
                <!-- Workers Tab -->
                <div class="tab-pane fade show active" id="workersTab">
                    <div class="table-responsive" style="max-height: 400px; overflow-y: auto;">
                        <table class="data-table table table-hover">
                            <thead>
                                <tr>
                                    <th>Worker ID</th>
                                    <th>Hostname</th>
                                    <th>Port</th>
                                    <th>Load</th>
                                    <th>CPU</th>
                                    <th>Memory</th>
                                    <th>Circuit</th>
                                    <th>Heartbeat</th>
                                    <th>Uptime</th>
                                    <th>Status</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody id="workerTable">
                                <tr><td colspan="11" class="text-center text-muted">No workers registered</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>

                <!-- Hostnames Tab -->
                <div class="tab-pane fade" id="hostnamesTab">
                    <div class="table-responsive" style="max-height: 400px; overflow-y: auto;">
                        <table class="data-table table table-hover">
                            <thead>
                                <tr>
                                    <th>Hostname</th>
                                    <th>Workers</th>
                                    <th>Environments</th>
                                    <th>Capacity</th>
                                    <th>Utilization</th>
                                    <th>Requests</th>
                                    <th>Errors</th>
                                    <th>Health</th>
                                </tr>
                            </thead>
                            <tbody id="hostnameTable">
                                <tr><td colspan="8" class="text-center text-muted">No hostnames registered</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>

                <!-- Environments Tab -->
                <div class="tab-pane fade" id="envsTab">
                    <div class="table-responsive" style="max-height: 400px; overflow-y: auto;">
                        <table class="data-table table table-hover">
                            <thead>
                                <tr>
                                    <th>Environment ID</th>
                                    <th>Worker</th>
                                    <th>Hostname</th>
                                    <th>Task ID</th>
                                    <th>Steps</th>
                                    <th>Created</th>
                                    <th>Idle Time</th>
                                    <th>Status</th>
                                </tr>
                            </thead>
                            <tbody id="envTable">
                                <tr><td colspan="8" class="text-center text-muted">No active environments</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>

        <!-- Bottom Row: Activity Log and System Health -->
        <div class="row">
            <div class="col-lg-8">
                <div class="section-card">
                    <h2 class="section-title">
                        <i class="bi bi-journal-text"></i> Activity Log
                        <span class="badge bg-secondary" id="activityCount">0</span>
                    </h2>
                    <div class="activity-log" id="activityLog">
                        <div class="text-center text-muted py-4">No activity yet</div>
                    </div>
                </div>
            </div>
            <div class="col-lg-4">
                <div class="section-card">
                    <h2 class="section-title"><i class="bi bi-heart-pulse"></i> System Health</h2>
                    <div id="systemHealth">
                        <div class="mb-3">
                            <label class="form-label fw-bold small">Cluster Capacity</label>
                            <div class="progress progress-thin mb-1">
                                <div class="progress-bar" id="capacityBar" style="width: 0%"></div>
                            </div>
                            <small class="text-muted"><span id="usedCapacity">0</span> / <span id="totalCapacity">0</span> environments</small>
                        </div>
                        <div class="mb-3">
                            <label class="form-label fw-bold small">Worker Health</label>
                            <div class="progress progress-thin mb-1">
                                <div class="progress-bar bg-success" id="healthyBar" style="width: 0%"></div>
                                <div class="progress-bar bg-warning" id="unhealthyBar" style="width: 0%"></div>
                                <div class="progress-bar bg-danger" id="deadBar" style="width: 0%"></div>
                            </div>
                            <small class="text-muted" id="healthBreakdown">-</small>
                        </div>
                        <div class="mb-3">
                            <label class="form-label fw-bold small">Circuit Breakers</label>
                            <div class="d-flex justify-content-between">
                                <span><span class="health-indicator health-good"></span><span id="circuitsOk">0</span> OK</span>
                                <span><span class="health-indicator health-critical"></span><span id="circuitsOpen">0</span> Open</span>
                            </div>
                        </div>
                        <div class="mb-3">
                            <label class="form-label fw-bold small">Environment Stats</label>
                            <div class="d-flex justify-content-between small">
                                <span>Created: <strong id="envsCreated">0</strong></span>
                                <span>Closed: <strong id="envsClosed">0</strong></span>
                            </div>
                        </div>
                        <div class="mb-3">
                            <label class="form-label fw-bold small">Draining Workers</label>
                            <div class="stat-value text-info" style="font-size: 1.5rem;" id="drainingCount">0</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Footer -->
        <div class="text-center text-muted mt-3 mb-2">
            <small>
                <i class="bi bi-info-circle"></i>
                Dashboard auto-refreshes every 5 seconds | Powered by Gym-Anything Master Server
            </small>
        </div>
    </div>

    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>

    <script>
        let charts = {};
        let countdownTimer;
        let countdownSeconds = 5;
        const REFRESH_INTERVAL = 5000;

        // Historical data
        let history = {
            timestamps: [],
            envCounts: [],
            requestCounts: [],
            lastRequestCount: 0
        };
        const MAX_HISTORY = 30;

        function initCharts() {
            // Environments timeline
            charts.envsTimeline = new Chart(document.getElementById('envsTimelineChart'), {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Active Envs',
                        data: [],
                        borderColor: '#198754',
                        backgroundColor: 'rgba(25, 135, 84, 0.1)',
                        tension: 0.4,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }
                }
            });

            // Requests per minute
            charts.requests = new Chart(document.getElementById('requestsChart'), {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Requests/min',
                        data: [],
                        borderColor: '#ffc107',
                        backgroundColor: 'rgba(255, 193, 7, 0.1)',
                        tension: 0.4,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: { y: { beginAtZero: true } }
                }
            });

            // Endpoint latency bar chart
            charts.latency = new Chart(document.getElementById('latencyChart'), {
                type: 'bar',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Avg (ms)',
                        data: [],
                        backgroundColor: 'rgba(13, 110, 253, 0.8)',
                    }, {
                        label: 'P95 (ms)',
                        data: [],
                        backgroundColor: 'rgba(255, 193, 7, 0.8)',
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { position: 'top' } },
                    scales: { y: { beginAtZero: true } }
                }
            });
        }

        function formatDuration(seconds) {
            if (seconds == null || isNaN(seconds)) return '-';
            if (seconds < 60) return Math.floor(seconds) + 's';
            if (seconds < 3600) return Math.floor(seconds / 60) + 'm ' + Math.floor(seconds % 60) + 's';
            const hours = Math.floor(seconds / 3600);
            const mins = Math.floor((seconds % 3600) / 60);
            return hours + 'h ' + mins + 'm';
        }

        function formatLatency(ms) {
            if (ms == null || isNaN(ms)) return '-';
            if (ms < 1) return '<1ms';
            if (ms < 1000) return Math.round(ms) + 'ms';
            return (ms / 1000).toFixed(2) + 's';
        }

        function getLatencyClass(ms) {
            if (ms < 100) return 'latency-good';
            if (ms < 500) return 'latency-warn';
            return 'latency-bad';
        }

        function getStatusBadge(status) {
            const badges = {
                'healthy': '<span class="status-badge status-healthy"><i class="bi bi-check-circle"></i> Healthy</span>',
                'unhealthy': '<span class="status-badge status-unhealthy"><i class="bi bi-exclamation-triangle"></i> Unhealthy</span>',
                'dead': '<span class="status-badge status-dead"><i class="bi bi-x-circle"></i> Dead</span>',
                'draining': '<span class="status-badge status-draining"><i class="bi bi-hourglass-split"></i> Draining</span>',
                'responsive': '<span class="status-badge status-healthy">Active</span>',
                'unresponsive': '<span class="status-badge status-unhealthy">Idle</span>'
            };
            return badges[status] || `<span class="status-badge">${status}</span>`;
        }

        function formatTimestamp(ts) {
            if (!ts) return '-';
            const d = new Date(ts * 1000);
            return d.toLocaleTimeString();
        }

        function getActivityClass(eventType) {
            return eventType || 'default';
        }

        async function refreshData() {
            try {
                const indicator = document.getElementById('refreshIndicator');
                indicator.classList.add('updating-pulse');

                const response = await fetch('/api/metrics');
                const data = await response.json();
                const cluster = data.cluster;
                const agg = cluster.aggregated || {};

                // Overview cards
                document.getElementById('totalWorkers').textContent = cluster.total_workers;
                document.getElementById('workerBreakdown').innerHTML =
                    `<span class="text-success">${cluster.healthy_workers}</span>/<span class="text-warning">${cluster.unhealthy_workers}</span>/<span class="text-danger">${cluster.dead_workers}</span>`;

                document.getElementById('totalEnvs').textContent = cluster.total_envs;
                document.getElementById('envCapacity').textContent = `${cluster.total_envs}/${cluster.total_capacity}`;
                document.getElementById('totalHostnames').textContent = cluster.hostname_stats.length;
                document.getElementById('totalRequests').textContent = agg.total_requests || 0;
                document.getElementById('totalErrors').textContent = agg.total_errors || 0;
                const errorRate = agg.error_rate ? (agg.error_rate * 100).toFixed(1) + '%' : '0%';
                document.getElementById('errorRate').textContent = errorRate;
                document.getElementById('uptime').textContent = formatDuration(data.master.uptime_sec);
                document.getElementById('lastUpdate').textContent = 'Updated: ' + new Date().toLocaleTimeString();

                // Update history for charts
                const now = new Date().toLocaleTimeString();
                history.timestamps.push(now);
                history.envCounts.push(cluster.total_envs);
                const reqDiff = (agg.total_requests || 0) - history.lastRequestCount;
                history.requestCounts.push(Math.max(0, reqDiff * 12)); // Approximate requests/min
                history.lastRequestCount = agg.total_requests || 0;

                if (history.timestamps.length > MAX_HISTORY) {
                    history.timestamps.shift();
                    history.envCounts.shift();
                    history.requestCounts.shift();
                }

                // Update timeline charts
                charts.envsTimeline.data.labels = history.timestamps;
                charts.envsTimeline.data.datasets[0].data = history.envCounts;
                charts.envsTimeline.update('none');

                charts.requests.data.labels = history.timestamps;
                charts.requests.data.datasets[0].data = history.requestCounts;
                charts.requests.update('none');

                // Update latency chart
                const epStats = agg.endpoint_stats || [];
                charts.latency.data.labels = epStats.slice(0, 6).map(e => e.name.replace('/envs/', '').replace('/<env_id>/', ''));
                charts.latency.data.datasets[0].data = epStats.slice(0, 6).map(e => e.avg_latency || 0);
                charts.latency.data.datasets[1].data = epStats.slice(0, 6).map(e => e.p95_latency || 0);
                charts.latency.update('none');

                // Endpoint table
                const epTable = document.getElementById('endpointTable');
                if (epStats.length === 0) {
                    epTable.innerHTML = '<tr><td colspan="9" class="text-center text-muted">No endpoint data yet</td></tr>';
                } else {
                    epTable.innerHTML = epStats.map(ep => `
                        <tr>
                            <td><code>${ep.name}</code></td>
                            <td>${ep.request_count}</td>
                            <td class="text-success">${ep.success_count}</td>
                            <td class="text-danger">${ep.error_count}</td>
                            <td>${(ep.error_rate * 100).toFixed(1)}%</td>
                            <td class="${getLatencyClass(ep.avg_latency)}">${formatLatency(ep.avg_latency)}</td>
                            <td>${formatLatency(ep.p50_latency)}</td>
                            <td>${formatLatency(ep.p95_latency)}</td>
                            <td>${formatLatency(ep.p99_latency)}</td>
                        </tr>
                    `).join('');
                }

                // Workers table
                document.getElementById('workerCount').textContent = cluster.workers.length;
                const workerTable = document.getElementById('workerTable');
                if (cluster.workers.length === 0) {
                    workerTable.innerHTML = '<tr><td colspan="11" class="text-center text-muted">No workers registered</td></tr>';
                } else {
                    workerTable.innerHTML = cluster.workers.map(w => {
                        const loadPct = w.max_envs > 0 ? Math.round(w.env_count / w.max_envs * 100) : 0;
                        const loadClass = loadPct > 80 ? 'bg-danger' : loadPct > 50 ? 'bg-warning' : 'bg-success';
                        const circuitBadge = w.circuit_open ?
                            '<span class="badge bg-danger">OPEN</span>' :
                            (w.consecutive_failures > 0 ? `<span class="badge bg-warning">${w.consecutive_failures}</span>` : '<span class="badge bg-success">OK</span>');
                        const drainBtn = w.status === 'draining' ?
                            `<button class="btn btn-success action-btn" onclick="undrainWorker('${w.worker_id}')" title="Undrain"><i class="bi bi-play-fill"></i></button>` :
                            `<button class="btn btn-warning action-btn" onclick="drainWorker('${w.worker_id}')" title="Drain"><i class="bi bi-pause-fill"></i></button>`;
                        return `
                            <tr>
                                <td class="worker-id-cell" title="${w.worker_id}">${w.worker_id.substring(0, 8)}...</td>
                                <td>${w.hostname}</td>
                                <td>${w.port}</td>
                                <td>
                                    <div class="progress progress-thin" style="width: 60px;">
                                        <div class="progress-bar ${loadClass}" style="width: ${loadPct}%"></div>
                                    </div>
                                    <small>${w.env_count}/${w.max_envs}</small>
                                </td>
                                <td>${w.cpu_percent?.toFixed(0) || 0}%</td>
                                <td>${w.memory_percent?.toFixed(0) || 0}%</td>
                                <td>${circuitBadge}</td>
                                <td>${formatDuration(w.last_heartbeat_ago_sec)} ago</td>
                                <td>${formatDuration(w.uptime_sec)}</td>
                                <td>${getStatusBadge(w.status)}</td>
                                <td>
                                    ${drainBtn}
                                    <button class="btn btn-outline-danger action-btn" onclick="removeWorker('${w.worker_id}')" title="Remove"><i class="bi bi-trash"></i></button>
                                </td>
                            </tr>
                        `;
                    }).join('');
                }

                // Hostnames table
                document.getElementById('hostnameCount').textContent = cluster.hostname_stats.length;
                const hostnameTable = document.getElementById('hostnameTable');
                if (cluster.hostname_stats.length === 0) {
                    hostnameTable.innerHTML = '<tr><td colspan="8" class="text-center text-muted">No hostnames registered</td></tr>';
                } else {
                    hostnameTable.innerHTML = cluster.hostname_stats.map(h => {
                        const util = h.capacity > 0 ? Math.round(h.env_count / h.capacity * 100) : 0;
                        const utilClass = util > 80 ? 'bg-danger' : util > 50 ? 'bg-warning' : 'bg-success';
                        const healthPct = h.worker_count > 0 ? Math.round(h.healthy_count / h.worker_count * 100) : 0;
                        return `
                            <tr>
                                <td><strong>${h.hostname}</strong></td>
                                <td><span class="badge bg-primary">${h.worker_count}</span></td>
                                <td>${h.env_count}</td>
                                <td>${h.capacity}</td>
                                <td>
                                    <div class="progress progress-thin" style="width: 60px;">
                                        <div class="progress-bar ${utilClass}" style="width: ${util}%"></div>
                                    </div>
                                    <small>${util}%</small>
                                </td>
                                <td>${h.total_requests || 0}</td>
                                <td>${h.error_count > 0 ? `<span class="badge bg-danger">${h.error_count}</span>` : '0'}</td>
                                <td><small>${h.healthy_count}/${h.worker_count} healthy</small></td>
                            </tr>
                        `;
                    }).join('');
                }

                // Environments table
                const activeEnvs = agg.active_envs || [];
                const envMappings = cluster.env_mappings || {};
                document.getElementById('envCount').textContent = Object.keys(envMappings).length;
                const envTable = document.getElementById('envTable');

                if (activeEnvs.length > 0) {
                    envTable.innerHTML = activeEnvs.map(env => {
                        const worker = cluster.workers.find(w => w.worker_id === env.worker_id);
                        return `
                            <tr>
                                <td class="env-id-cell" title="${env.env_id}">${env.env_id.substring(0, 12)}...</td>
                                <td class="worker-id-cell" title="${env.worker_id}">${env.worker_id?.substring(0, 8) || '-'}...</td>
                                <td>${env.hostname || '-'}</td>
                                <td><small>${env.task_id || '-'}</small></td>
                                <td>${env.steps || 0}</td>
                                <td><small>${formatTimestamp(env.created_at)}</small></td>
                                <td>${formatDuration(env.idle_time_sec)}</td>
                                <td>${getStatusBadge(env.responsive ? 'responsive' : 'unresponsive')}</td>
                            </tr>
                        `;
                    }).join('');
                } else if (Object.keys(envMappings).length > 0) {
                    // Fallback: show from mappings
                    envTable.innerHTML = Object.entries(envMappings).map(([envId, workerId]) => {
                        const worker = cluster.workers.find(w => w.worker_id === workerId);
                        return `
                            <tr>
                                <td class="env-id-cell" title="${envId}">${envId.substring(0, 12)}...</td>
                                <td class="worker-id-cell" title="${workerId}">${workerId.substring(0, 8)}...</td>
                                <td>${worker?.hostname || '-'}</td>
                                <td>-</td>
                                <td>-</td>
                                <td>-</td>
                                <td>-</td>
                                <td>${getStatusBadge(worker?.status || 'unknown')}</td>
                            </tr>
                        `;
                    }).join('');
                } else {
                    envTable.innerHTML = '<tr><td colspan="8" class="text-center text-muted">No active environments</td></tr>';
                }

                // Activity log
                const activityLog = agg.activity_log || [];
                document.getElementById('activityCount').textContent = activityLog.length;
                const activityDiv = document.getElementById('activityLog');
                if (activityLog.length === 0) {
                    activityDiv.innerHTML = '<div class="text-center text-muted py-4">No activity yet</div>';
                } else {
                    activityDiv.innerHTML = activityLog.slice(0, 50).map(log => {
                        const time = formatTimestamp(log.timestamp);
                        const eventType = log.event_type || 'default';
                        let details = '';
                        if (log.env_id) details += `env: ${log.env_id.substring(0, 8)}...`;
                        if (log.task_id) details += ` task: ${log.task_id}`;
                        if (log.error) details += ` <span class="text-danger">${log.error}</span>`;
                        if (log.reason) details += ` reason: ${log.reason}`;
                        return `
                            <div class="activity-item ${eventType}">
                                <div class="d-flex justify-content-between">
                                    <strong>${eventType.replace('_', ' ')}</strong>
                                    <small class="text-muted">${time}</small>
                                </div>
                                <small class="text-muted">${log.hostname || ''} ${details}</small>
                            </div>
                        `;
                    }).join('');
                }

                // System health
                const totalCap = cluster.total_capacity || 1;
                const usedPct = Math.round(cluster.total_envs / totalCap * 100);
                document.getElementById('capacityBar').style.width = usedPct + '%';
                document.getElementById('capacityBar').className = 'progress-bar ' + (usedPct > 80 ? 'bg-danger' : usedPct > 50 ? 'bg-warning' : 'bg-success');
                document.getElementById('usedCapacity').textContent = cluster.total_envs;
                document.getElementById('totalCapacity').textContent = cluster.total_capacity;

                const totalW = cluster.total_workers || 1;
                document.getElementById('healthyBar').style.width = (cluster.healthy_workers / totalW * 100) + '%';
                document.getElementById('unhealthyBar').style.width = (cluster.unhealthy_workers / totalW * 100) + '%';
                document.getElementById('deadBar').style.width = (cluster.dead_workers / totalW * 100) + '%';
                document.getElementById('healthBreakdown').textContent = `${cluster.healthy_workers} healthy, ${cluster.unhealthy_workers} unhealthy, ${cluster.dead_workers} dead`;

                document.getElementById('circuitsOk').textContent = cluster.workers.filter(w => !w.circuit_open).length;
                document.getElementById('circuitsOpen').textContent = cluster.workers.filter(w => w.circuit_open).length;
                document.getElementById('envsCreated').textContent = agg.total_envs_created || 0;
                document.getElementById('envsClosed').textContent = agg.total_envs_closed || 0;
                document.getElementById('drainingCount').textContent = cluster.draining_workers || 0;

                indicator.classList.remove('updating-pulse');
            } catch (error) {
                console.error('Failed to refresh:', error);
            }
            countdownSeconds = 5;
        }

        async function drainWorker(workerId) {
            if (!confirm('Drain worker ' + workerId.substring(0, 8) + '...?\\n\\nDraining stops new environments but continues serving existing ones.')) return;
            try {
                await fetch('/workers/drain', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({worker_id: workerId})
                });
                refreshData();
            } catch (e) { alert('Failed: ' + e); }
        }

        async function undrainWorker(workerId) {
            try {
                await fetch('/workers/undrain', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({worker_id: workerId})
                });
                refreshData();
            } catch (e) { alert('Failed: ' + e); }
        }

        async function removeWorker(workerId) {
            if (!confirm('Remove worker ' + workerId.substring(0, 8) + '...?\\n\\nThis will orphan any environments.')) return;
            try {
                await fetch('/workers/deregister', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({worker_id: workerId, reason: 'manual_remove'})
                });
                refreshData();
            } catch (e) { alert('Failed: ' + e); }
        }

        function startCountdown() {
            countdownSeconds = 5;
            if (countdownTimer) clearInterval(countdownTimer);
            countdownTimer = setInterval(() => {
                countdownSeconds--;
                document.getElementById('refreshCountdown').textContent = countdownSeconds;
                if (countdownSeconds <= 0) refreshData();
            }, 1000);
        }

        document.addEventListener('DOMContentLoaded', () => {
            initCharts();
            refreshData();
            startCountdown();
        });
    </script>
</body>
</html>
"""
