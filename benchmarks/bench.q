// ============================================================================
// bench.q - Latency & Throughput Benchmark Suite for kdb+ Quant Platform
// ============================================================================

\l src/common/schema.q
\l src/common/util.q
\l src/analytics/lob.q
\l src/analytics/tca.q
\l src/analytics/surveillance.q
\l src/native/native.q
\l src/tick/feed.q

.util.setProc[`BENCH];

runBenchmarks:{[]
    initTables[];
    -1 "\n====================================================================";
    -1 "kdb+ QUANT PLATFORM - PERFORMANCE BENCHMARK SUITE";
    -1 "====================================================================\n";

    // 1. Data Generation Throughput (100k trades + 100k quotes)
    bGen:.util.profile[`gen100kTradesAndQuotes; {.feed.populateSampleDataset[100000; 2000]}; ::];
    totalEvents:(count trade) + (count quote) + (count lobDelta);
    genThroughput:`long$1e6 * totalEvents % bGen`timeUs;

    // 2. L3 Order Book Delta Processing & L2 Extraction
    btcDeltas:select from lobDelta where sym=`BTCUSD;
    bLob:.util.profile[`lobDeltaProcessing; {.lob.processDeltas x; .lob.extractL2FromState[.lob.activeOrders;`BTCUSD;5]}; enlist btcDeltas];
    lobThroughput:`long$1e6 * (count btcDeltas) % bLob`timeUs;

    // 3. TCA Child Execution Markouts (aj across +1s, +5s, +10s, +60s)
    bTcaChild:.util.profile[`tcaChildMarkoutsAj; {.tca.analyzeChildFills[x;y]}; (childExecution; quote)];

    // 4. TCA Parent Order Interval VWAP/TWAP (wj1 across 100k trades)
    bTcaParent:.util.profile[`tcaParentIntervalWj1; {.tca.analyzeParentOrders[x;y;z;w]}; (parentOrder; childExecution; trade; quote)];

    // 5. Real-Time Surveillance CEP Suite (Spoofing + Layering + Wash + Momentum + Fat-Finger)
    bSurv:.util.profile[`surveillanceCepAll; {.surv.runAllChecks[x;y]}; (lobDelta; trade)];

    // 6. 1M Element Vectorized Microprice & VPIN Calculation
    n:1000000;
    bp:100f + n?10f; ap:bp + 0.01 + n?0.05f; bs:1f + n?50f; as:1f + n?50f;
    bMicro:.util.profile[`vectorized1MMicroprice; {.native.microprice[x;y;z;w]}; (bp;ap;bs;as)];
    microThroughput:`long$1e6 * n % bMicro`timeUs;

    summary:([]
        benchmark:`genDataset`lobReconstruction`tcaChildMarkoutsAj`tcaParentWj1`surveillanceCep`microprice1M;
        rowsProcessed:(totalEvents; count btcDeltas; count childExecution; count trade; (count lobDelta)+count trade; n);
        latencyUs:(bGen`timeUs; bLob`timeUs; bTcaChild`timeUs; bTcaParent`timeUs; bSurv`timeUs; bMicro`timeUs);
        latencyMs:0.001 * (bGen`timeUs; bLob`timeUs; bTcaChild`timeUs; bTcaParent`timeUs; bSurv`timeUs; bMicro`timeUs);
        throughputPerSec:(genThroughput; lobThroughput; `long$1e6*(count childExecution)%bTcaChild`timeUs; `long$1e6*(count trade)%bTcaParent`timeUs; `long$1e6*((count lobDelta)+count trade)%bSurv`timeUs; microThroughput);
        memDeltaKB:`long$(bGen`memDeltaBytes; bLob`memDeltaBytes; bTcaChild`memDeltaBytes; bTcaParent`memDeltaBytes; bSurv`memDeltaBytes; bMicro`memDeltaBytes) % 1024
        );

    show summary;
    summary
    };

runBenchmarks[];
if[`exit in key .Q.opt .z.x; exit 0];
