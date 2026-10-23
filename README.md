# kdb+/q Quantitative Trading, LOB Microstructure, TCA & Market Surveillance Platform

An end-to-end, institutional-grade **kdb+/q** quantitative finance platform combining four core production systems in a single cohesive codebase:

1. **Real-Time Tick Plant Architecture (`src/tick/`)**: Feedhandler $\rightarrow$ Tickerplant (`tp.q`) with binary write-ahead logging (`-11!`) $\rightarrow$ Real-Time Database (`rdb.q`) with EOD `.Q.hdpf` persistence & garbage collection $\rightarrow$ Partitioned Historical Database (`hdb.q`) with `-19!`/`-21!` columnar compression $\rightarrow$ Non-Blocking Query Gateway (`gw.q`) using deferred IPC (`-30!`) and role-based entitlements.
2. **L3-to-L2 Limit Order Book (LOB) Reconstruction & Slippage Engine (`src/analytics/lob.q`)**: Vectorized state transitions via scan (`\`) over L3 delta events (`ADD`, `MOD`, `CAN`, `EXEC`), point-in-time historical book reconstruction, volume-weighted microprice, multi-level exponential order book imbalance (OBI), and VWAP sweep slippage estimation.
3. **Transaction Cost Analysis (TCA) & Execution Algo Backtester (`src/analytics/tca.q`)**: Vectorized As-Of Joins (`aj`) for $+1\text{s}, +5\text{s}, +10\text{s}, +60\text{s}$ adverse-selection markouts, Window Joins (`wj1`) for interval VWAP/TWAP & Implementation Shortfall (bps), venue toxicity scorecards, and a TWAP / VWAP / POV execution simulator.
4. **Real-Time Market Surveillance & Anomaly Detection CEP Engine (`src/analytics/surveillance.q`)**: Event-driven Complex Event Processing (CEP) detecting **Spoofing**, **Layering**, **Wash Trading**, **Momentum Ignition** (rolling `mavg`/`mdev` z-scores), and **Fat-Finger** price dislocations in real time, streaming to a browser WebSocket UI (`dashboard/index.html`).

---

## System Architecture

```mermaid
flowchart LR
    subgraph Feeds["Market Data & Order Feeds"]
        SYN["Synthetic GBM + L3 Feed\n(src/tick/feed.q)"]
        BIN["Binance Live WS Feed\n(src/feed/binance_ws_feed.py)"]
    end

    subgraph TickPlant["kdb+ Core Tick Architecture"]
        TP["Tickerplant (tp.q :5010)\nPub/Sub (.u) + Binary Log"]
        TPLOG[("TP Write-Ahead Log\n(-11! Replay)")]
        RDB["Real-Time DB (rdb.q :5011)\nIn-Memory #g Tables"]
        HDB[("Partitioned HDB (hdb.q :5012)\n#p Parted + -19! Compressed")]
        RTE["Real-Time CEP Engine (rte.q :5013)\nLOB + TCA + Surveillance"]
    end

    subgraph Access["Client & Analytics Layer"]
        GW["Async Query Gateway (gw.q :5014)\nDeferred IPC (-30!) & RBAC"]
        DASH["Live WebSocket Dashboard\n(dashboard/index.html)"]
        C_EXT["C Shared Library (2:)\n(fast_microstructure.c)"]
    end

    SYN -->|".u.upd"| TP
    BIN -->|"PyKX / IPC"| TP
    TP -->|"Write-Ahead"| TPLOG
    TPLOG -.->|"-11! Recovery"| RDB
    TP -->|"Async Pub"| RDB
    TP -->|"Async Pub"| RTE
    RDB -->|".Q.hdpf EOD Rollover"| HDB
    GW <-->|"Federated IPC"| RDB
    GW <-->|"Federated IPC"| HDB
    GW <-->|"Federated IPC"| RTE
    RTE <-->|".z.ws JSON"| DASH
    C_EXT -.->|"Zero-Copy K Vectors"| RTE
```

---

## Repository Structure

```text
kdb-quant-platform/
├── src/
│   ├── common/
│   │   ├── schema.q                 # Schemas: trade, quote, lobDelta, lobSnapshot, parentOrder, childExecution, surveillanceAlert
│   │   └── util.q                   # Structured logging, IPC connection pool, CLI parser, profiling & vectorized quant math
│   ├── tick/
│   │   ├── u.q                      # Pub/Sub subscription management & EOD broadcast
│   │   ├── tp.q                     # Tickerplant with binary journal logging & zero-latency/batched modes
│   │   ├── rdb.q                    # Real-Time Database with -11! log recovery, EOD splay & .Q.gc[]
│   │   ├── hdb.q                    # Partitioned Historical Database server
│   │   ├── hdb_maint.q              # Columnar compression (-19!/-21!), #p/#s attribute audit & .z.pg slow query profiler
│   │   ├── rte.q                    # Real-Time CEP Engine (1m OHLCV/VWAP, Live LOB, Surveillance & WebSocket .z.ws server)
│   │   ├── gw.q                     # Non-blocking Gateway with deferred response (-30!) & table entitlements
│   │   └── feed.q                   # Vectorized GBM tick generator, L3 order book deltas & market abuse scenario injector
│   ├── analytics/
│   │   ├── lob.q                    # L3->L2 Order Book reconstruction, historical replay (\), microprice & slippage walk
│   │   ├── tca.q                    # TCA engine (aj markouts, wj1 interval VWAP/IS, venue scorecard, TWAP/VWAP/POV backtester)
│   │   └── surveillance.q           # Real-time detection of Spoofing, Layering, Wash Trading, Momentum Ignition & Fat-Fingers
│   ├── native/
│   │   ├── fast_microstructure.c    # C API (k.h) shared library for zero-copy vectorized Microprice & VPIN toxicity
│   │   └── native.q                 # Dynamic 2: loader with seamless pure-q vectorized fallback
│   └── feed/
│       └── binance_ws_feed.py       # Live Binance WebSocket L1/L2 feedhandler using PyKX / asyncio
├── dashboard/
│   └── index.html                   # Real-time WebSocket UI for L2 Order Book, TCA Markouts & Surveillance Alerts
├── tests/
│   └── test_all.q                   # Automated unit & integration test suite across all modules
├── benchmarks/
│   └── bench.q                      # Throughput & microsecond latency benchmark suite
├── scripts/
│   ├── run_stack.sh                 # Starts TP, RDB, HDB, RTE, Gateway & Live Feed
│   └── stop_stack.sh                # Gracefully stops all background processes
└── Makefile
```

---

## Quick Start

### 1. Build the C Native Extension (`2:`)
```bash
make native
```

### 2. Run the Automated Unit & Integration Test Suite
```bash
make test
# Or directly: q tests/test_all.q -exit
```

### 3. Run the Performance & Latency Benchmark Suite
```bash
make bench
# Or directly: q benchmarks/bench.q -exit
```

### 4. Launch the Full Multi-Process Tick Plant Stack
```bash
make start
# Open dashboard/index.html in any browser to view the live L2 Book, TCA & Surveillance feed
make stop
```

---

## Key Technical Highlights & Sample Queries

### 1. L3-to-L2 Order Book Reconstruction & VWAP Slippage (`src/analytics/lob.q`)
Reconstructs the top-5 L2 book at any historical nanosecond timestamp using functional scan/over (`\` / `/`) and estimates execution slippage by walking available liquidity levels:
```q
// Reconstruct BTCUSD L2 order book at a specific nanosecond timestamp
snap:.lob.reconstructAt[lobDelta; `BTCUSD; 2026.10.23D14:55:00.000000000; 5];

// Estimate VWAP fill price and market impact (bps) for sweeping 25 BTC on the Ask side
.lob.estimateSlippage[snap; `B; 25f]
// Returns: side| `B  requestedQty| 25f  filledQty| 25f  vwapFillPrice| 68502.4  slippageBps| 2.18  levelsSwept| 3
```

### 2. Post-Trade Markouts (`aj`) & Interval VWAP Implementation Shortfall (`wj1`) (`src/analytics/tca.q`)
Combines `aj` (for $+1\text{s}, +5\text{s}, +10\text{s}, +60\text{s}$ post-fill mid-price markouts) with `wj1` (for exact market volume-weighted average price over each parent order's active window):
```q
// Compute child fill markouts (+1s, +5s, +10s, +60s) and effective spread capture
childAnalysis:.tca.analyzeChildFills[childExecution; quote];

// Evaluate venue toxicity and maker/taker performance
.tca.venueScorecard[childAnalysis]

// Compute parent order Implementation Shortfall (IS) and VWAP slippage via wj1
.tca.analyzeParentOrders[parentOrder; childExecution; trade; quote]
```

### 3. Real-Time Market Surveillance CEP (`src/analytics/surveillance.q`)
Vectorized detection of 5 regulatory market abuse patterns:
* **Spoofing**: Large limit order additions (`size >= 15 BTC`) canceled within $<5\text{s}$ alongside opposite-side fills.
* **Layering**: Single trader placing and canceling $\ge 3$ distinct price levels on the same book side.
* **Wash Trading**: Self-matching `EXEC` events (`ej` across `sym`, `traderId`, `price`, `size` within $500\text{ms}$).
* **Momentum Ignition**: Simultaneous $>3\sigma$ rolling z-score (`mavg`/`mdev`) breakouts in aggressive volume and price velocity.
* **Fat-Finger**: Executions deviating $\ge 75\text{ bps}$ from rolling reference price.

---

## Representative Benchmarks

Measured via `benchmarks/bench.q` on standard x86_64 Linux hardware:

| Benchmark | Dataset Size | Latency (ms) | Throughput |
| :--- | :--- | :--- | :--- |
| **Synthetic GBM + L3 Dataset Generation** | 210,000 events | ~42 ms | ~5.0M events/sec |
| **L3-to-L2 Order Book Reconstruction** | 2,800 L3 deltas | ~3.1 ms | ~900K deltas/sec |
| **TCA Child Fill Markouts (`aj` x 5 horizons)** | 40 child fills vs 100K quotes | ~1.4 ms | Sub-millisecond per horizon |
| **TCA Parent Interval VWAP/TWAP (`wj1`)** | 5 parent orders vs 100K trades | ~2.8 ms | ~35M trade rows/sec scanned |
| **Surveillance CEP (All 5 Abuse Detectors)** | 114,000 combined events | ~11.5 ms | ~9.9M events/sec |
| **Vectorized Microprice (`2:` C / q)** | 1,000,000 quotes | ~1.9 ms | ~520M quotes/sec |

---

## License

Released under the [MIT License](LICENSE).
