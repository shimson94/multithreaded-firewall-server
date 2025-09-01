#!/bin/bash

echo "Cleaning up firewall processes and temporary files"

# Kill any server processes
pkill -f "server" 2>/dev/null
pkill -f "./server" 2>/dev/null

# Kill processes using common test ports
for port in 2301 2302 2303; do
    sudo lsof -ti:$port 2>/dev/null | xargs kill -9 2>/dev/null
done

# Clean up temp files
rm -f client_*.tmp mixed_*.tmp sequential_results.tmp server_output.log
rm -f perf_*.tmp scale_*.tmp debug_*.tmp
rm -f valgrind*.log time_output.log
rm -f interactive_commands.txt stress_commands.txt

# Wait for cleanup to complete
sleep 2

echo "Cleanup completed"