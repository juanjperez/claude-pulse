#!/bin/bash
# Setup watchdog cron jobs to auto-restart services if they stop
# Usage: ./setup-watchdog.sh

echo "Setting up auto-restart watchdog..."

# Remove existing watchdog entries and add new ones
(crontab -l 2>/dev/null | grep -v "prometheus-watchdog" | grep -v "grafana-watchdog"
echo "* * * * * pgrep prometheus > /dev/null || launchctl kickstart gui/\$(id -u)/homebrew.mxcl.prometheus # prometheus-watchdog"
echo "* * * * * pgrep grafana > /dev/null || launchctl kickstart gui/\$(id -u)/homebrew.mxcl.grafana # grafana-watchdog") | crontab -

echo "✓ Watchdog cron jobs installed"
echo ""
echo "Current crontab:"
crontab -l | grep -E "prometheus|grafana"
echo ""
echo "Services will auto-restart within 1 minute if they stop."
