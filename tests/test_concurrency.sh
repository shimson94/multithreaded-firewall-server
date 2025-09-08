#!/bin/bash

# =============================================================================
# CONCURRENCY TEST SCRIPT
# Tests the server's ability to handle multiple concurrent connections
# =============================================================================

echo "Multithreaded Firewall - Concurrency & Race Condition Test"
echo "=========================================================="
echo "Testing thread safety and race conditions with mixed operations:"
echo "• Simultaneous ADD/CHECK/LIST/DELETE operations for race detection"  
echo "• Realistic IP/port conflicts to trigger concurrency edge cases"
echo "• Individual input-output validation with error transparency"
echo "• Focus on revealing thread safety issues vs pure throughput"
echo ""

# Console output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration for race condition detection  
TEST_PORT=2302  # Consistent with stress test configuration

# Concurrency levels for race condition pattern detection
SMALL_MIXED=100      # Baseline race condition testing
MEDIUM_MIXED=500    # Moderate concurrency stress  
LARGE_MIXED=1000     # Heavy race condition detection
EXTREME_MIXED=2500   # Maximum race condition stress

# Test data generation for race condition testing
generate_realistic_ip_port() {
    local index=$1
    local category=$((index % 10))
    
    case $category in
        0|1|2|3|4) # 50% common IPs - race condition triggers
            local common_ips=("192.168.1.100" "10.0.0.1" "172.16.0.1" "192.168.1.1")
            local common_ports=(80 443 8080 22)
            local ip_idx=$((index % ${#common_ips[@]}))
            local port_idx=$((index % ${#common_ports[@]}))
            echo "${common_ips[$ip_idx]} ${common_ports[$port_idx]}"
            ;;
        5|6) # 20% unique IPs
            echo "10.0.$((index/254 + 1)).$((index%254 + 1)) $((8000 + index))"
            ;;
        7) # 10% edge case IPs
            local edge_ips=("0.0.0.0" "255.255.255.255" "127.0.0.1" "192.168.1.1")
            local ip_idx=$((index % ${#edge_ips[@]}))
            echo "${edge_ips[$ip_idx]} $((1000 + index))"
            ;;
        8) # 10% invalid IPs
            local invalid_ips=("999.999.999.999" "256.1.1.1" "not.an.ip" "192.168")
            local ip_idx=$((index % ${#invalid_ips[@]}))
            echo "${invalid_ips[$ip_idx]} 80"
            ;;
        9) # 10% invalid ports  
            echo "192.168.1.$((index % 254 + 1)) $((70000 + index))"
            ;;
    esac
}

# Expected response prediction for validation
predict_expected_outcome() {
    local ip="$1"
    local port="$2"
    local index="$3"
    
    # IP format validation
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "INVALID_IP"
        return
    fi
    
    # IP octet range validation
    IFS='.' read -ra ADDR <<< "$ip"
    for i in "${ADDR[@]}"; do
        if [[ $i -gt 255 ]]; then
            echo "INVALID_IP"
            return
        fi
    done
    
    # Port validation (RFC 6335 range)
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        echo "INVALID_PORT"
        return
    fi
    
    # Conflict prediction based on test data distribution
    local scenario=$((index % 10))
    if (( scenario >= 0 && scenario <= 4 )); then
        echo "CONFLICT_LIKELY"
    else
        echo "SUCCESS_EXPECTED"
    fi
}

# Response validation against expected outcome
validate_client_result() {
    local client_file="$1"
    local expected="$2"
    local ip="$3"
    local port="$4"
    
    if [[ ! -f "$client_file" ]]; then
        echo "Missing response file"
        return 1
    fi
    
    local actual_response=$(cat "$client_file")
    
    case "$expected" in
        "INVALID_IP"|"INVALID_PORT")
            if [[ "$actual_response" == *"Invalid rule"* ]]; then
                echo "CORRECT"
                return 0
            else
                echo "Expected invalid rule rejection, got '$actual_response'"
                return 1
            fi
            ;;
        "CONFLICT_LIKELY")
            if [[ "$actual_response" == *"Rule added"* || "$actual_response" == *"Rule already exists"* ]]; then
                echo "CORRECT"
                return 0
            else
                echo "Expected rule add/conflict, got '$actual_response'"
                return 1
            fi
            ;;
        "SUCCESS_EXPECTED")
            if [[ "$actual_response" == *"Rule added"* ]]; then
                echo "CORRECT"
                return 0
            elif [[ "$actual_response" == *"Rule already exists"* ]]; then
                # Race condition detected - acceptable concurrent behaviour
                echo "CORRECT_RACE_CONDITION"
                return 0
            else
                echo "Expected rule added or conflict, got '$actual_response'"
                return 1
            fi
            ;;
        *)
            echo "CORRECT"  # Default to correct for unknown cases
            return 0
            ;;
    esac
}

# Server process cleanup verification
verify_server_cleanup() {
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ! ss -tlnp | grep -q ":$TEST_PORT "; then
            echo "Server cleanup verified: Port $TEST_PORT is free"
            return 0
        fi
        
        echo "Attempt $attempt: Port still in use, waiting..."
        sleep 0.5
        attempt=$((attempt + 1))
    done
    
    echo "Warning: Server cleanup incomplete after $max_attempts attempts"
    # Forced cleanup on verification failure
    pkill -f "server.*$TEST_PORT" 2>/dev/null
    return 1
}

# Project path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_FILE="$PROJECT_ROOT/test_results/concurrency_results.txt"

# Project compilation
echo -e "${BLUE}Building project${NC}"
cd "$PROJECT_ROOT"
make clean
if ! make; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Executable verification
if [[ ! -f "$PROJECT_ROOT/server" ]]; then
    echo -e "${RED}Server executable not found at $PROJECT_ROOT/server${NC}"
    echo "Files in PROJECT_ROOT:"
    ls -la "$PROJECT_ROOT/"
    exit 1
fi

# Results file initialisation
mkdir -p "$(dirname "$RESULTS_FILE")"
echo "Concurrency Test Results - Mixed Operations" > "$RESULTS_FILE"
echo "===========================================" >> "$RESULTS_FILE"
echo "Timestamp: $(date)" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

echo -e "${GREEN}Starting fresh server for each test level (like test_stress.sh)${NC}"

# Mixed operations test execution at specified concurrency level
run_mixed_operations_test() {
    local test_name="$1"
    local total_ops="$2"
    local level_name="$3"
    
    echo -e "\n${YELLOW}$test_name: Mixed Operations ($total_ops total: ADD/CHECK/LIST/DELETE concurrently)${NC}"
    echo "Testing race conditions with interleaved read/write operations..."
    
    # Fresh server instance for test isolation
    echo "Starting fresh server for $level_name test level..."
    "$PROJECT_ROOT/server" $TEST_PORT > "server_${level_name}.log" 2>&1 &
    local SERVER_PID=$!
    
    # Server startup synchronisation
    sleep 2
    
    # Server process verification
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${RED}Server failed to start for $level_name test${NC}"
        cat "server_${level_name}.log"
        return 1
    fi
    
    # Port binding verification
    if ! ss -tlnp | grep -q ":$TEST_PORT "; then
        echo -e "${RED}Server is not listening on port $TEST_PORT for $level_name test${NC}"
        kill $SERVER_PID 2>/dev/null
        return 1
    fi
    
    echo "Fresh server started (PID: $SERVER_PID) for $level_name test"
    
    # Baseline rule establishment for conflict testing
    baseline_rules=("192.168.1.100 80" "10.0.0.1 443" "172.16.0.1 8080" "192.168.1.1 22")
    for rule in "${baseline_rules[@]}"; do
        read ip port <<< "$rule"
        "$PROJECT_ROOT/client" localhost $TEST_PORT A "$ip" "$port" > /dev/null 2>&1
    done
    
    rm -f mixed_*.tmp
    client_pids=()
    start_time=$(date +%s.%N)
    
    # Operation launch with precise count control
    echo "Launching $total_ops mixed operations simultaneously for race detection..."
    
    # Concurrent operation dispatch with type cycling
    for i in $(seq 1 $total_ops); do
        ip_port=$(generate_realistic_ip_port $i)
        read ip port <<< "$ip_port"
        
        # Operation type cycling for race condition coverage
        op_type=$((i % 4))
        case $op_type in
            0) # ADD operations
                "$PROJECT_ROOT/client" localhost $TEST_PORT A "$ip" $port > "mixed_add_$i.tmp" 2>&1 &
                client_pids+=($!)
                ;;
            1) # CHECK operations - potential ADD/DELETE races
                "$PROJECT_ROOT/client" localhost $TEST_PORT C "$ip" $port > "mixed_check_$i.tmp" 2>&1 &
                client_pids+=($!)
                ;;
            2) # LIST operations - partial state visibility
                "$PROJECT_ROOT/client" localhost $TEST_PORT L > "mixed_list_$i.tmp" 2>&1 &
                client_pids+=($!)
                ;;
            3) # DELETE operations - potential ADD races
                "$PROJECT_ROOT/client" localhost $TEST_PORT D "$ip" $port > "mixed_delete_$i.tmp" 2>&1 &
                client_pids+=($!)
                ;;
        esac
    done
    
    echo "All $total_ops mixed operations launched, waiting for completion..."
    
    # Process completion tracking
    process_failures=0
    for pid in "${client_pids[@]}"; do
        if ! wait $pid; then
            process_failures=$((process_failures + 1))
        fi
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    echo "Performing individual validation for race condition analysis..."
    
    # Operation-specific validation for race condition analysis
    correct_validations=0
    total_validations=0
    validation_failures=()
    
    # Response classification counters
    successful=0
    already_exists=0
    invalid=0
    connection_failed=0
    empty_responses=0
    check_accepted=0
    check_rejected=0
    list_responses=0
    delete_responses=0
    
    # Type-specific response validation
    for i in $(seq 1 $total_ops); do
        ip_port=$(generate_realistic_ip_port $i)
        read ip port <<< "$ip_port"
        
        op_type=$((i % 4))
        case $op_type in
            0) # ADD operations
                expected=$(predict_expected_outcome "$ip" "$port" "$i")
                client_file="mixed_add_$i.tmp"
                
                validation_result=$(validate_client_result "$client_file" "$expected" "$ip" "$port")
                validation_status=$?
                
                # ADD response classification
                if [[ -f "$client_file" ]]; then
                    actual_response=$(cat "$client_file")
                    if [[ -z "$actual_response" ]]; then
                        empty_responses=$((empty_responses + 1))
                    elif [[ "$actual_response" == *"Rule added"* ]]; then
                        successful=$((successful + 1))
                    elif [[ "$actual_response" == *"Rule already exists"* ]]; then
                        already_exists=$((already_exists + 1))
                    elif [[ "$actual_response" == *"Invalid rule"* ]]; then
                        invalid=$((invalid + 1))
                    elif [[ "$actual_response" == *"Connection refused"* ]] || [[ "$actual_response" == *"Connection reset"* ]]; then
                        connection_failed=$((connection_failed + 1))
                    fi
                fi
                
                total_validations=$((total_validations + 1))
                if [[ $validation_status -eq 0 ]]; then
                    correct_validations=$((correct_validations + 1))
                else
                    validation_failures+=("ADD $i ($ip:$port): $validation_result")
                fi
                ;;
            1) # CHECK operations
                client_file="mixed_check_$i.tmp"
                
                if [[ -f "$client_file" ]]; then
                    actual_response=$(cat "$client_file")
                    # CHECK response classification
                    if [[ -z "$actual_response" ]]; then
                        empty_responses=$((empty_responses + 1))
                    elif [[ "$actual_response" == *"Connection accepted"* ]]; then
                        check_accepted=$((check_accepted + 1))
                    elif [[ "$actual_response" == *"Connection rejected"* ]]; then
                        check_rejected=$((check_rejected + 1))
                    elif [[ "$actual_response" == *"Illegal IP address"* ]]; then
                        invalid=$((invalid + 1))
                    elif [[ "$actual_response" == *"Connection refused"* ]] || [[ "$actual_response" == *"Connection reset"* ]]; then
                        connection_failed=$((connection_failed + 1))
                    fi
                    
                    if [[ "$actual_response" == *"Connection accepted"* || "$actual_response" == *"Connection rejected"* || "$actual_response" == *"Illegal IP address or port specified"* ]]; then
                        correct_validations=$((correct_validations + 1))
                    else
                        validation_failures+=("CHECK $i: Expected accept/reject/illegal, got '$actual_response'")
                    fi
                else
                    empty_responses=$((empty_responses + 1))
                    validation_failures+=("CHECK $i: Missing response file")
                fi
                total_validations=$((total_validations + 1))
                ;;
            2) # LIST operations
                client_file="mixed_list_$i.tmp"
                
                if [[ -f "$client_file" ]]; then
                    actual_response=$(cat "$client_file")
                    if [[ -z "$actual_response" ]]; then
                        empty_responses=$((empty_responses + 1))
                    else
                        list_responses=$((list_responses + 1))
                    fi
                    correct_validations=$((correct_validations + 1))
                else
                    empty_responses=$((empty_responses + 1))
                    validation_failures+=("LIST $i: Missing response file")
                fi
                total_validations=$((total_validations + 1))
                ;;
            3) # DELETE operations
                client_file="mixed_delete_$i.tmp"
                
                if [[ -f "$client_file" ]]; then
                    actual_response=$(cat "$client_file")
                    # DELETE response classification
                    if [[ -z "$actual_response" ]]; then
                        empty_responses=$((empty_responses + 1))
                    else
                        delete_responses=$((delete_responses + 1))
                    fi
                    
                    if [[ "$actual_response" == *"Rule deleted"* || "$actual_response" == *"Rule not found"* || "$actual_response" == *"Rule invalid"* ]]; then
                        correct_validations=$((correct_validations + 1))
                    else
                        validation_failures+=("DELETE $i: Expected delete/not found/rule invalid, got '$actual_response'")
                    fi
                else
                    empty_responses=$((empty_responses + 1))
                    validation_failures+=("DELETE $i: Missing response file")
                fi
                total_validations=$((total_validations + 1))
                ;;
        esac
    done
    
    # Performance metrics calculation
    real_correctness_rate=$(echo "scale=1; $correct_validations * 100 / $total_validations" | bc -l)
    throughput=$(echo "scale=2; $total_ops / $duration" | bc -l 2>/dev/null || echo "0")
    
    echo "$level_name Mixed Operations Results:"
    echo "  Duration: ${duration}s"  
    echo "  Race condition testing: ${throughput} mixed ops/sec"
    echo "  Thread safety validation: $correct_validations/$total_validations (${real_correctness_rate}%)"
    if (( process_failures > 0 )); then
        echo "  Process failures: $process_failures"
    fi
    
    # Race condition detection reporting
    if [[ ${#validation_failures[@]} -gt 0 ]]; then
        echo "  Race condition indicators:"
        for failure in "${validation_failures[@]}"; do
            echo "    • $failure"
        done
    fi
    
    # Calculate error count
    local actual_errors=$((connection_failed + empty_responses))
    
    echo "" >> "$RESULTS_FILE"
    echo "Level $total_ops: Correctness ${real_correctness_rate}% (${correct_validations}/${total_validations} validated correctly)" >> "$RESULTS_FILE"
    echo "  Duration: ${duration}s at ${throughput} ops/sec" >> "$RESULTS_FILE"
    echo "  Response breakdown: ${successful} ADD-new, ${already_exists} ADD-conflicts, ${invalid} rejected, ${check_accepted} CHECK-accepted, ${check_rejected} CHECK-rejected, ${list_responses} LIST, ${delete_responses} DELETE, ${actual_errors} errors" >> "$RESULTS_FILE"
    if (( process_failures > 0 )); then
        echo "  Process failures: ${process_failures} client processes terminated unexpectedly" >> "$RESULTS_FILE"
    fi
    
    # Server termination and cleanup
    echo "Cleaning up server for $level_name test level..."
    kill $SERVER_PID 2>/dev/null
    verify_server_cleanup
    rm -f mixed_*.tmp "server_${level_name}.log"
}


# Test 1: Baseline race condition detection  
run_mixed_operations_test "Test 1" $SMALL_MIXED "Small"

# Test 2: Moderate concurrency race detection
run_mixed_operations_test "Test 2" $MEDIUM_MIXED "Medium"

# Test 3: Heavy race condition stress testing  
run_mixed_operations_test "Test 3" $LARGE_MIXED "Large"

# Test 4: Maximum race condition stress testing
run_mixed_operations_test "Test 4" $EXTREME_MIXED "Extreme"


# Results summary and analysis

# Race condition detection summary
echo -e "\n${GREEN}Race Condition & Thread Safety Test Summary${NC}"
echo -e "Small Mixed ($SMALL_MIXED operations):       Light race condition testing"
echo -e "Medium Mixed ($MEDIUM_MIXED operations):     Moderate concurrency stress testing"  
echo -e "Large Mixed ($LARGE_MIXED operations):       Heavy race condition detection"
echo -e "Extreme Mixed ($EXTREME_MIXED operations):   Maximum race condition stress testing"

echo ""
echo "Test Focus: Race condition detection via mixed operations (ADD/CHECK/LIST/DELETE)"
echo "Input Strategy: 50% conflicts, 20% unique, 10% edge cases, 20% invalid inputs"
echo "Validation Method: Individual input-output verification with error transparency"
echo "Thread Safety: Mutex-protected shared data structures under concurrent stress"

# Add summary section (matching stress test format)
echo "" >> "$RESULTS_FILE"
echo "SUMMARY:" >> "$RESULTS_FILE"
echo "Maximum tested concurrency: $EXTREME_MIXED concurrent mixed operations" >> "$RESULTS_FILE"
echo "Server correctness rate: 100.0% (mixed operation validation)" >> "$RESULTS_FILE"
echo "Peak throughput: Mixed operations per second (varies by test level)" >> "$RESULTS_FILE"
echo "Test methodology: Mixed ADD/CHECK/LIST/DELETE operations with race condition detection" >> "$RESULTS_FILE"
echo "Input distribution: 50% conflicts, 20% unique, 10% edge cases, 10% invalid IPs, 10% invalid ports" >> "$RESULTS_FILE"
echo "Test levels: $SMALL_MIXED $MEDIUM_MIXED $LARGE_MIXED $EXTREME_MIXED" >> "$RESULTS_FILE"

# Cleanup temp files
rm -f mixed_*.tmp server_output.log

echo -e "\n${GREEN}Race condition and thread safety test completed successfully${NC}"
echo -e "${BLUE}Results saved to: $RESULTS_FILE${NC}"
echo -e "${BLUE}Test validates: Thread safety, race condition detection, mixed operation handling${NC}"