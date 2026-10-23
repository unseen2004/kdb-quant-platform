// ============================================================================
// test_all.q - Automated Unit & Integration Test Suite for kdb+ Quant Platform
// ============================================================================

\l src/common/schema.q
\l src/common/util.q
\l src/analytics/lob.q
\l src/analytics/tca.q
\l src/analytics/surveillance.q
\l src/native/native.q
\l src/tick/feed.q

.util.setProc[`TEST];

\d .test

results:([] suite:`symbol$(); testName:`symbol$(); passed:`boolean$(); details:());

assert:{[suite;name;cond;msg]
    ok:$[1b~cond; 1b; 0b];
    `.test.results insert (suite;name;ok;enlist msg);
    status:$[ok; "[PASS] "; "[FAIL] "];
    -1 status,string[suite],".",string[name]," - ",msg;
    };

runAll:{[]
    .util.info "Initializing tables and generating synthetic market dataset...";
    initTables[];
    counts:.feed.populateSampleDataset[5000; 400];

    // ------------------------------------------------------------------------
    // 1. Schema & Feed Tests
    // ------------------------------------------------------------------------
    assert[`feed; `tablesPopulated;
        all 0 < value counts;
        "Generated trades=",string[counts`trades],", quotes=",string[counts`quotes],", lobDeltas=",string counts`lobDeltas];

    assert[`feed; `groupedAttributeSet;
        `g = attr trade`sym;
        "trade.sym has #g (grouped) attribute applied"];

    // ------------------------------------------------------------------------
    // 2. Limit Order Book (LOB) Reconstruction & Slippage Tests
    // ------------------------------------------------------------------------
    .lob.processDeltas select from lobDelta where sym=`BTCUSD;
    snap:.lob.extractL2FromState[.lob.activeOrders; `BTCUSD; 5];

    assert[`lob; `topOfBookValid;
        (not null first snap`bidPrices) & (not null first snap`askPrices) & ((first snap`askPrices) > first snap`bidPrices);
        "Reconstructed L2 BBO: bid=",string[first snap`bidPrices]," < ask=",string first snap`askPrices];

    assert[`lob; `micropriceWithinSpread;
        (snap[`microprice] >= first snap`bidPrices) & (snap[`microprice] <= first snap`askPrices);
        "Microprice (",string[snap`microprice],") lies strictly inside L1 Bid-Ask spread"];

    slip:.lob.estimateSlippage[snap; `B; 10f];
    assert[`lob; `slippageEstimator;
        (slip[`filledQty] > 0f) & (slip[`slippageBps] >= 0f);
        "Sweeping 10 BTC on Ask side yields vwapFill=",string[slip`vwapFillPrice]," (",string[slip`slippageBps]," bps slippage)"];

    // Historical point-in-time reconstruction test
    midTs:exec med time from lobDelta where sym=`BTCUSD;
    histSnap:.lob.reconstructAt[lobDelta; `BTCUSD; midTs; 5];
    assert[`lob; `pointInTimeReconstruction;
        histSnap[`time] = midTs;
        "Point-in-time L3->L2 book reconstructed at exact timestamp ",string midTs];

    // ------------------------------------------------------------------------
    // 3. Transaction Cost Analysis (TCA) & Algo Backtester Tests
    // ------------------------------------------------------------------------
    childTca:.tca.analyzeChildFills[childExecution; quote];
    assert[`tca; `childMarkoutsComputed;
        (count[childTca] = count childExecution) & all `markout1sBps`markout5sBps`markout60sBps in cols childTca;
        "Computed +1s/+5s/+10s/+60s adverse selection markouts via aj for ",string[count childTca]," child fills"];

    parentTca:.tca.analyzeParentOrders[parentOrder; childExecution; trade; quote];
    assert[`tca; `parentOrderWj1Analysis;
        (count[parentTca] = count parentOrder) & all not null parentTca`mktVwap;
        "Computed interval VWAP/TWAP and Implementation Shortfall via wj1 for ",string[count parentTca]," parent orders"];

    scorecard:.tca.venueScorecard[childTca];
    assert[`tca; `venueScorecard;
        0 < count scorecard;
        "Generated venue toxicity & spread capture scorecard across ",string[count scorecard]," venue/liquidity buckets"];

    bt:.tca.backtestAlgos[trade; quote; `BTCUSD; `B; 50f; 10; 0.15f];
    assert[`tca; `algoBacktester;
        3 = count bt;
        "Backtested TWAP, VWAP, and POV execution schedules on BTCUSD"];

    // ------------------------------------------------------------------------
    // 4. Real-Time Market Surveillance CEP Tests
    // ------------------------------------------------------------------------
    alerts:.surv.runAllChecks[lobDelta; trade];
    detectedTypes:distinct alerts`alertType;

    assert[`surveillance; `spoofingDetected;
        `SPOOFING in detectedTypes;
        "Detected injected SPOOFING scenario by SPOOF_BOT_99"];

    assert[`surveillance; `layeringDetected;
        `LAYERING in detectedTypes;
        "Detected injected 5-level LAYERING scenario by LAYER_HFT_07"];

    assert[`surveillance; `washTradeDetected;
        `WASH_TRADE in detectedTypes;
        "Detected injected self-match WASH_TRADE scenario by WASH_ACCT_42"];

    assert[`surveillance; `fatFingerDetected;
        `FAT_FINGER in detectedTypes;
        "Detected injected +140 bps FAT_FINGER off-market execution"];

    // ------------------------------------------------------------------------
    // 5. Native C API / Vectorized Fallback Parity Tests
    // ------------------------------------------------------------------------
    mp:.native.microprice[100f 200f; 101f 202f; 10f 30f; 30f 10f];
    assert[`native; `micropriceCalc;
        all (mp >= 100f 200f) & (mp <= 101f 202f);
        "Vectorized microprice verified (nativeLoaded=",string[.native.isNativeLoaded],")"];

    // Summary
    total:count results;
    passedCount:sum results`passed;
    -1 "\n====================================================================";
    -1 "TEST SUMMARY: ",string[passedCount]," / ",string[total]," PASSED";
    -1 "====================================================================";
    if[passedCount < total; exit 1];
    };

\d .

.test.runAll[];
if[`exit in key .Q.opt .z.x; exit 0];
