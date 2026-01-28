#!/bin/bash
# Claude Pulse - Uninstallation Script
# Removes all Claude Pulse components

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Claude Pulse Uninstaller                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

read -p "This will remove Claude Pulse services and configurations. Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Stopping services..."

# Stop OTel Collector
launchctl bootout gui/$(id -u)/com.otelcol.claude-code 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.otelcol.claude-code.plist
echo "✓ OTel Collector stopped"

# Stop Prometheus and Grafana
brew services stop prometheus 2>/dev/null || true
brew services stop grafana 2>/dev/null || true
echo "✓ Prometheus and Grafana stopped"

# Remove watchdog cron jobs
(crontab -l 2>/dev/null | grep -v "prometheus-watchdog" | grep -v "grafana-watchdog") | crontab - 2>/dev/null || true
echo "✓ Watchdog cron jobs removed"

echo ""
echo "Removing configurations..."

# Remove OTel Collector
rm -f ~/.local/bin/otelcol-contrib
rm -rf ~/.config/otelcol
echo "✓ OTel Collector removed"

echo ""
read -p "Remove collected data (metrics, logs)? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf ~/.local/share/otelcol
    echo "✓ OTel data removed"
fi

echo ""
read -p "Uninstall Prometheus and Grafana (brew uninstall)? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    brew uninstall prometheus grafana 2>/dev/null || true
    echo "✓ Prometheus and Grafana uninstalled"

    read -p "Remove Prometheus data (/opt/homebrew/var/prometheus)? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /opt/homebrew/var/prometheus
        echo "✓ Prometheus data removed"
    fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   Uninstallation Complete!                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Note: Environment variables in ~/.zshrc were not removed."
echo "You can manually remove the CLAUDE_CODE_ENABLE_TELEMETRY and OTEL_* lines."
echo ""
