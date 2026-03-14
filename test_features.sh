#!/bin/bash
# Test script for Jarvis features

echo "=== Jarvis Feature Test ==="

# Check if app is running
if ! pgrep -f "Jarvis.app" > /dev/null; then
    echo "❌ Jarvis app is not running"
    exit 1
fi

echo "✅ Jarvis app is running"

# Test 1: Check if the app responds to AppleScript
echo ""
echo "Test 1: App Responsiveness"
osascript -e 'tell application "Jarvis" to activate' 2>/dev/null && echo "✅ App responds to AppleScript" || echo "❌ App doesn't respond to AppleScript"

# Test 2: Check for any crash logs
echo ""
echo "Test 2: Crash Logs"
ls -la ~/Library/Logs/DiagnosticReports/Jarvis* 2>/dev/null | wc -l | xargs -I {} echo "Found {} crash report(s)"

# Test 3: Check if database exists (indicates indexing has been set up)
echo ""
echo "Test 3: Database Setup"
DB_PATH=~/Library/Application\ Support/Jarvis/jarvis.db
if [ -f "$DB_PATH" ]; then
    echo "✅ Database exists at: $DB_PATH"
    ls -lh "$DB_PATH"
else
    echo "❌ Database not found at: $DB_PATH"
fi

echo ""
echo "=== Test Complete ==="
