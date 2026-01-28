#!/bin/bash
# Import the dashboard.json into Grafana
# Usage: ./import-dashboard.sh [username] [password]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAFANA_URL="http://localhost:65432"
GRAFANA_USER="${1:-admin}"
GRAFANA_PASS="${2:-admin}"
DASHBOARD_FILE="$SCRIPT_DIR/../dashboard.json"

if [ ! -f "$DASHBOARD_FILE" ]; then
    echo "Error: $DASHBOARD_FILE not found"
    exit 1
fi

# Create the payload with dashboard wrapped
PAYLOAD=$(python3 -c "
import json
with open('$DASHBOARD_FILE') as f:
    dashboard = json.load(f)
payload = {
    'dashboard': dashboard,
    'message': 'Imported from dashboard.json',
    'overwrite': True
}
print(json.dumps(payload))
")

# Import to Grafana
RESPONSE=$(curl -s -X POST \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$GRAFANA_URL/api/dashboards/db")

# Check result
STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status', 'error'))" 2>/dev/null)

if [ "$STATUS" = "success" ]; then
    echo "Dashboard imported successfully!"
    echo "$RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'URL: $GRAFANA_URL{r[\"url\"]}')"
else
    echo "Error importing dashboard:"
    echo "$RESPONSE"
    exit 1
fi
