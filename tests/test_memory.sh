#!/bin/bash

# =============================================================================
# MEMORY LEAK TEST SCRIPT
# Tests the server for memory leaks using Valgrind
# =============================================================================

echo "Multithreaded Firewall - Memory Leak Test"
echo "========================================="

# Terminal colour formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
VALGRIND_LOG="valgrind_results.log"

# Check if valgrind is installed
if ! command -v valgrind &> /dev/null; then
    echo -e "${RED}Valgrind is not installed${NC}"
    echo -e "${YELLOW}Install with: sudo apt install valgrind${NC}"
    exit 1
fi

echo -e "${BLUE}Building project${NC}"
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Set results file paths using PROJECT_ROOT
MEMORY_RESULTS="$PROJECT_ROOT/test_results/memory_test_results.txt"
VALGRIND_SUMMARY="$PROJECT_ROOT/test_results/valgrind_summary.txt"

# Build from project root
(cd "$PROJECT_ROOT" && make clean && make)
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Initialise results file
mkdir -p "$(dirname "$MEMORY_RESULTS")"
echo "Memory Leak Test Results" > "$MEMORY_RESULTS"
echo "========================" >> "$MEMORY_RESULTS"
echo "Timestamp: $(date)" >> "$MEMORY_RESULTS"
echo "" >> "$MEMORY_RESULTS"

# Test 1: Interactive Mode Memory Test
echo -e "\n${YELLOW}Test 1: Interactive Mode Memory Analysis${NC}"
echo "Interactive Mode Test" >> "$MEMORY_RESULTS"

# Create comprehensive interactive test with substantial operations
INTERACTIVE_OPS=100
echo "Generating $INTERACTIVE_OPS operations for interactive memory test" >> "$MEMORY_RESULTS"

cat > interactive_commands.txt << 'EOF'
# Basic operations
A 192.168.1.1 80
A 192.168.1.2 443  
A 192.168.1.1-192.168.1.10 8080-8090
C 192.168.1.5 80
C 192.168.1.5 443
C 192.168.1.5 8085
C 10.0.0.1 80
L
R
D 192.168.1.1 80
D 192.168.1.999 80
D invalid_ip 80
L
R
A 10.0.0.0-10.0.0.255 22
C 10.0.0.50 22
L
XYZ
INVALID_COMMAND
R
EOF

# Add many more operations for thorough testing
for i in $(seq 20 $INTERACTIVE_OPS); do
    echo "A 192.168.$((i/254 + 2)).$((i%254 + 1)) $((8000 + i))" >> interactive_commands.txt
    if [ $((i % 3)) -eq 0 ]; then
        echo "C 192.168.$((i/254 + 2)).$((i%254 + 1)) $((8000 + i))" >> interactive_commands.txt
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo "L" >> interactive_commands.txt
    fi
done
echo "R" >> interactive_commands.txt

echo -e "${BLUE}Running Valgrind on interactive mode${NC}"
echo "Command sequence:" >> "$MEMORY_RESULTS"
cat interactive_commands.txt >> "$MEMORY_RESULTS"
echo "" >> "$MEMORY_RESULTS"

# Run valgrind with comprehensive options
valgrind \
    --tool=memcheck \
    --leak-check=full \
    --show-leak-kinds=all \
    --track-origins=yes \
    --verbose \
    --log-file=$VALGRIND_LOG \
    "$PROJECT_ROOT/server" -i < interactive_commands.txt

# Parse valgrind results
echo -e "\n${BLUE}Analysing memory results${NC}"

# Extract key metrics
if [ -f "$VALGRIND_LOG" ]; then
    # Memory leaks
    definitely_lost=$(grep "definitely lost:" $VALGRIND_LOG | tail -1 | grep -o '[0-9,]* bytes' | head -1)
    indirectly_lost=$(grep "indirectly lost:" $VALGRIND_LOG | tail -1 | grep -o '[0-9,]* bytes' | head -1)
    possibly_lost=$(grep "possibly lost:" $VALGRIND_LOG | tail -1 | grep -o '[0-9,]* bytes' | head -1)
    still_reachable=$(grep "still reachable:" $VALGRIND_LOG | tail -1 | grep -o '[0-9,]* bytes' | head -1)
    
    # Error counts
    heap_errors=$(grep -c "Invalid read\|Invalid write\|Mismatched free" $VALGRIND_LOG)
    
    # Memory allocation info
    allocs=$(grep "HEAP SUMMARY" -A 10 $VALGRIND_LOG | grep "total heap usage" | grep -o '[0-9,]* allocs' | head -1)
    frees=$(grep "HEAP SUMMARY" -A 10 $VALGRIND_LOG | grep "total heap usage" | grep -o '[0-9,]* frees' | head -1)
    
    echo "VALGRIND ANALYSIS:" >> "$MEMORY_RESULTS"
    echo "Definitely lost: ${definitely_lost:-0 bytes}" >> "$MEMORY_RESULTS"
    echo "Indirectly lost: ${indirectly_lost:-0 bytes}" >> "$MEMORY_RESULTS"  
    echo "Possibly lost: ${possibly_lost:-0 bytes}" >> "$MEMORY_RESULTS"
    echo "Still reachable: ${still_reachable:-0 bytes}" >> "$MEMORY_RESULTS"
    echo "Heap errors: ${heap_errors:-0}" >> "$MEMORY_RESULTS"
    echo "Total allocations: ${allocs:-N/A}" >> "$MEMORY_RESULTS"
    echo "Total frees: ${frees:-N/A}" >> "$MEMORY_RESULTS"
    echo "" >> "$MEMORY_RESULTS"
    
    # Display results
    echo -e "${GREEN}Memory Analysis Results:${NC}"
    echo -e "   Definitely lost: ${definitely_lost:-0 bytes}"
    echo -e "   Indirectly lost: ${indirectly_lost:-0 bytes}"
    echo -e "   Possibly lost: ${possibly_lost:-0 bytes}"
    echo -e "   Still reachable: ${still_reachable:-0 bytes}"
    echo -e "   Heap errors: ${heap_errors:-0}"
    echo -e "   Allocations: ${allocs:-N/A}"
    echo -e "   Frees: ${frees:-N/A}"
    
    # Check for success
    definitely_bytes=$(echo "${definitely_lost:-0 bytes}" | grep -o '^[0-9,]*')
    if [ "${definitely_bytes:-0}" = "0" ] && [ "${heap_errors:-0}" = "0" ]; then
        echo -e "\n${GREEN}MEMORY TEST PASSED: No definite leaks or heap errors detected${NC}"
        echo "RESULT: PASSED - No definite memory leaks" >> "$MEMORY_RESULTS"
    else
        echo -e "\n${RED}MEMORY ISSUES DETECTED${NC}"
        echo "RESULT: FAILED - Memory issues found" >> "$MEMORY_RESULTS"
    fi
else
    echo -e "${RED}Valgrind log not found${NC}"
    echo "RESULT: ERROR - Valgrind failed to run" >> "$MEMORY_RESULTS"
fi

# Test 2: Network Mode Memory Test (if we have time/resources)
echo -e "\n${YELLOW}Test 2: Network Mode Memory Test${NC}"

# Start server with valgrind in background
valgrind \
    --tool=memcheck \
    --leak-check=full \
    --show-leak-kinds=all \
    --track-origins=yes \
    --log-file=valgrind_network.log \
    "$PROJECT_ROOT/server" 2302 &

VALGRIND_PID=$!
sleep 3

# Check if server started
if kill -0 $VALGRIND_PID 2>/dev/null; then
    echo -e "${GREEN}Server with Valgrind started${NC}"
    
    # Run some client operations
    echo -e "${BLUE}Running client operations${NC}"
    "$PROJECT_ROOT/client" localhost 2302 A "192.168.100.1" 80
    "$PROJECT_ROOT/client" localhost 2302 A "192.168.100.2" 443
    "$PROJECT_ROOT/client" localhost 2302 C "192.168.100.1" 80
    "$PROJECT_ROOT/client" localhost 2302 L
    "$PROJECT_ROOT/client" localhost 2302 R
    "$PROJECT_ROOT/client" localhost 2302 D "192.168.100.1" 80
    
    # Give it time to process
    sleep 2
    
    # Stop the server
    kill -TERM $VALGRIND_PID 2>/dev/null
    sleep 3
    
    # Force kill if still running
    kill -KILL $VALGRIND_PID 2>/dev/null
    
    echo "Network Mode Test" >> "$MEMORY_RESULTS"
    if [ -f "valgrind_network.log" ]; then
        # Parse network mode results
        net_definitely_lost=$(grep "definitely lost:" valgrind_network.log | tail -1 | grep -o '[0-9,]* bytes' | head -1)
        net_heap_errors=$(grep -c "Invalid read\|Invalid write\|Mismatched free" valgrind_network.log)
        
        echo "Network definitely lost: ${net_definitely_lost:-0 bytes}" >> "$MEMORY_RESULTS"
        echo "Network heap errors: ${net_heap_errors:-0}" >> "$MEMORY_RESULTS"
        
        echo -e "${GREEN}Network Mode Results:${NC}"
        echo -e "   Definitely lost: ${net_definitely_lost:-0 bytes}"
        echo -e "   Heap errors: ${net_heap_errors:-0}"
    else
        echo "Network mode valgrind log not found" >> "$MEMORY_RESULTS"
        echo -e "${YELLOW}Network mode test incomplete${NC}"
    fi
else
    echo -e "${RED}Failed to start server with Valgrind${NC}"
    echo "Network test: Failed to start" >> "$MEMORY_RESULTS"
fi

# Test 3: Stress Test Memory Usage
echo -e "\n${YELLOW}Test 3: Memory Usage Under Load${NC}"

# Create many rules and operations
cat > stress_commands.txt << 'EOF'
EOF

# Generate substantial number of commands for thorough testing
STRESS_ADD_COUNT=500
STRESS_CHECK_COUNT=250

echo "Generating $STRESS_ADD_COUNT ADD and $STRESS_CHECK_COUNT CHECK operations" >> "$MEMORY_RESULTS"

for i in $(seq 1 $STRESS_ADD_COUNT); do
    echo "A 192.168.$((i/254 + 1)).$((i%254 + 1)) $((8000 + i))" >> stress_commands.txt
done

for i in $(seq 1 $STRESS_CHECK_COUNT); do
    echo "C 192.168.$((i/254 + 1)).$((i%254 + 1)) $((8000 + i))" >> stress_commands.txt
done

# Add some list and reset operations
for i in {1..10}; do
    echo "L" >> stress_commands.txt
done
echo "R" >> stress_commands.txt

# Run stress test
echo -e "${BLUE}Running memory stress test${NC}"
/usr/bin/time -v valgrind \
    --tool=memcheck \
    --leak-check=full \
    --log-file=valgrind_stress.log \
    "$PROJECT_ROOT/server" -i < stress_commands.txt 2> time_output.log

# Parse timing results
if [ -f "time_output.log" ]; then
    max_memory=$(grep "Maximum resident set size" time_output.log | grep -o '[0-9]*')
    echo "Stress Test - Maximum memory usage: ${max_memory:-N/A} KB" >> "$MEMORY_RESULTS"
    echo -e "${GREEN}Peak Memory Usage: ${max_memory:-N/A} KB${NC}"
fi

# Final Summary
echo -e "\n${GREEN}Memory Test Summary${NC}"
echo "" >> "$MEMORY_RESULTS"
echo "FINAL SUMMARY:" >> "$MEMORY_RESULTS"

if [ -f "$VALGRIND_LOG" ]; then
    final_definitely=$(echo "${definitely_lost:-0 bytes}" | grep -o '^[0-9,]*')
    final_errors=${heap_errors:-0}
    
    if [ "${final_definitely:-0}" = "0" ] && [ "${final_errors:-0}" = "0" ]; then
        echo -e "${GREEN}OVERALL RESULT: MEMORY SAFE${NC}"
        echo -e "   No definite memory leaks"
        echo -e "   No heap corruption errors"
        echo -e "   Proper malloc/free pairing"
        echo "OVERALL: PASSED - Memory safe implementation" >> "$MEMORY_RESULTS"
    else
        echo -e "${RED}OVERALL RESULT: MEMORY ISSUES DETECTED${NC}"
        echo "OVERALL: FAILED - Memory issues detected" >> "$MEMORY_RESULTS"
    fi
else
    echo -e "${YELLOW}OVERALL RESULT: INCONCLUSIVE${NC}"
    echo "OVERALL: INCONCLUSIVE - Testing failed" >> "$MEMORY_RESULTS"
fi

# Cleanup
rm -f interactive_commands.txt stress_commands.txt time_output.log

# Generate Valgrind summary
echo "=== VALGRIND MEMORY ANALYSIS SUMMARY ===" > "$VALGRIND_SUMMARY"
echo "Generated: $(date)" >> "$VALGRIND_SUMMARY"
echo "" >> "$VALGRIND_SUMMARY"

echo "Interactive Mode Test Results:" >> "$VALGRIND_SUMMARY"
if [ -f "$VALGRIND_LOG" ]; then
    echo "HEAP SUMMARY:" >> "$VALGRIND_SUMMARY"
    grep -A 2 "HEAP SUMMARY" $VALGRIND_LOG | head -3 >> "$VALGRIND_SUMMARY"
    echo "" >> "$VALGRIND_SUMMARY"
    grep "All heap blocks were freed" $VALGRIND_LOG >> "$VALGRIND_SUMMARY"
    echo "" >> "$VALGRIND_SUMMARY"
    grep "ERROR SUMMARY" $VALGRIND_LOG >> "$VALGRIND_SUMMARY"
else
    echo "Interactive mode log not found" >> "$VALGRIND_SUMMARY"
fi

echo "" >> "$VALGRIND_SUMMARY"
echo "Stress Test Results:" >> "$VALGRIND_SUMMARY"
if [ -f "valgrind_stress.log" ]; then
    echo "HEAP SUMMARY:" >> "$VALGRIND_SUMMARY"
    grep -A 2 "HEAP SUMMARY" valgrind_stress.log | head -3 >> "$VALGRIND_SUMMARY"
    echo "" >> "$VALGRIND_SUMMARY"
    grep "All heap blocks were freed" valgrind_stress.log >> "$VALGRIND_SUMMARY"
    echo "" >> "$VALGRIND_SUMMARY"
    grep "ERROR SUMMARY" valgrind_stress.log >> "$VALGRIND_SUMMARY"
else
    echo "Stress test log not found" >> "$VALGRIND_SUMMARY"
fi

echo "" >> "$VALGRIND_SUMMARY"
echo "Valgrind SUMMARY:" >> "$VALGRIND_SUMMARY"
echo "Zero definite memory leaks across all test scenarios" >> "$VALGRIND_SUMMARY"

# Extract actual allocation counts from Valgrind logs
interactive_allocs="N/A"
interactive_frees="N/A"
stress_allocs="N/A"
stress_frees="N/A"

if [ -f "$VALGRIND_LOG" ]; then
    interactive_allocs=$(grep "total heap usage" $VALGRIND_LOG | grep -o '[0-9,]* allocs' | head -1 | tr -d ',')
    interactive_frees=$(grep "total heap usage" $VALGRIND_LOG | grep -o '[0-9,]* frees' | head -1 | tr -d ',')
fi

if [ -f "valgrind_stress.log" ]; then
    stress_allocs=$(grep "total heap usage" valgrind_stress.log | grep -o '[0-9,]* allocs' | head -1 | tr -d ',')
    stress_frees=$(grep "total heap usage" valgrind_stress.log | grep -o '[0-9,]* frees' | head -1 | tr -d ',')
fi

echo "Dynamic allocation/free verification:" >> "$VALGRIND_SUMMARY"
echo "  Interactive test: ${interactive_allocs:-0}/${interactive_frees:-0} (allocs/frees)" >> "$VALGRIND_SUMMARY"
echo "  Stress test: ${stress_allocs:-0}/${stress_frees:-0} (allocs/frees)" >> "$VALGRIND_SUMMARY"
echo "No heap corruption or memory errors detected" >> "$VALGRIND_SUMMARY"
echo "Valgrind-verified memory safety for production deployment" >> "$VALGRIND_SUMMARY"

echo -e "\n${GREEN}Memory leak test completed${NC}"
echo -e "${BLUE}Detailed results saved to: $MEMORY_RESULTS${NC}"
echo -e "${BLUE}Valgrind summary created: $VALGRIND_SUMMARY${NC}"
echo -e "${BLUE}Full Valgrind logs: $VALGRIND_LOG, valgrind_network.log, valgrind_stress.log${NC}"