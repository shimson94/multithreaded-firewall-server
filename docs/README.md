# Multithreaded Firewall Server

A high-performance, thread-safe firewall server implementation in C that demonstrates scalable concurrent connection handling and rule management.

## 🎯 Key Achievements

- **100,000 concurrent connections** with 100% correctness validation (21.2 minutes execution)
- **957.85 ops/sec** peak throughput with mixed concurrent operations
- **941.79 ops/sec** sustained throughput under stress testing
- **Zero memory leaks** (Valgrind verified: 189/189, 607/607 allocations)
- **Thread-safe design** with proper mutex synchronisation and race condition prevention
- **Dynamic memory management** with efficient capacity scaling

## 🏗️ Architecture

### Core Components
- **Multithreaded Server**: POSIX threads with proper synchronisation
- **Dynamic Memory Management**: Growable rule and request storage
- **Network Protocol**: TCP client-server communication
- **Thread Safety**: Mutex-protected shared data structures

### Thread Model
```
Main Thread
├── Accept Loop (single-threaded)
└── Client Handlers (multi-threaded)
    ├── Request Processing (mutex-protected)
    ├── Rule Management (thread-safe)
    └── Response Generation
```

## 📊 Performance Metrics

### Stress Testing Results (test_stress.sh)
| Concurrency Level | Correctness | Throughput | Duration | Response Breakdown |
|-------------------|-------------|------------|----------|-------------------|
| 500 | 100.0% (500/500) | **941.79 ops/sec** | 0.53s | 107 new, 293 conflicts, 100 rejected |
| 1,000 | 100.0% (1000/1000) | **933.90 ops/sec** | 1.07s | 207 new, 593 conflicts, 200 rejected |
| 3,000 | 100.0% (3000/3000) | **926.24 ops/sec** | 3.24s | 607 new, 1793 conflicts, 600 rejected |
| 5,000 | 100.0% (5000/5000) | **743.62 ops/sec** | 6.72s | 1007 new, 2993 conflicts, 1000 rejected |
| 10,000 | 100.0% (10000/10000) | **741.31 ops/sec** | 13.49s | 2007 new, 5993 conflicts, 2000 rejected |
| **100,000** | 100.0% (100000/100000) | **114.12 ops/sec** | **876.22s (21.2 min)** | 20007 new, 59993 conflicts, 20000 rejected |

### Concurrency Testing Results (test_concurrency.sh)
| Test Level | Correctness | Throughput | Mixed Operations | Response Breakdown |
|------------|-------------|------------|------------------|-------------------|
| 100 | 100.0% (100/100) | 750.35 ops/sec | ADD/CHECK/LIST/DELETE | 5 new, 15 conflicts, 10 rejected |
| 500 | 100.0% (500/500) | 941.83 ops/sec | ADD/CHECK/LIST/DELETE | 25 new, 75 conflicts, 50 rejected |
| 1,000 | 100.0% (1000/1000) | **957.85 ops/sec** | ADD/CHECK/LIST/DELETE | 50 new, 150 conflicts, 100 rejected |
| 2,500 | 100.0% (2500/2500) | 947.22 ops/sec | ADD/CHECK/LIST/DELETE | 125 new, 375 conflicts, 250 rejected |

**Maximum Scale: 100,000 concurrent connections with 100% individual validation**

## 🚀 Features

### Firewall Operations
- **ADD**: Create firewall rules with IP/port ranges
- **CHECK**: Validate connections against active rules
- **DELETE**: Remove specific firewall rules
- **LIST**: Display all active rules with query history

### Advanced Capabilities
- **IP Range Support**: CIDR notation and range specifications
- **Port Range Support**: Single ports and port ranges
- **Query Tracking**: Maintains connection attempt history
- **Interactive Mode**: Command-line interface for testing
- **Network Mode**: TCP server for client connections

## 🛠️ Technical Implementation

### Memory Management
- **Dynamic Arrays**: Rules and requests grow automatically
- **Proper Cleanup**: All malloc/free pairs verified with enhanced cleanup verification
- **Memory Safety**: Valgrind shows 189/189, 607/607 perfect allocation ratios
- **Process Monitoring**: Complete process failure tracking and diagnostic reporting
- **414x Performance Optimization**: Real-time response classification using bash built-ins

### Concurrency Design
- **POSIX Threads**: One thread per client connection
- **Mutex Protection**: All shared data access synchronised
- **Thread Lifecycle**: Proper creation, execution, and cleanup
- **Resource Management**: Thread-safe socket handling

### Error Handling
- **Input Validation**: Comprehensive IP and port validation
- **Network Resilience**: Timeout handling and connection management
- **Memory Safety**: Buffer overflow protection and bounds checking

## 📁 Project Structure

```
multithreaded-firewall-server/
├── src/
│   ├── server.c              # Main server implementation
│   └── client.c              # Test client implementation
├── tests/
│   ├── test_concurrency.sh   # Concurrency performance tests
│   ├── test_memory.sh        # Memory leak detection
│   ├── test_stress.sh        # High-performance stress testing (10K connections)
│   └── cleanup.sh            # Cleanup utility
├── docs/
│   ├── README.md             # This file
│   └── PERFORMANCE.md        # Detailed performance analysis
├── test_results/            # Generated test results
│   ├── concurrency_results.txt     # Concurrency test output
│   ├── stress_results.txt          # Stress test metrics (up to 10K)
│   ├── max_stress_result_found.txt # Maximum scale test (100K connections)
│   ├── memory_test_results.txt     # Memory analysis results
│   └── valgrind_summary.txt        # Memory leak analysis
├── screenshots/              # Test output demonstrations
│   ├── concurrency_test.png  # Place concurrency test screenshot here
│   ├── memory_test.png       # Place memory test screenshot here
│   └── stress_test.png       # Place stress test screenshot here
└── Makefile                  # Build configuration
```

## 🧪 Testing & Validation

### Automated Test Suite
- **Concurrency Tests**: Mixed operations race condition testing with ADD/CHECK/LIST/DELETE
- **Memory Tests**: Valgrind-based leak detection with comprehensive error scenario coverage  
- **Stress Tests**: High-performance testing with up to 100,000 concurrent connections

### Testing Methodology Enhancements

**414x Test Validation Performance Improvement:**

**Before (Slow Approach):**
1. **Subprocess Overhead**: After all clients finished, run separate `grep | wc -l` commands to count different response types
2. **Multiple File Reads**: Read through all output files multiple times for different metrics
3. **Post-Processing Phase**: Wait for all tests to complete, then process results in separate step

**After (414x Faster):**
1. **Bash Built-ins**: Use bash string matching and variables instead of spawning subprocesses
2. **Real-time Classification**: Count response types as they're generated during test execution
3. **Single-Pass Processing**: Eliminate the separate post-processing phase entirely

**Additional Enhancements:**
- **Parallel chunk processing**: Enables efficient validation of large-scale tests without performance degradation

### Test Results Screenshots

#### Concurrency Test Results
*Screenshot showing 525 concurrent operations with 100% success rate*
![Concurrency Test](screenshots/concurrency_test.png)

#### Stress Test Performance
*Screenshot showing maximum concurrent connection handling*
![Stress Test](screenshots/stress_test.png)

#### Memory Leak Analysis
*Screenshot demonstrating zero memory leaks and perfect allocation/free ratios*
![Memory Test](screenshots/memory_test.png)

## 🔧 Build & Run

### Prerequisites
```bash
# Ubuntu/WSL
sudo apt update
sudo apt install build-essential valgrind

# Ensure gcc, pthread, and networking libraries are available
```

### Build
```bash
make clean && make
```

### Run Tests
```bash
# Concurrency performance test
cd tests && ./test_concurrency.sh

# Memory leak detection
cd tests && ./test_memory.sh

# Maximum load stress test
cd tests && ./test_stress.sh
```

### Interactive Mode
```bash
./server -i
# Commands: A <ip> <port>, C <ip> <port>, L, R, D <ip> <port>
```

### Network Mode
```bash
# Terminal 1 - Server
./server 2302

# Terminal 2 - Client
./client localhost 2302 A 192.168.1.1 80
./client localhost 2302 L
```

## 💡 Key Learning Outcomes

### Systems Programming
- **Multithreading**: POSIX threads, synchronisation primitives
- **Network Programming**: Socket programming, TCP protocols
- **Memory Management**: Dynamic allocation, leak prevention
- **Concurrency**: Thread safety, race condition prevention

### Software Engineering
- **Performance Testing**: Load testing, benchmarking methodologies
- **Quality Assurance**: Automated testing, memory validation
- **Documentation**: Technical specifications, performance metrics
- **Version Control**: Git workflow, professional presentation


## 🔬 Technical Details

### Server Performance Optimisations
- **Thread-Per-Client Model**: Efficient concurrent connection handling
- **Mutex-Protected Shared State**: Thread-safe rule management without race conditions
- **Dynamic Memory Scaling**: Capacity doubling strategy for efficient growth
- **Network Socket Optimisation**: Proper connection lifecycle management

### Production Readiness
- **Large-Scale Testing**: Tested up to 100,000 concurrent connections
- **Error Transparency**: Complete process failure tracking and diagnostic reporting
- **Memory Safety**: Valgrind-verified zero leaks (189/189, 607/607 allocations)
- **Input Validation**: Comprehensive IP/port validation with malformed input handling

## 📈 Scalability Analysis

The server demonstrates strong scalability characteristics:
- **Peak Performance**: 957.85 ops/sec with mixed operations (1,000 concurrent)
- **Maximum Scale**: 100,000 concurrent connections tested (21.2 minutes sustained)
- **High Reliability**: 100% correctness validation across all test levels
- **Memory Efficiency**: Zero leaks with dynamic scaling under extreme load

---

*This project demonstrates advanced systems programming capabilities including multithreading, network programming, and concurrent system design - validated through comprehensive testing at scale with up to 100,000 concurrent connections.*