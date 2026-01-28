# Claude Code Instructions for Claude Pulse

This file provides instructions for Claude Code to diagnose, troubleshoot, and evolve the Claude Pulse monitoring system.

## Quick Diagnosis Commands

When asked to diagnose the system, run these commands:

```bash
# Check all services are running
launchctl list | grep otelcol
brew services list | grep -E "prometheus|grafana"

# Verify ports are listening
lsof -i :4317  # OTel gRPC receiver
lsof -i :9090  # Prometheus
lsof -i :9091  # OTel Prometheus exporter
lsof -i :65432 # Grafana
```

## Prometheus API

Base URL: `http://localhost:9090`

### Query Metrics

```bash
# Instant query
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=claude_code_claude_code_cost_usage_USD_total'

# Range query (last 24h, 1-minute steps)
curl -s --get 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=sum(claude_code_claude_code_cost_usage_USD_total)' \
  --data-urlencode "start=$(date -v-24H +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=60'
```

### List All Metrics

```bash
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | \
  python3 -c "import json,sys; [print(m) for m in json.load(sys.stdin)['data'] if 'claude' in m]"
```

### Check Scrape Targets

```bash
curl -s http://localhost:9090/api/v1/targets | \
  python3 -c "import json,sys; d=json.load(sys.stdin); [print(f\"{t['labels']['job']}: {t['health']}\") for t in d['data']['activeTargets']]"
```

### Common PromQL Queries

```bash
# Total cost (all time in range)
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(max_over_time(claude_code_claude_code_cost_usage_USD_total[7d]))' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"Total: \${float(d['data']['result'][0]['value'][1]):.2f}\" if d['data']['result'] else 'No data')"

# Cost by model
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum by (model) (max_over_time(claude_code_claude_code_cost_usage_USD_total[7d]))' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); [print(f\"{r['metric'].get('model','unknown')}: \${float(r['value'][1]):.2f}\") for r in d['data']['result']]"

# Active time (hours)
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(max_over_time(claude_code_claude_code_active_time_total_seconds_total[7d]))/3600' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"Active time: {float(d['data']['result'][0]['value'][1]):.2f} hours\" if d['data']['result'] else 'No data')"

# Lines of code added
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(max_over_time(claude_code_claude_code_lines_of_code_count_total{type="added"}[7d]))' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"Lines added: {int(float(d['data']['result'][0]['value'][1]))}\" if d['data']['result'] else 'No data')"

# Session count
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=count(count by (session_id) (claude_code_claude_code_session_count_total))' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"Sessions: {d['data']['result'][0]['value'][1]}\" if d['data']['result'] else 'No data')"
```

### Check Data Freshness

```bash
# When was the last data point received?
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=timestamp(claude_code_claude_code_cost_usage_USD_total)' | \
  python3 -c "import json,sys,datetime; d=json.load(sys.stdin); ts=float(d['data']['result'][0]['value'][1]) if d['data']['result'] else 0; print(f'Last update: {datetime.datetime.fromtimestamp(ts)}' if ts else 'No data')"
```

## Grafana API

Base URL: `http://localhost:65432`
Default credentials: `admin:admin`

### Export Current Dashboard

```bash
# Get dashboard by UID
curl -s -u admin:admin \
  'http://localhost:65432/api/dashboards/uid/claude-code-usage' | \
  python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['dashboard'], indent=2))" > dashboard-export.json
```

### Import/Update Dashboard

```bash
# Import dashboard.json (overwrites existing)
DASHBOARD=$(cat dashboard.json)
curl -s -X POST \
  -u admin:admin \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $DASHBOARD, \"overwrite\": true}" \
  'http://localhost:65432/api/dashboards/db'
```

Or use the provided script:

```bash
./scripts/import-dashboard.sh admin admin
```

### List All Dashboards

```bash
curl -s -u admin:admin 'http://localhost:65432/api/search?type=dash-db' | \
  python3 -c "import json,sys; [print(f\"{d['uid']}: {d['title']}\") for d in json.load(sys.stdin)]"
```

### Check Grafana Health

```bash
curl -s http://localhost:65432/api/health
```

### Get Datasources

```bash
curl -s -u admin:admin 'http://localhost:65432/api/datasources' | \
  python3 -c "import json,sys; [print(f\"{d['name']}: {d['url']}\") for d in json.load(sys.stdin)]"
```

## Evolving the Dashboard

When making changes to the dashboard:

1. **Edit dashboard.json directly** - The dashboard is stored in `dashboard.json`

2. **Test queries in Prometheus first** - Before adding to dashboard, verify queries work:
   ```bash
   curl -s --get 'http://localhost:9090/api/v1/query' \
     --data-urlencode 'query=YOUR_QUERY_HERE'
   ```

3. **Import the updated dashboard**:
   ```bash
   ./scripts/import-dashboard.sh admin admin
   ```

4. **Verify in browser** - Open http://localhost:65432 and check the panels

### Dashboard Panel Structure

Each panel in `dashboard.json` follows this structure:

```json
{
  "title": "Panel Title",
  "type": "stat",  // or "timeseries", "gauge", "table", etc.
  "targets": [
    {
      "expr": "sum(max_over_time(metric_name[$__range]))",
      "refId": "A"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "currencyUSD"  // or "short", "percent", "s", etc.
    }
  }
}
```

### Important Query Patterns

For cumulative counters (cost, tokens, lines), always use `max_over_time`:

```promql
# Correct - gets the maximum value over time range
sum(max_over_time(claude_code_claude_code_cost_usage_USD_total[$__range]))

# Wrong - will show inflated values due to counter resets
sum(claude_code_claude_code_cost_usage_USD_total)
```

For rate calculations, use consistent time functions in both numerator and denominator:

```promql
# Cost per hour of active time
sum(max_over_time(claude_code_claude_code_cost_usage_USD_total[$__range])) /
(sum(max_over_time(claude_code_claude_code_active_time_total_seconds_total[$__range])) / 3600)
```

## Data Verification

### Compare JSON Logs to Prometheus

```bash
# Get totals from JSON logs (source of truth for historical data)
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

# Get totals from Prometheus
curl -s --get 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(max_over_time(claude_code_claude_code_cost_usage_USD_total[30d]))' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"Prometheus Total: \${float(d['data']['result'][0]['value'][1]):.2f}\" if d['data']['result'] else 'No data')"
```

Prometheus should be >= JSON (includes live data since last flush).

### Replay Historical Data

If Prometheus data was lost (e.g., after restart or corruption):

```bash
./scripts/replay-metrics.sh
```

## Service Management

### Restart Services

```bash
# OTel Collector (WARNING: resets in-memory counters - data still in JSON logs)
launchctl kickstart -k gui/$(id -u)/com.otelcol.claude-code

# Prometheus (safe - data persisted to disk)
brew services restart prometheus

# Grafana (safe - dashboards persisted)
brew services restart grafana
```

### Force Start if Bootstrap Fails

```bash
# For Grafana "Bootstrap failed" errors
brew services stop grafana
launchctl bootout gui/$(id -u)/homebrew.mxcl.grafana 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/homebrew.mxcl.grafana.plist
launchctl kickstart -k gui/$(id -u)/homebrew.mxcl.grafana
```

### View Logs

```bash
# OTel Collector
tail -50 ~/.local/share/otelcol/logs/otelcol.err

# Prometheus
tail -50 /opt/homebrew/var/log/prometheus.err.log

# Grafana
tail -50 /opt/homebrew/var/log/grafana/grafana.log
```

## Metrics Reference

| Claude Code Metric | Prometheus Name | Type |
|-------------------|-----------------|------|
| `claude_code.cost.usage` | `claude_code_claude_code_cost_usage_USD_total` | Counter |
| `claude_code.token.usage` | `claude_code_claude_code_token_usage_tokens_total` | Counter |
| `claude_code.active_time.total` | `claude_code_claude_code_active_time_total_seconds_total` | Counter |
| `claude_code.session.count` | `claude_code_claude_code_session_count_total` | Counter |
| `claude_code.lines_of_code.count` | `claude_code_claude_code_lines_of_code_count_total` | Counter |
| `claude_code.commit.count` | `claude_code_claude_code_commit_count_total` | Counter |
| `claude_code.pull_request.count` | `claude_code_claude_code_pull_request_count_total` | Counter |

### Common Labels

- `model`: `claude-haiku-4-5-20251001`, `claude-sonnet-4-5-20250929`, `claude-opus-4-5-20251101`
- `type`: `input`, `output`, `cacheRead`, `cacheCreation` (for tokens); `added`, `removed` (for lines)
- `session_id`: Unique session identifier
- `job`: `claude_code` (scrape job name)

## File Locations

| File | Purpose |
|------|---------|
| `~/.config/otelcol/config.yaml` | OTel Collector configuration |
| `~/.local/share/otelcol/logs/metrics.jsonl` | JSON backup of all metrics |
| `/opt/homebrew/etc/prometheus.yml` | Prometheus scrape configuration |
| `/opt/homebrew/var/prometheus/` | Prometheus time-series data |
| `/opt/homebrew/etc/grafana/grafana.ini` | Grafana configuration |
| `/opt/homebrew/var/lib/grafana/` | Grafana data (dashboards, users) |
| `~/Library/LaunchAgents/com.otelcol.claude-code.plist` | OTel Collector service definition |
