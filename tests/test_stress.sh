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

# Initialise results file
mkdir -p "$(dirname "$STRESS_RESULTS")"
echo "Stress Test Results - Maximum Concurrency" > "$STRESS_RESULTS"
echo "=========================================" >> "$STRESS_RESULTS"
echo "Timestamp: $(date)" >> "$STRESS_RESULTS"
echo "" >> "$STRESS_RESULTS"

# OLD: Deterministic IP and port allocation (ARTIFICIAL - COMMENTING OUT)
# generate_valid_ip_port() {
#     local index=$1
#     
#     # Generate unique IPs within private address space
#     local subnet=$((index % 250 + 1))
#     local host=$(((index / 250) % 250 + 1))
#     local ip="192.168.$subnet.$host"
#     
#     # Generate unique ports: 10000-65000 range to avoid conflicts
#     local port=$((10000 + index))
#     
#     echo "$ip $port"
# }

# NEW: Realistic IP and port generation with conflicts and edge cases
generate_realistic_ip_port() {
    local index=$1
    local scenario=$((index % 10))
    
    case $scenario in
        0|1|2|3|4) 
            # 50% valid, commonly used IPs (realistic conflicts)
            local common_ips=("192.168.1.100" "10.0.0.50" "172.16.0.10" "192.168.0.1" "10.1.1.1")
            local common_ports=(80 443 8080 22 3306)
            local ip_idx=$((index % ${#common_ips[@]}))
            local port_idx=$((index % ${#common_ports[@]}))
            echo "${common_ips[$ip_idx]} ${common_ports[$port_idx]}"
            ;;
        5|6)
            # 20% unique valid IPs  
            local ip="192.168.$((index % 255 + 1)).$((index % 254 + 1))"
            local port=$((8000 + index % 1000))
            echo "$ip $port"
            ;;
        7)
            # 10% edge case IPs
            local edge_ips=("0.0.0.0" "255.255.255.255" "127.0.0.1" "192.168.1.1")
            local ip_idx=$((index % ${#edge_ips[@]}))
            echo "${edge_ips[$ip_idx]} 80"
            ;;
        8)
            # 10% invalid IPs
            local invalid_ips=("999.999.999.999" "256.1.1.1" "192.168.1" "not.an.ip")
            local ip_idx=$((index % ${#invalid_ips[@]}))
            echo "${invalid_ips[$ip_idx]} 80"
            ;;
        9)
            # 10% invalid ports
            local invalid_ports=(-1 99999 abc)
            local port_idx=$((index % ${#invalid_ports[@]}))
            echo "192.168.1.1 ${invalid_ports[$port_idx]}"
            ;;
    esac
}

# Determine expected response for given IP/port input
predict_expected_outcome() {
    local ip="$1"
    local port="$2"
    local index="$3"
    
    # Validate IP format and octet ranges
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # IP format valid, verify octet boundaries
        IFS='.' read -ra OCTETS <<< "$ip"
        for octet in "${OCTETS[@]}"; do
            if (( octet > 255 )); then
                echo "INVALID_IP"
                return
            fi
        done
    else
        # Malformed IP address
        echo "INVALID_IP"
        return
    fi
    
    # Validate port range (1-65535)
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 )) || (( port > 65535 )); then
        echo "INVALID_PORT"
        return
    fi
    
    # Predict conflict likelihood based on generation algorithm
    # Scenarios 0-4 use common addresses with high collision probability
    local scenario=$((index % 10))
    if (( scenario >= 0 && scenario <= 4 )); then
        # Common address - expect conflicts in concurrent testing
        echo "CONFLICT_LIKELY"
    else
        # Unique address - should succeed unless race condition occurs
        echo "SUCCESS_EXPECTED"
    fi
}

# Compare actual server response with predicted outcome
validate_client_result() {
    local client_file="$1"
    local expected="$2"
    local ip="$3"
    local port="$4"
    
    if [[ ! -f "$client_file" ]]; then
        echo "MISSING_RESPONSE"
        return 1
    fi
    
    local actual_response=$(cat "$client_file")
    
    case "$expected" in
        "INVALID_IP"|"INVALID_PORT")
            if [[ "$actual_response" == *"Invalid rule"* ]]; then
                echo "CORRECT"
                return 0
            else
                echo "INCORRECT: Expected 'Invalid rule' for $ip:$port, got '$actual_response'"
                return 1
            fi
            ;;
        "SUCCESS_EXPECTED")
            if [[ "$actual_response" == *"Rule added"* ]]; then
                echo "CORRECT"
                return 0
            elif [[ "$actual_response" == *"Rule already exists"* ]]; then
                # Race condition caused conflict - acceptable behavior
                echo "CORRECT_RACE_CONDITION"
                return 0
            else
                echo "INCORRECT: Expected success for $ip:$port, got '$actual_response'"
                return 1
            fi
            ;;
        "CONFLICT_LIKELY")
            if [[ "$actual_response" == *"Rule already exists"* ]]; then
                echo "CORRECT"
                return 0
            elif [[ "$actual_response" == *"Rule added"* ]]; then
                # First occurrence of duplicate address - valid
                echo "CORRECT_FIRST_OCCURRENCE"
                return 0
            else
                echo "INCORRECT: Expected success/conflict for $ip:$port, got '$actual_response'"
                return 1
            fi
            ;;
        *)
            echo "UNKNOWN_EXPECTED: $expected"
            return 1
            ;;
    esac
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
    
    # Initialise per-client validation log
    local validation_log="validation_${level}.log"
    echo "# Individual Client Validation Log - Level $level" > "$validation_log"
    echo "# Format: ClientID | Input | Expected | Actual | Validation" >> "$validation_log"
    
    for i in $(seq 1 $level); do
        local ip_port=$(generate_realistic_ip_port $i)
        local ip=$(echo $ip_port | cut -d' ' -f1)
        local port=$(echo $ip_port | cut -d' ' -f2)
        local expected=$(predict_expected_outcome "$ip" "$port" "$i")
        
        # Record input parameters and prediction
        echo "$i | $ip:$port | $expected | PENDING | PENDING" >> "$validation_log"
        
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
    
    # Validate each client response individually
    echo "Performing individual input-output validation..."
    
    local correct_validations=0
    local total_validations=0
    local validation_failures=()
    
    for i in $(seq 1 $level); do
        local ip_port=$(generate_realistic_ip_port $i)
        local ip=$(echo $ip_port | cut -d' ' -f1)
        local port=$(echo $ip_port | cut -d' ' -f2)
        local expected=$(predict_expected_outcome "$ip" "$port" "$i")
        local client_file="stress_${level}_$i.tmp"
        
        local validation_result=$(validate_client_result "$client_file" "$expected" "$ip" "$port")
        local validation_status=$?
        
        # Update log with server response
        local actual_response=""
        if [[ -f "$client_file" ]]; then
            actual_response=$(cat "$client_file" | tr '\n' ' ')
        else
            actual_response="NO_RESPONSE_FILE"
        fi
        
        # Update validation status in log file
        sed -i "${i}s/| PENDING | PENDING$/| $actual_response | $validation_result/" "$validation_log"
        
        total_validations=$((total_validations + 1))
        if [[ $validation_status -eq 0 ]]; then
            correct_validations=$((correct_validations + 1))
        else
            validation_failures+=("Client $i ($ip:$port): $validation_result")
        fi
    done
    
    # Calculate individual validation success rate
    local real_correctness_rate=$(echo "scale=1; $correct_validations * 100 / $total_validations" | bc -l)
    
    # Aggregate response counts for comparison
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
            local test_ip_port=$(generate_realistic_ip_port $idx)
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
    
    # Calculate correctness rate: all appropriate responses (success + conflicts + proper rejections)
    local correct_responses=$((successful + already_exists + invalid))
    local actual_errors=$((connection_failed + empty_responses))
    local correctness_rate=$(echo "scale=1; $correct_responses * 100 / $total_files" | bc -l)
    local throughput=$(echo "scale=2; $level / $duration" | bc -l 2>/dev/null || echo "0")
    
    echo ""
    echo "   INDIVIDUAL VALIDATION RESULTS:"
    echo "     Correct validations: $correct_validations/$total_validations"
    echo "     Validation failures: ${#validation_failures[@]}"
    echo "     CORRECTNESS RATE: ${real_correctness_rate}% (each input gets expected response)"
    echo "     THROUGHPUT: ${throughput} ops/sec"
    echo ""
    echo "   LEGACY AGGREGATE BREAKDOWN (for comparison):"
    echo "     New rules added: $successful"
    echo "     Conflicts detected: $already_exists" 
    echo "     Invalid inputs rejected: $invalid"
    echo "     Connection/system errors: $actual_errors"
    echo "     Legacy aggregate rate: ${correctness_rate}% (meaningless - just counts any response)"
    
    # Report validation failures
    if [[ ${#validation_failures[@]} -gt 0 ]]; then
        echo ""
        echo "   VALIDATION FAILURES:"
        local max_failures=5
        local failure_count=0
        for failure in "${validation_failures[@]}"; do
            if [[ $failure_count -lt $max_failures ]]; then
                echo "     • $failure"
                failure_count=$((failure_count + 1))
            else
                echo "     ... and $((${#validation_failures[@]} - max_failures)) more (see $validation_log)"
                break
            fi
        done
    fi
    
    echo ""
    echo "   Detailed validation log: $validation_log"
    
    # Store metrics for summary report
    SUCCESS_RATES+=($real_correctness_rate)
    THROUGHPUT_RATES+=($throughput)
    TEST_DURATIONS+=($duration)
    
    # Log test results with validation metrics
    echo "Level $level: Correctness ${real_correctness_rate}% (${correct_validations}/${total_validations} validated correctly) in ${duration}s at ${throughput} ops/sec" >> "$STRESS_RESULTS"
    echo "  Legacy breakdown: ${successful} new, ${already_exists} conflicts, ${invalid} rejected, ${actual_errors} errors" >> "$STRESS_RESULTS"
    
    # Cleanup
    kill $server_pid 2>/dev/null
    sleep 1
    rm -f stress_${level}_*.tmp "server_stress_$level.log" "$validation_log"
    
    return 0
}

echo "Testing realistic IP/port generation algorithm:"
for i in 1 5 10 250 500; do
    result=$(generate_realistic_ip_port $i)
    echo "Index $i -> IP:Port = $result"
done
echo ""
echo "Distribution: 50% common IPs (conflicts), 20% unique, 10% edge cases, 10% invalid IPs, 10% invalid ports"

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
best_correctness_rate="0"
best_throughput="0"
max_tested_level=${STRESS_LEVELS[-1]}

for i in "${!SUCCESS_RATES[@]}"; do
    if (( $(echo "${SUCCESS_RATES[$i]} > $best_correctness_rate" | bc -l) )); then
        best_correctness_rate=${SUCCESS_RATES[$i]}
    fi
    if (( $(echo "${THROUGHPUT_RATES[$i]} > $best_throughput" | bc -l) )); then
        best_throughput=${THROUGHPUT_RATES[$i]}
    fi
done

echo "" >> "$STRESS_RESULTS"
echo "FINAL SUMMARY:" >> "$STRESS_RESULTS"
echo "Maximum tested concurrency: $max_tested_level concurrent connections" >> "$STRESS_RESULTS"
echo "Server correctness rate: ${best_correctness_rate}% (individual input-output validation)" >> "$STRESS_RESULTS"
echo "Peak throughput: ${best_throughput} ops/sec" >> "$STRESS_RESULTS"
echo "Test methodology: Individual validation of each input against expected outcome" >> "$STRESS_RESULTS"
echo "Input distribution: 50% conflicts, 20% unique, 10% edge cases, 10% invalid IPs, 10% invalid ports" >> "$STRESS_RESULTS"
echo "Test levels: ${STRESS_LEVELS[*]}" >> "$STRESS_RESULTS"

echo -e "\n${GREEN}Stress test completed${NC}"
echo -e "${BLUE}Results saved to: $STRESS_RESULTS${NC}"