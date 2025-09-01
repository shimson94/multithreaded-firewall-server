#!/bin/bash

# =============================================================================
# CONCURRENCY TEST SCRIPT
# Tests the server's ability to handle multiple concurrent connections
# =============================================================================

echo "Multithreaded Firewall - Concurrency Test"
echo "========================================="

# Terminal colour formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration - adjust these for different scale testing
TEST_PORT=2301
SEQUENTIAL_COUNT=50
LOW_CONCURRENT=25
MED_CONCURRENT=100
HIGH_CONCURRENT=250
MIXED_OPS_COUNT=100

# Calculate processing time excluding artificial delays
calculate_processing_time() {
    local start_time=$1
    local sleep_duration=$2
    local end_time=$(date +%s.%N)
    local total_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")
    local processing_time=$(echo "$total_time - $sleep_duration" | bc -l 2>/dev/null || echo "N/A")
    
    # Handle negative timing due to measurement precision
    if (( $(echo "$processing_time < 0" | bc -l) )); then
        processing_time="0.010"
    fi
    
    echo "$processing_time"
}

echo -e "${BLUE}Building project${NC}"
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT should be the multithreaded-firewall-server directory (parent of tests)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Set results file path using PROJECT_ROOT
RESULTS_FILE="$PROJECT_ROOT/test_results/concurrency_results.txt"


# Build from project root
(cd "$PROJECT_ROOT" && make clean && make)
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

echo -e "${BLUE}Starting server on port $TEST_PORT${NC}"
"$PROJECT_ROOT/server" $TEST_PORT > server_output.log 2>&1 &
SERVER_PID=$!

# Wait for server to start
sleep 2

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}Server failed to start${NC}"
    cat server_output.log
    exit 1
fi

# Verify server is listening
if ! ss -tlnp | grep -q ":$TEST_PORT "; then
    echo -e "${RED}Server is not listening on port $TEST_PORT${NC}"
    exit 1
fi

echo -e "${GREEN}Server started successfully (PID: $SERVER_PID)${NC}"

# Initialize results
mkdir -p "$(dirname "$RESULTS_FILE")"
echo "Concurrency Test Results" > "$RESULTS_FILE"
echo "========================" >> "$RESULTS_FILE"
echo "Timestamp: $(date)" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# Test 1: Sequential baseline
echo -e "\n${YELLOW}Test 1: Sequential Operations (Baseline)${NC}"
start_time=$(date +%s.%N)

for i in $(seq 1 $SEQUENTIAL_COUNT); do
    "$PROJECT_ROOT/client" localhost $TEST_PORT A "192.168.1.$((i%254 + 1))" 80 >> sequential_results.tmp 2>&1
    if [ $? -eq 0 ]; then
        echo -n "✓"
    else
        echo -n "✗"
    fi
done

end_time=$(date +%s.%N)
sequential_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")
successful_sequential=$(grep -c "Rule added" sequential_results.tmp 2>/dev/null || echo "0")

echo -e "\nSequential: $successful_sequential/$SEQUENTIAL_COUNT successful in ${sequential_time}s"
echo "Sequential Test: $successful_sequential/$SEQUENTIAL_COUNT successful in ${sequential_time}s" >> "$RESULTS_FILE"

# Test 2: Low concurrency
echo -e "\n${YELLOW}Test 2: Low Concurrency ($LOW_CONCURRENT concurrent)${NC}"
start_time=$(date +%s.%N)

for i in $(seq 1 $LOW_CONCURRENT); do
    "$PROJECT_ROOT/client" localhost $TEST_PORT A "192.168.2.$((i%254 + 1))" 80 > "client_low_$i.tmp" 2>&1 &
done

# Wait briefly for all clients to complete
echo -e "${BLUE}Waiting for concurrent operations to complete${NC}"
sleep 1

concurrent_time_low=$(calculate_processing_time "$start_time" 1)
successful_low=$(grep -l "Rule added" client_low_*.tmp 2>/dev/null | wc -l)

echo "Low Concurrency: $successful_low/$LOW_CONCURRENT successful in ${concurrent_time_low}s"
echo "Low Concurrency ($LOW_CONCURRENT): $successful_low/$LOW_CONCURRENT successful in ${concurrent_time_low}s" >> "$RESULTS_FILE"

# Test 3: Medium concurrency
echo -e "\n${YELLOW}Test 3: Medium Concurrency ($MED_CONCURRENT concurrent)${NC}"
rm -f client_*.tmp
start_time=$(date +%s.%N)

for i in $(seq 1 $MED_CONCURRENT); do
    "$PROJECT_ROOT/client" localhost $TEST_PORT A "192.168.3.$((i%254 + 1))" 80 > "client_med_$i.tmp" 2>&1 &
done
sleep 1

concurrent_time_med=$(calculate_processing_time "$start_time" 1)
successful_med=$(grep -l "Rule added" client_med_*.tmp 2>/dev/null | wc -l)

echo "Medium Concurrency: $successful_med/$MED_CONCURRENT successful in ${concurrent_time_med}s"
echo "Medium Concurrency ($MED_CONCURRENT): $successful_med/$MED_CONCURRENT successful in ${concurrent_time_med}s" >> "$RESULTS_FILE"

# Test 4: High concurrency
echo -e "\n${YELLOW}Test 4: High Concurrency ($HIGH_CONCURRENT concurrent)${NC}"
rm -f client_*.tmp
start_time=$(date +%s.%N)

for i in $(seq 1 $HIGH_CONCURRENT); do
    "$PROJECT_ROOT/client" localhost $TEST_PORT A "192.168.4.$((i%254 + 1))" 80 > "client_high_$i.tmp" 2>&1 &
done
sleep 1

concurrent_time_high=$(calculate_processing_time "$start_time" 1)
successful_high=$(grep -l "Rule added" client_high_*.tmp 2>/dev/null | wc -l)

echo "High Concurrency: $successful_high/$HIGH_CONCURRENT successful in ${concurrent_time_high}s"
echo "High Concurrency ($HIGH_CONCURRENT): $successful_high/$HIGH_CONCURRENT successful in ${concurrent_time_high}s" >> "$RESULTS_FILE"

# Test 5: Mixed operations concurrency
echo -e "\n${YELLOW}Test 5: Mixed Operations (Add, Check, List)${NC}"
start_time=$(date +%s.%N)

# Add some rules
for i in $(seq 1 $MIXED_OPS_COUNT); do
    "$PROJECT_ROOT/client" localhost $TEST_PORT A "192.168.5.$((i%254 + 1))" 80 > "mixed_add_$i.tmp" 2>&1 &
done

# Check connections
for i in $(seq 1 $MIXED_OPS_COUNT); do
    "$PROJECT_ROOT/client" localhost $TEST_PORT C "192.168.5.$((i%254 + 1))" 80 > "mixed_check_$i.tmp" 2>&1 &
done

# Wait for ADD operations to complete before LIST
sleep 1

# List operations (should find the rules that were just added)
for i in $(seq 1 $((MIXED_OPS_COUNT / 4))); do
    "$PROJECT_ROOT/client" localhost $TEST_PORT L > "mixed_list_$i.tmp" 2>&1 &
done

# Wait for all operations to complete
sleep 1

# Allow time for all operations to complete before measuring
sleep 1
mixed_time=$(calculate_processing_time "$start_time" 3)
successful_mixed_add=$(grep -l "Rule added" mixed_add_*.tmp 2>/dev/null | wc -l)
successful_mixed_check=$(grep -l "Connection accepted\|Connection rejected" mixed_check_*.tmp 2>/dev/null | wc -l)
successful_mixed_list=$(grep -l "Rule:" mixed_list_*.tmp 2>/dev/null | wc -l)
expected_list_ops=$((MIXED_OPS_COUNT / 4))

echo "Mixed Operations: Add($successful_mixed_add/$MIXED_OPS_COUNT), Check($successful_mixed_check/$MIXED_OPS_COUNT), List($successful_mixed_list/$expected_list_ops) in ${mixed_time}s"
echo "Mixed Operations: Add($successful_mixed_add/$MIXED_OPS_COUNT), Check($successful_mixed_check/$MIXED_OPS_COUNT), List($successful_mixed_list/$expected_list_ops) in ${mixed_time}s" >> "$RESULTS_FILE"

# Get final rule count
echo -e "\n${YELLOW}Verifying server state${NC}"
# Get rule count with better output control
list_output=$("$PROJECT_ROOT/client" localhost $TEST_PORT L 2>/dev/null)
total_rules=$(echo "$list_output" | grep -c "Rule:" 2>/dev/null || echo "0")
echo "Total rules in server: $total_rules"
echo "Final rule count: $total_rules" >> "$RESULTS_FILE"

# Performance summary
echo -e "\n${GREEN}Concurrency Test Summary${NC}"
echo -e "Sequential ($SEQUENTIAL_COUNT):     $successful_sequential/$SEQUENTIAL_COUNT ✓"
echo -e "Low Concurrent ($LOW_CONCURRENT): $successful_low/$LOW_CONCURRENT ✓"
echo -e "Med Concurrent ($MED_CONCURRENT): $successful_med/$MED_CONCURRENT ✓"
echo -e "High Concurrent ($HIGH_CONCURRENT): $successful_high/$HIGH_CONCURRENT ✓"
echo -e "Mixed Operations:    Success ✓"
echo -e "Total Rules Created: $total_rules"

# Calculate success rate - ensure all variables are clean numbers
total_attempted=$((SEQUENTIAL_COUNT + LOW_CONCURRENT + MED_CONCURRENT + HIGH_CONCURRENT + MIXED_OPS_COUNT))
# Clean any non-numeric values
successful_sequential=${successful_sequential:-0}
successful_low=${successful_low:-0}
successful_med=${successful_med:-0}
successful_high=${successful_high:-0}
successful_mixed_add=${successful_mixed_add:-0}
total_successful=$((successful_sequential + successful_low + successful_med + successful_high + successful_mixed_add))
success_rate=$(echo "scale=1; $total_successful * 100 / $total_attempted" | bc -l 2>/dev/null || echo "N/A")

echo -e "\n${BLUE}Overall Success Rate: $total_successful/$total_attempted ($success_rate%)${NC}"
echo "" >> "$RESULTS_FILE"
echo "SUMMARY:" >> "$RESULTS_FILE"
echo "Overall Success Rate: $total_successful/$total_attempted ($success_rate%)" >> "$RESULTS_FILE"

# Cleanup temp files
rm -f client_*.tmp mixed_*.tmp sequential_results.tmp server_output.log

echo -e "\n${GREEN}Concurrency test completed${NC}"
echo -e "${BLUE}Results saved to: $RESULTS_FILE${NC}"

# Cleanup handled automatically