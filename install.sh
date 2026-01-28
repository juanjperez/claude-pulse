#!/bin/bash
# Claude Pulse - Installation Script
# Installs OpenTelemetry Collector, Prometheus, and Grafana for Claude Code monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OTEL_VERSION="0.115.0"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      Claude Pulse Installer                    ║"
echo "║         Local monitoring for Claude Code usage metrics         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is required. Install from https://brew.sh/"
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    OTEL_ARCH="arm64"
    HOMEBREW_PREFIX="/opt/homebrew"
else
    OTEL_ARCH="amd64"
    HOMEBREW_PREFIX="/usr/local"
fi

echo "Detected architecture: $ARCH"
echo "Homebrew prefix: $HOMEBREW_PREFIX"
echo ""

# Step 1: Install Prometheus and Grafana
echo "═══════════════════════════════════════════════════════════════"
echo "Step 1: Installing Prometheus and Grafana..."
echo "═══════════════════════════════════════════════════════════════"

brew install prometheus grafana 2>/dev/null || brew upgrade prometheus grafana 2>/dev/null || true
echo "✓ Prometheus and Grafana installed"

# Step 2: Install OpenTelemetry Collector
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 2: Installing OpenTelemetry Collector..."
echo "═══════════════════════════════════════════════════════════════"

mkdir -p ~/.local/bin
mkdir -p ~/.config/otelcol
mkdir -p ~/.local/share/otelcol/logs

if [ ! -f ~/.local/bin/otelcol-contrib ] || [ "$1" = "--force" ]; then
    echo "Downloading OTel Collector v${OTEL_VERSION}..."
    OTEL_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_darwin_${OTEL_ARCH}.tar.gz"
    curl -sL "$OTEL_URL" | tar xz -C ~/.local/bin otelcol-contrib
    echo "✓ OTel Collector installed to ~/.local/bin/otelcol-contrib"
else
    echo "✓ OTel Collector already installed"
fi

# Step 3: Configure OTel Collector
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 3: Configuring OTel Collector..."
echo "═══════════════════════════════════════════════════════════════"

cat > ~/.config/otelcol/config.yaml << 'EOF'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: localhost:4317
      http:
        endpoint: localhost:4318

processors:
  batch:
    timeout: 10s

exporters:
  file/metrics:
    path: ~/.local/share/otelcol/logs/metrics.jsonl
    rotation:
      max_megabytes: 100
      max_days: 30
      max_backups: 3
  file/logs:
    path: ~/.local/share/otelcol/logs/events.jsonl
    rotation:
      max_megabytes: 100
      max_days: 30
      max_backups: 3
  prometheus:
    endpoint: localhost:9091
    namespace: claude_code

service:
  telemetry:
    metrics:
      level: none
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [file/metrics, prometheus]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [file/logs]
EOF

# Expand ~ in the config file
sed -i '' "s|~|$HOME|g" ~/.config/otelcol/config.yaml
echo "✓ OTel Collector configured"

# Step 4: Create OTel Collector LaunchAgent
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 4: Setting up OTel Collector service..."
echo "═══════════════════════════════════════════════════════════════"

cat > ~/Library/LaunchAgents/com.otelcol.claude-code.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.otelcol.claude-code</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.local/bin/otelcol-contrib</string>
        <string>--config</string>
        <string>$HOME/.config/otelcol/config.yaml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.local/share/otelcol/logs/otelcol.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.local/share/otelcol/logs/otelcol.err</string>
</dict>
</plist>
EOF

echo "✓ OTel Collector service configured"

# Step 5: Configure Prometheus
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 5: Configuring Prometheus..."
echo "═══════════════════════════════════════════════════════════════"

# Backup existing config
if [ -f "$HOMEBREW_PREFIX/etc/prometheus.yml" ]; then
    cp "$HOMEBREW_PREFIX/etc/prometheus.yml" "$HOMEBREW_PREFIX/etc/prometheus.yml.backup"
fi

cat > "$HOMEBREW_PREFIX/etc/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
    - targets: ["localhost:9090"]

  - job_name: "claude_code"
    static_configs:
    - targets: ["localhost:9091"]
EOF

echo "✓ Prometheus configured"

# Step 6: Configure Grafana
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 6: Configuring Grafana..."
echo "═══════════════════════════════════════════════════════════════"

GRAFANA_INI="$HOMEBREW_PREFIX/etc/grafana/grafana.ini"

# Set custom port (65432) to avoid conflicts
if grep -q "^;http_port" "$GRAFANA_INI" 2>/dev/null; then
    sed -i '' 's/^;http_port.*/http_port = 65432/' "$GRAFANA_INI"
elif grep -q "^http_port" "$GRAFANA_INI" 2>/dev/null; then
    sed -i '' 's/^http_port.*/http_port = 65432/' "$GRAFANA_INI"
else
    echo "http_port = 65432" >> "$GRAFANA_INI"
fi

echo "✓ Grafana configured on port 65432"

# Step 7: Start services
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 7: Starting services..."
echo "═══════════════════════════════════════════════════════════════"

# Start OTel Collector
launchctl bootout gui/$(id -u)/com.otelcol.claude-code 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.otelcol.claude-code.plist
launchctl kickstart gui/$(id -u)/com.otelcol.claude-code
echo "✓ OTel Collector started"

# Start Prometheus
brew services start prometheus 2>/dev/null || brew services restart prometheus
echo "✓ Prometheus started"

# Start Grafana
brew services start grafana 2>/dev/null || brew services restart grafana
echo "✓ Grafana started"

sleep 3

# Step 8: Setup Grafana datasource
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 8: Configuring Grafana datasource..."
echo "═══════════════════════════════════════════════════════════════"

# Wait for Grafana to be ready
for i in {1..30}; do
    if curl -s http://localhost:65432/api/health > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Add Prometheus datasource
curl -s -X POST \
    -u admin:admin \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Prometheus",
        "type": "prometheus",
        "url": "http://localhost:9090",
        "access": "proxy",
        "isDefault": true
    }' \
    http://localhost:65432/api/datasources 2>/dev/null || true

echo "✓ Prometheus datasource configured"

# Step 9: Import dashboard
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 9: Importing Grafana dashboard..."
echo "═══════════════════════════════════════════════════════════════"

if [ -f "$SCRIPT_DIR/dashboard.json" ]; then
    "$SCRIPT_DIR/scripts/import-dashboard.sh" admin admin
    echo "✓ Dashboard imported"
else
    echo "⚠ dashboard.json not found, skipping import"
fi

# Step 10: Setup watchdog
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 10: Setting up auto-restart watchdog..."
echo "═══════════════════════════════════════════════════════════════"

"$SCRIPT_DIR/scripts/setup-watchdog.sh"
echo "✓ Watchdog configured"

# Step 11: Configure shell environment
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Step 11: Configuring shell environment..."
echo "═══════════════════════════════════════════════════════════════"

ENV_VARS='
# Claude Code Telemetry (added by Claude Pulse)
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317'

# Detect the user's shell and find the right config file
USER_SHELL=$(basename "$SHELL")
SHELL_CONFIG=""

if [ "$USER_SHELL" = "zsh" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
    # Create .zshrc if it doesn't exist
    touch "$SHELL_CONFIG"
elif [ "$USER_SHELL" = "bash" ]; then
    # On macOS, bash uses .bash_profile for login shells, .bashrc for non-login
    # We'll add to .bashrc and source it from .bash_profile if needed
    SHELL_CONFIG="$HOME/.bashrc"
    touch "$SHELL_CONFIG"
    # Ensure .bash_profile sources .bashrc
    if [ -f "$HOME/.bash_profile" ]; then
        if ! grep -q "source.*\.bashrc" "$HOME/.bash_profile" 2>/dev/null; then
            echo -e '\n# Source .bashrc\n[[ -f ~/.bashrc ]] && source ~/.bashrc' >> "$HOME/.bash_profile"
        fi
    else
        echo -e '# Source .bashrc\n[[ -f ~/.bashrc ]] && source ~/.bashrc' > "$HOME/.bash_profile"
    fi
else
    # Fallback: try to find an existing config file
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_CONFIG="$HOME/.bashrc"
    fi
fi

if [ -n "$SHELL_CONFIG" ]; then
    if grep -q "CLAUDE_CODE_ENABLE_TELEMETRY" "$SHELL_CONFIG" 2>/dev/null; then
        echo "✓ Telemetry already configured in $SHELL_CONFIG"
    else
        echo "$ENV_VARS" >> "$SHELL_CONFIG"
        echo "✓ Telemetry environment variables added to $SHELL_CONFIG"
    fi
    SHELL_CONFIG_NAME=$(basename "$SHELL_CONFIG")
else
    echo "⚠ Could not detect shell config file"
    echo "  Add these environment variables manually:"
    echo "$ENV_VARS"
    SHELL_CONFIG_NAME="your shell config"
fi

# Done!
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Installation Complete!                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Dashboard URL: http://localhost:65432"
echo "Login: admin / admin (change on first login)"
echo ""
echo "Next steps:"
echo "  1. Run 'source ~/$SHELL_CONFIG_NAME' or restart your terminal"
echo "  2. Start using Claude Code - metrics will flow automatically"
echo "  3. Open http://localhost:65432 to view your dashboard"
echo ""
