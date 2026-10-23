// ============================================================================
// tca.q - Transaction Cost Analysis (aj/wj1 Markouts, IS) & Algo Backtester
// ============================================================================

\d .tca

// Compute Child Execution Markouts (+1s, +5s, +10s, +60s) & Spread Capture via `aj`
analyzeChildFills:{[fills;quotes]
    if[(0=count fills) or (0=count quotes); :()];
    qSorted:`sym`time xasc select sym, time, bid, ask, mid:0.5*bid+ask from quotes;
    qSorted:update `p#sym from qSorted;

    // 1. Prevailing quote at fill time (t=0)
    f0:aj[`sym`time; fills; qSorted];

    // 2. Future quotes at +1s, +5s, +10s, +60s for adverse selection markouts
    qFuture:select sym, time, midFuture:mid from qSorted;
    f1:aj[`sym`time; select sym, time:time+0D00:00:01, execId from fills; qFuture];
    f5:aj[`sym`time; select sym, time:time+0D00:00:05, execId from fills; qFuture];
    f10:aj[`sym`time; select sym, time:time+0D00:00:10, execId from fills; qFuture];
    f60:aj[`sym`time; select sym, time:time+0D00:01:00, execId from fills; qFuture];

    res:f0 lj (`execId xkey select execId, mid1s:midFuture from f1)
           lj (`execId xkey select execId, mid5s:midFuture from f5)
           lj (`execId xkey select execId, mid10s:midFuture from f10)
           lj (`execId xkey select execId, mid60s:midFuture from f60);

    // Direction multiplier: +1 for Buy, -1 for Sell
    // Positive markout means price moved in favor of our trade after execution;
    // Negative markout indicates adverse selection / toxic flow.
    update
        dir:?[side=`B; 1f; -1f],
        effectiveSpreadBps:?[side=`B; 1f; -1f] * 10000f * (fillPrice - mid) % mid,
        markout1sBps:?[side=`B; 1f; -1f] * 10000f * (mid1s - fillPrice) % fillPrice,
        markout5sBps:?[side=`B; 1f; -1f] * 10000f * (mid5s - fillPrice) % fillPrice,
        markout10sBps:?[side=`B; 1f; -1f] * 10000f * (mid10s - fillPrice) % fillPrice,
        markout60sBps:?[side=`B; 1f; -1f] * 10000f * (mid60s - fillPrice) % fillPrice
    from res
    };

// Full Parent Order TCA using Window Join (`wj1`) for Interval VWAP/TWAP & Implementation Shortfall
analyzeParentOrders:{[parents;fills;trades;quotes]
    if[(0=count parents) or (0=count fills) or (0=count trades); :()];

    // Aggregate child fills by parentId
    childAgg:select
        filledQty:sum fillQty,
        execVwap:fillQty wavg fillPrice,
        avgFeeBps:fillQty wavg feeBps,
        makerRatio:(sum fillQty * liquidityFlag=`MAKER) % sum fillQty,
        childCount:count i
        by parentId from fills;

    pJoined:parents lj childAgg;

    // Prepare trades for wj1 across each parent order's [startTime; endTime] window
    tSorted:`sym`time xasc select sym, time, mktPrice:price, mktSize:size from trades;
    tSorted:update `p#sym from tSorted;
    pSorted:`sym`startTime xasc update time:startTime from pJoined;

    w:(pSorted`startTime; pSorted`endTime);
    withMkt:wj1[w; `sym`time; pSorted; (tSorted; (wavg;`mktSize;`mktPrice); (avg;`mktPrice); (sum;`mktSize))];
    withMkt:`mktVwap`mktTwap`mktVolume xcol withMkt;

    // Calculate Implementation Shortfall (IS), VWAP Slippage, TWAP Slippage (in bps)
    // Convention: negative bps = cost/underperformance vs benchmark; positive bps = price improvement
    update
        fillRate:filledQty % totalQty,
        participationRate:?[mktVolume>0f; filledQty % mktVolume; 0f],
        isBps:?[side=`B; -1f; 1f] * 10000f * (execVwap - arrivalPrice) % arrivalPrice,
        vwapSlippageBps:?[side=`B; -1f; 1f] * 10000f * (execVwap - mktVwap) % mktVwap,
        twapSlippageBps:?[side=`B; -1f; 1f] * 10000f * (execVwap - mktTwap) % mktTwap,
        netIsBps:(?[side=`B; -1f; 1f] * 10000f * (execVwap - arrivalPrice) % arrivalPrice) - avgFeeBps
    from withMkt
    };

// Venue Toxicity & Execution Quality Scorecard
venueScorecard:{[analyzedFills]
    select
        fillCount:count i,
        totalVolume:sum fillQty,
        makerShare:100f * (sum fillQty * liquidityFlag=`MAKER) % sum fillQty,
        avgEffSpreadBps:fillQty wavg effectiveSpreadBps,
        markout1sBps:fillQty wavg markout1sBps,
        markout5sBps:fillQty wavg markout5sBps,
        markout10sBps:fillQty wavg markout10sBps,
        markout60sBps:fillQty wavg markout60sBps,
        avgFeeBps:fillQty wavg feeBps
    by venue, liquidityFlag from analyzedFills
    };

// Vectorized Algo Execution Backtester: compare TWAP, VWAP, and POV strategies on historical ticks
backtestAlgos:{[trades;quotes;s;side;totalQty;numSlices;povRate]
    tSub:select from trades where sym=s;
    qSub:`sym`time xasc select from quotes where sym=s;
    qSub:update `p#sym from qSub;
    if[(0=count tSub) or (0=count qSub); :()];

    t0:first tSub`time;
    t1:last tSub`time;
    arrivalPx:exec first 0.5*bid+ask from qSub where time>=t0;
    bucketNs:(`long$t1 - t0) div numSlices;

    buckets:update bucketId:bucketNs xbar `long$(time - t0) from tSub;
    bStats:0!select
        sliceStart:first time,
        sliceEnd:last time,
        mktVwap:size wavg price,
        mktTwap:avg price,
        mktVol:sum size
        by bucketId from buckets;

    // 1. TWAP Strategy: equal quantity per time slice executed at slice midpoint quote + half spread
    twapSliceQty:totalQty % count bStats;
    twapPx:sum[twapSliceQty * bStats`mktTwap] % totalQty;

    // 2. Historical Volume-Weighted (VWAP) Schedule: proportional to bucket volume
    volWeights:(bStats`mktVol) % sum bStats`mktVol;
    vwapSizes:totalQty * volWeights;
    vwapPx:sum[vwapSizes * bStats`mktVwap] % totalQty;

    // 3. POV (Percentage of Volume) Strategy: participate at `povRate` up to `totalQty`
    rawPov:povRate * bStats`mktVol;
    cumPov:sums rawPov;
    prevCum:0f, -1 _ cumPov;
    povSizes:0f | (totalQty - prevCum) & rawPov;
    povFilled:sum povSizes;
    povPx:$[povFilled>0f; sum[povSizes * bStats`mktVwap] % povFilled; 0n];

    dir:$[side=`B; -1f; 1f];
    mktBenchmark:exec size wavg price from tSub;

    ([] algo:`TWAP`VWAP`POV;
        sym:3#s;
        side:3#side;
        targetQty:3#totalQty;
        filledQty:(totalQty; totalQty; povFilled);
        arrivalPrice:3#arrivalPx;
        execPrice:(twapPx; vwapPx; povPx);
        mktVwap:3#mktBenchmark;
        isBps:dir * 10000f * ((twapPx; vwapPx; povPx) - arrivalPx) % arrivalPx;
        vwapSlippageBps:dir * 10000f * ((twapPx; vwapPx; povPx) - mktBenchmark) % mktBenchmark)
    };

\d .
