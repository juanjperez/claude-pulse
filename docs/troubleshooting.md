# Troubleshooting

Common issues and their solutions.

## Quick Diagnostics

Run these commands to check the status of all services:

```bash
# Check all services
launchctl list | grep otelcol
brew services list | grep -E "prometheus|grafana"

# Verify ports are listening
lsof -i :4317  # OTel gRPC receiver
lsof -i :9090  # Prometheus UI/API
lsof -i :9091  # OTel Prometheus exporter
lsof -i :65432  # Grafana
```

## No Data in Grafana

### Symptoms
- Dashboard shows "No data" for all panels
- Graphs are empty

### Solutions

1. **Verify Claude Code telemetry is enabled:**
   ```bash
   env | grep -E "CLAUDE_CODE|OTEL"
   ```
   You should see:
   ```
   CLAUDE_CODE_ENABLE_TELEMETRY=1
   OTEL_METRICS_EXPORTER=otlp
   OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
   ```

2. **Check OTel Collector is running:**
   ```bash
   pgrep otelcol
   ```

3. **Check Prometheus targets:**
   Open http://localhost:9090/targets - both targets should show "UP"

4. **Verify data is flowing:**
   ```bash
   curl -s http://localhost:9091/metrics | grep claude_code
   ```

5. **Check time range in Grafana:**
   Make sure the dashboard time range includes when you used Claude Code

6. **Restart Claude Code:**
   Environment variables are read at startup. Open a new terminal and run `claude` again.

## Services Not Starting

### OTel Collector

```bash
# Check logs
cat ~/.local/share/otelcol/logs/otelcol.err

# Force restart
launchctl kickstart -k gui/$(id -u)/com.otelcol.claude-code

# Reload completely
launchctl bootout gui/$(id -u)/com.otelcol.claude-code 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.otelcol.claude-code.plist
launchctl kickstart gui/$(id -u)/com.otelcol.claude-code
```

### Prometheus

```bash
# Check logs
cat /opt/homebrew/var/log/prometheus.err.log

# Restart
brew services restart prometheus

# Force start
launchctl kickstart -k gui/$(id -u)/homebrew.mxcl.prometheus
```

### Grafana

```bash
# Check logs
cat /opt/homebrew/var/log/grafana/grafana.log

# Restart
brew services restart grafana

# If "Bootstrap failed" error
brew services stop grafana
launchctl bootout gui/$(id -u)/homebrew.mxcl.grafana 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/homebrew.mxcl.grafana.plist
launchctl kickstart -k gui/$(id -u)/homebrew.mxcl.grafana
```

## Data Appears to Reset

### Symptoms
- Metrics suddenly drop to zero
- Historical data disappears

### Cause
The OTel Collector was likely restarted. In-memory counters reset, but Prometheus keeps historical data.

### Solutions

1. **Check JSON logs for historical data:**
   ```bash
   cat ~/.local/share/otelcol/logs/metrics.jsonl | \
     jq -r '.resourceMetrics[].scopeMetrics[].metrics[] | select(.name == "claude_code.cost.usage") | .sum.dataPoints[].asDouble' | \
     awk '{sum += $1} END {print "Total: $" sum}'
   ```

2. **Replay data from JSON logs:**
   ```bash
   ./scripts/replay-metrics.sh
   ```

## Port Conflicts

### Symptoms
- Services fail to start
- "Address already in use" errors

### Solutions

```bash
# Find what's using a port
lsof -i :PORT_NUMBER

# Kill the process
kill -9 PID
```

Default ports:
- 4317: OTel Collector gRPC
- 4318: OTel Collector HTTP
- 9090: Prometheus
- 9091: OTel Prometheus exporter
- 65432: Grafana

## Grafana Login Issues

### Forgot Password

```bash
GF_PATHS_DATA=/opt/homebrew/var/lib/grafana \
  /opt/homebrew/opt/grafana/bin/grafana cli \
  --homepath /opt/homebrew/opt/grafana/share/grafana \
  admin reset-admin-password YOUR_NEW_PASSWORD

# Restart Grafana
launchctl kickstart -k gui/$(id -u)/homebrew.mxcl.grafana
```

### Locked Out (Too Many Failed Attempts)

1. Edit `/opt/homebrew/etc/grafana/grafana.ini`
2. Find and set:
   ```ini
   disable_brute_force_login_protection = true
   ```
3. Reset password (see above)
4. Restart Grafana
5. Re-enable brute force protection after successful login

## High Cost/Lines Per Hour Values

### Symptoms
- "Cost per Hour" shows unrealistic values (e.g., $500/hour)
- "Lines per Hour" shows very high values

### Cause
The active time metric might be missing or stale, causing division by a very small number.

### Solutions

1. **Check active time data:**
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=sum(claude_code_claude_code_active_time_total_seconds_total)'
   ```

2. **Verify the queries use max_over_time consistently:**
   Both numerator and denominator should use `max_over_time[$__range]`

## Verify Data Consistency

Compare JSON logs with Prometheus:

```bash
# JSON logs total
python3 << 'EOF'
import json, os
from collections import defaultdict
costs = defaultdict(float)
with open(os.path.expanduser("~/.local/share/otelcol/logs/metrics.jsonl")) as f:
    for line in f:
        try:
            data = json.loads(line)
            for rm in data.get('resourceMetrics', []):
                for sm in rm.get('scopeMetrics', []):
                    for m in sm.get('metrics', []):
                        if m.get('name') == 'claude_code.cost.usage' and 'sum' in m:
                            for dp in m['sum'].get('dataPoints', []):
                                attrs = {a['key']: a['value'].get('stringValue', '') for a in dp.get('attributes', [])}
                                key = (attrs.get('session.id', ''), attrs.get('model', ''))
                                costs[key] = max(costs[key], dp.get('asDouble', 0))
        except: pass
print(f"JSON Total: ${sum(costs.values()):.2f}")
EOF

# Prometheus total
curl -s 'http://localhost:9090/api/v1/query?query=sum(max_over_time(claude_code_claude_code_cost_usage_USD_total[7d]))' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); r=d['data']['result']; print(f'Prometheus Total: \${float(r[0][\"value\"][1]):.2f}' if r else 'No data')"
```

Prometheus should be >= JSON (includes live data accumulated since last JSON flush).

## API Reference for Diagnosis

### Prometheus API (port 9090)

| Endpoint | Description |
|----------|-------------|
| `GET /api/v1/query?query=PROMQL` | Execute instant query |
| `GET /api/v1/query_range?query=PROMQL&start=TS&end=TS&step=S` | Execute range query |
| `GET /api/v1/label/__name__/values` | List all metric names |
| `GET /api/v1/targets` | Show scrape targets and health |
| `GET /api/v1/status/runtimeinfo` | Prometheus runtime info |

Example:
```bash
# Query total cost
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(max_over_time(claude_code_claude_code_cost_usage_USD_total[7d]))'
```

### Grafana API (port 65432)

Default credentials: `admin:admin`

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check |
| `GET /api/datasources` | List datasources |
| `GET /api/search?type=dash-db` | List dashboards |
| `GET /api/dashboards/uid/UID` | Get dashboard by UID |
| `POST /api/dashboards/db` | Create/update dashboard |

Example:
```bash
# Export dashboard
curl -s -u admin:admin 'http://localhost:65432/api/dashboards/uid/claude-code-usage' | \
  python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['dashboard'], indent=2))"

# Import dashboard
curl -s -X POST -u admin:admin \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $(cat dashboard.json), \"overwrite\": true}" \
  'http://localhost:65432/api/dashboards/db'
```

### OTel Collector Metrics (port 9091)

```bash
# View all Claude Code metrics being exported
curl -s http://localhost:9091/metrics | grep claude_code
```
