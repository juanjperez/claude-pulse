#!/bin/bash
# Replay metrics from JSON logs back into Prometheus
# Usage: ./replay-metrics.sh
#
# This script extracts historical metrics from the JSON log files
# and imports them into Prometheus as TSDB blocks.

set -e

METRICS_FILE="$HOME/.local/share/otelcol/logs/metrics.jsonl"
PROMETHEUS_DATA="/opt/homebrew/var/prometheus"
TEMP_DIR=$(mktemp -d)
OPENMETRICS_FILE="$TEMP_DIR/metrics.txt"

echo "═══════════════════════════════════════════════════════════════"
echo "  Replaying metrics from JSON logs to Prometheus"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ ! -f "$METRICS_FILE" ]; then
    echo "Error: Metrics file not found: $METRICS_FILE"
    exit 1
fi

# Check if promtool is available
if ! command -v promtool &> /dev/null; then
    echo "Error: promtool not found. Install with: brew install prometheus"
    exit 1
fi

echo "Step 1: Extracting metrics from JSON logs..."

# Parse JSON and convert to OpenMetrics format
python3 << 'PYTHON_SCRIPT' > "$OPENMETRICS_FILE"
import json
import sys
import os
import re
from collections import defaultdict

metrics_file = os.path.expanduser("~/.local/share/otelcol/logs/metrics.jsonl")

# Metric name mapping to match what OTel Collector exports
METRIC_SUFFIXES = {
    'claude_code.cost.usage': '_USD_total',
    'claude_code.token.usage': '_tokens_total',
    'claude_code.session.count': '_total',
    'claude_code.lines_of_code.count': '_total',
    'claude_code.commit.count': '_total',
    'claude_code.pull_request.count': '_total',
    'claude_code.active_time.total': '_seconds_total',
    'claude_code.code_edit_tool.decision': '_total',
}

def sanitize_label_name(name):
    """Convert label name to valid Prometheus format"""
    return re.sub(r'[^a-zA-Z0-9_]', '_', name)

def sanitize_metric_name(name):
    """Convert metric name to valid Prometheus format"""
    return re.sub(r'[^a-zA-Z0-9_:]', '_', name)

# Store all data points
all_points = []

with open(metrics_file, 'r') as f:
    for line in f:
        if not line.strip():
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        for rm in data.get('resourceMetrics', []):
            # Get resource attributes
            resource_attrs = {}
            for attr in rm.get('resource', {}).get('attributes', []):
                key = sanitize_label_name(attr.get('key', ''))
                val = attr.get('value', {})
                if 'stringValue' in val and key:
                    resource_attrs[key] = val['stringValue']

            for sm in rm.get('scopeMetrics', []):
                for metric in sm.get('metrics', []):
                    orig_name = metric.get('name', '')

                    # Build Prometheus metric name with namespace prefix
                    prom_name = 'claude_code_' + sanitize_metric_name(orig_name)

                    # Add appropriate suffix
                    suffix = METRIC_SUFFIXES.get(orig_name, '_total')
                    prom_name += suffix

                    # Handle sum metrics (counters)
                    if 'sum' in metric:
                        for dp in metric['sum'].get('dataPoints', []):
                            value = dp.get('asDouble', dp.get('asInt', 0))
                            timestamp_ns = int(dp.get('timeUnixNano', 0))
                            # Convert nanoseconds to seconds (float) for OpenMetrics
                            timestamp_sec = timestamp_ns / 1e9

                            if timestamp_sec == 0:
                                continue

                            # Build labels - match what OTel Collector exports
                            labels = {'job': 'claude_code'}  # Must match live data

                            # Add metric-specific attributes
                            for attr in dp.get('attributes', []):
                                key = sanitize_label_name(attr.get('key', ''))
                                val = attr.get('value', {})
                                if 'stringValue' in val and key:
                                    # Keep session_id, model, type, and other relevant labels
                                    if key in ('session_id', 'model', 'type', 'tool_name', 'decision', 'source', 'language'):
                                        labels[key] = val['stringValue']

                            # Create label string
                            if labels:
                                label_str = ','.join(f'{k}="{v}"' for k, v in sorted(labels.items()))
                                metric_key = f"{prom_name}{{{label_str}}}"
                            else:
                                metric_key = prom_name

                            all_points.append((timestamp_sec, prom_name, metric_key, value))

# Sort by timestamp
all_points.sort(key=lambda x: x[0])

# Print TYPE declarations first
declared_types = set()
for ts, metric_name, metric_key, val in all_points:
    if metric_name not in declared_types:
        print(f"# TYPE {metric_name} counter")
        declared_types.add(metric_name)

# Print data points with timestamps in seconds (float)
for ts, metric_name, metric_key, val in all_points:
    # OpenMetrics uses seconds with decimal precision
    print(f"{metric_key} {val} {ts:.3f}")

print("# EOF")
PYTHON_SCRIPT

LINE_COUNT=$(wc -l < "$OPENMETRICS_FILE")
echo "  Extracted $LINE_COUNT lines of metrics"

echo ""
echo "Step 2: Creating TSDB blocks with promtool..."

cd "$TEMP_DIR"
if ! promtool tsdb create-blocks-from openmetrics "$OPENMETRICS_FILE" "$TEMP_DIR/blocks" 2>&1; then
    echo ""
    echo "Error creating blocks."
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""
echo "Step 3: Stopping Prometheus..."
brew services stop prometheus 2>/dev/null || true
sleep 2

echo ""
echo "Step 4: Copying blocks to Prometheus data directory..."

BLOCKS_FOUND=0
for block in "$TEMP_DIR/blocks"/*; do
    if [ -d "$block" ]; then
        BLOCK_NAME=$(basename "$block")
        echo "  Copying block: $BLOCK_NAME"
        cp -r "$block" "$PROMETHEUS_DATA/"
        BLOCKS_FOUND=$((BLOCKS_FOUND + 1))
    fi
done

if [ $BLOCKS_FOUND -eq 0 ]; then
    echo "  No blocks were created."
else
    echo "  Copied $BLOCKS_FOUND block(s)"
fi

echo ""
echo "Step 5: Starting Prometheus..."
brew services start prometheus
sleep 5

# Verify Prometheus is running
if curl -s http://localhost:9090/api/v1/status/runtimeinfo > /dev/null 2>&1; then
    echo "  Prometheus is running"
else
    echo "  Trying to force start..."
    launchctl kickstart -k gui/$(id -u)/homebrew.mxcl.prometheus 2>/dev/null || true
    sleep 3
fi

echo ""
echo "Step 6: Cleanup..."
rm -rf "$TEMP_DIR"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Done! Refresh Grafana to see the restored data."
echo "═══════════════════════════════════════════════════════════════"
