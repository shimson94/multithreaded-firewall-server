#!/bin/bash

# Monitor system resources during stress testing
echo "System Resource Monitor"
echo "======================"

echo "Memory Usage:"
free -h

echo -e "\nThread Limits:"
cat /proc/sys/kernel/threads-max

echo -e "\nFile Descriptor Limits:"
ulimit -n

echo -e "\nProcess Limits:"
ulimit -u

echo -e "\nCurrent System Load:"
uptime

echo -e "\nActive Connections:"
ss -tuln | grep -E ":230[0-9]"

echo -e "\nAvailable TCP Ports:"
cat /proc/sys/net/ipv4/ip_local_port_range