#!/bin/bash

echo "Concurrency Stress Test - Maximum Load Analysis"
echo "==============================================="

# Terminal colour formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test configuration - extended levels to find real limits
STRESS_LEVELS=(50 100 250 500 750 1000 2000 3000 5000 10000)

# Set results file path using PROJECT_ROOT
STRESS_RESULTS="$PROJECT_ROOT/test_results/stress_results.txt"

# Performance tracking variables
declare -a SUCCESS_RATES
declare -a THROUGHPUT_RATES
declare -a TEST_DURATIONS

# Initialize results file
mkdir -p "$(dirname "$STRESS_RESULTS")"
echo "Stress Test Results - Maximum Concurrency" > "$STRESS_RESULTS"
echo "=========================================" >> "$STRESS_RESULTS"
echo "Timestamp: $(date)" >> "$STRESS_RESULTS"
echo "" >> "$STRESS_RESULTS"

# Deterministic IP and port allocation
generate_valid_ip_port() {
    local index=$1
    
    # Generate unique IPs within private address space
    local subnet=$((index % 250 + 1))
    local host=$(((index / 250) % 250 + 1))
    local ip="192.168.$subnet.$host"
    
    # Generate unique ports: 10000-65000 range to avoid conflicts
    local port=$((10000 + index))
    
    echo "$ip $port"
}

# Execute concurrency test at specified load level
test_stress_level() {
    local level=$1
    echo -e "\nTesting $level concurrent connections"
    
    "$PROJECT_ROOT/server" 2302 > "server_stress_$level.log" 2>&1 &
    local server_pid=$!
    sleep 2
    
    if ! kill -0 $server_pid 2>/dev/null; then
        echo "Server failed to start"
        return 1
    fi
    
    echo "Server started (PID: $server_pid), launching clients..."
    
    client_pids=()
    local start_time=$(date +%s.%N)
    
    for i in $(seq 1 $level); do
        local ip_port=$(generate_valid_ip_port $i)
        local ip=$(echo $ip_port | cut -d' ' -f1)
        local port=$(echo $ip_port | cut -d' ' -f2)
        timeout 30s "$PROJECT_ROOT/client" localhost 2302 A "$ip" $port > "stress_${level}_$i.tmp" 2>&1 &
        client_pids+=($!)
    done
    
    echo "All $level clients launched, waiting for completion..."
    
    # Wait for all processes
    for pid in "${client_pids[@]}"; do
        wait $pid 2>/dev/null
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Analyse results
    local successful=$(grep -l "Rule added" stress_${level}_*.tmp 2>/dev/null | wc -l)
    local already_exists=$(grep -l "Rule already exists" stress_${level}_*.tmp 2>/dev/null | wc -l)
    local invalid=$(grep -l "Invalid rule" stress_${level}_*.tmp 2>/dev/null | wc -l)
    local connection_failed=$(grep -l "Connection refused\|Connection reset\|Connection timed out" stress_${level}_*.tmp 2>/dev/null | wc -l)
    local empty_responses=$(find . -name "stress_${level}_*.tmp" -size 0 2>/dev/null | wc -l)
    local total_files=$(ls stress_${level}_*.tmp 2>/dev/null | wc -l)
    
    echo "Test Results:"
    echo "   Client processes: $level"
    echo "   Response files: $total_files"  
    echo "   Successful: $successful"
    echo "   Already exists: $already_exists"
    echo "   Invalid: $invalid"
    echo "   Connection failed: $connection_failed"
    echo "   Empty responses: $empty_responses"
    echo "   Duration: ${duration}s"
    echo "   Rate: $(echo "scale=2; $level / $duration" | bc -l) ops/sec"
    
    if [ $invalid -gt 0 ]; then
        echo -e "\nInvalid responses (sample):"
        grep -l "Invalid rule" stress_${level}_*.tmp | head -2 | while read f; do
            local idx=$(echo $f | grep -o '[0-9]*' | tail -1)
            local test_ip_port=$(generate_valid_ip_port $idx)
            echo "$f: $(cat "$f") [Generated: $test_ip_port]"
        done
    fi
    
    if [ $connection_failed -gt 0 ]; then
        echo -e "\nConnection failures (sample):"
        grep -l "Connection refused\|Connection reset\|Connection timed out" stress_${level}_*.tmp | head -3 | while read f; do
            echo "$f: $(cat "$f")"
        done
    fi
    
    if [ $empty_responses -gt 0 ]; then
        echo -e "\nEmpty response files: $empty_responses (possible client crashes or connection failures)"
    fi
    
    local success_rate=$(echo "scale=1; ($successful + $already_exists) * 100 / $total_files" | bc -l)
    local throughput=$(echo "scale=2; $level / $duration" | bc -l 2>/dev/null || echo "0")
    
    echo "   SUCCESS RATE: ${success_rate}%"
    echo "   THROUGHPUT: ${throughput} ops/sec"
    
    # Store metrics for dynamic summary
    SUCCESS_RATES+=($success_rate)
    THROUGHPUT_RATES+=($throughput)
    TEST_DURATIONS+=($duration)
    
    # Log results to file
    echo "Level $level: $successful/$level successful (${success_rate}%) in ${duration}s at ${throughput} ops/sec" >> "$STRESS_RESULTS"
    
    # Cleanup
    kill $server_pid 2>/dev/null
    sleep 1
    rm -f stress_${level}_*.tmp "server_stress_$level.log"
    
    return 0
}

echo "Testing IP/port generation algorithm:"
for i in 1 5 10 250 500; do
    result=$(generate_valid_ip_port $i)
    echo "Index $i -> IP:Port = $result"
done

# Execute stress tests at key concurrency levels
echo -e "\nRunning stress tests:"
for level in "${STRESS_LEVELS[@]}"; do
    test_stress_level $level
    echo "Press Enter to continue..."
    read -t 2
done

# Generate dynamic summary based on actual results
echo "" >> "$STRESS_RESULTS"
echo "SUMMARY:" >> "$STRESS_RESULTS"

# Calculate best performing level
best_success_rate="0"
best_throughput="0"
max_tested_level=${STRESS_LEVELS[-1]}

for i in "${!SUCCESS_RATES[@]}"; do
    if (( $(echo "${SUCCESS_RATES[$i]} > $best_success_rate" | bc -l) )); then
        best_success_rate=${SUCCESS_RATES[$i]}
    fi
    if (( $(echo "${THROUGHPUT_RATES[$i]} > $best_throughput" | bc -l) )); then
        best_throughput=${THROUGHPUT_RATES[$i]}
    fi
done

echo "Maximum tested concurrency: $max_tested_level concurrent connections" >> "$STRESS_RESULTS"
echo "Best success rate achieved: ${best_success_rate}%" >> "$STRESS_RESULTS"
echo "Peak throughput: ${best_throughput} ops/sec" >> "$STRESS_RESULTS"
echo "Test levels: ${STRESS_LEVELS[*]}" >> "$STRESS_RESULTS"

echo -e "\n${GREEN}Stress test completed${NC}"
echo -e "${BLUE}📄 Results saved to: $STRESS_RESULTS${NC}"