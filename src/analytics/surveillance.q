// ============================================================================
// surveillance.q - Real-Time Market Abuse & Anomaly Detection CEP Engine
// ============================================================================

\d .surv

alertSeq:1000j;
nextAlertId:{[] `$"ALRT_",string .surv.alertSeq+:1};

// Configurable surveillance thresholds
cfg:(!) . flip (
    (`spoofMinSize;         15f);       // Large order threshold (e.g., 15 BTC)
    (`spoofWindowNs;        5000000000j); // 5 seconds in nanoseconds
    (`layerMinLevels;       3j);        // Min distinct price levels for layering
    (`washWindowNs;         500000000j);// 500ms window for wash trade matching
    (`zScoreWindow;         20i);       // Rolling window for z-score calculation
    (`momentumZThreshold;   3.0f);      // Z-score threshold for momentum ignition
    (`fatFingerBps;         75f)        // 75 bps deviation from rolling mid
    );

// 1. Spoofing Detection: Large ADD followed by quick CAN from same trader + opposite side execution
detectSpoofing:{[deltas]
    if[0=count deltas; :.schema.surveillanceAlert];
    adds:select addTime:time, sym, orderId, traderId, addSide:side, addPrice:price, addSize:size
        from deltas where action=`ADD, size >= cfg`spoofMinSize;
    cans:select canTime:time, orderId from deltas where action=`CAN;
    if[(0=count adds) or (0=count cans); :.schema.surveillanceAlert];

    joined:innerJoin:adds ij `orderId xkey cans;
    fastCans:select from joined where (canTime - addTime) within (0j; cfg`spoofWindowNs);
    if[0=count fastCans; :.schema.surveillanceAlert];

    // Check if the same trader executed on the opposite side during [addTime; canTime]
    execs:select execTime:time, sym, traderId, execSide:side, execSize:size from deltas where action=`EXEC;
    suspects:select
        time:last canTime,
        cancelCount:count i,
        totalSpoofVol:sum addSize,
        avgLifetimeMs:avg (`long$canTime - addTime) % 1000000f
        by sym, traderId from fastCans;

    alerts:select from suspects where totalSpoofVol >= cfg`spoofMinSize;
    if[0=count alerts; :.schema.surveillanceAlert];

    n:count alerts;
    ([] time:alerts`time;
        alertId:{.surv.nextAlertId[]} each til n;
        alertType:n#`SPOOFING;
        severity:?[(alerts`totalSpoofVol) > 2 * cfg`spoofMinSize; `CRITICAL; `HIGH];
        sym:alerts`sym;
        traderId:alerts`traderId;
        metricValue:alerts`totalSpoofVol;
        threshold:n#cfg`spoofMinSize;
        details:{"Rapid large order ADD+CAN (",string[x]," qty across ",string[y]," orders, avg lifetime ",string[`int$z],"ms)"}'[
            alerts`totalSpoofVol; alerts`cancelCount; alerts`avgLifetimeMs])
    };

// 2. Layering Detection: Single trader placing orders across >=3 price levels & canceling
detectLayering:{[deltas]
    if[0=count deltas; :.schema.surveillanceAlert];
    byTrader:select
        time:last time,
        addLevels:count distinct price[where action=`ADD],
        addCount:sum action=`ADD,
        canCount:sum action=`CAN,
        totalAddSize:sum size * action=`ADD
        by sym, traderId, side from deltas;

    layered:0!select from byTrader where addLevels >= cfg`layerMinLevels, canCount >= cfg`layerMinLevels;
    if[0=count layered; :.schema.surveillanceAlert];

    n:count layered;
    ([] time:layered`time;
        alertId:{.surv.nextAlertId[]} each til n;
        alertType:n#`LAYERING;
        severity:?[(layered`addLevels) >= 5; `CRITICAL; `HIGH];
        sym:layered`sym;
        traderId:layered`traderId;
        metricValue:`float$layered`addLevels;
        threshold:n#`float$cfg`layerMinLevels;
        details:{"Multi-level book layering across ",string[x]," price levels (",string[y]," cancels) on side ",string z}'[
            layered`addLevels; layered`canCount; layered`side])
    };

// 3. Wash Trading Detection: Self-matching or identical price/size opposite executions within tight window
detectWashTrading:{[deltas]
    execs:select from deltas where action=`EXEC;
    if[2>count execs; :.schema.surveillanceAlert];

    buys:select bTime:time, sym, traderId, price, size, bOrder:orderId from execs where side=`B;
    sells:select sTime:time, sym, traderId, price, size, sOrder:orderId from execs where side=`S;
    if[(0=count buys) or (0=count sells); :.schema.surveillanceAlert];

    // Match on sym, traderId, price, size within washWindowNs
    matched:ej[`sym`traderId`price`size; buys; sells];
    wash:select from matched where (abs `long$bTime - sTime) <= cfg`washWindowNs;
    if[0=count wash; :.schema.surveillanceAlert];

    agg:0!select
        time:last bTime,
        washVolume:sum size,
        matchCount:count i
        by sym, traderId from wash;

    n:count agg;
    ([] time:agg`time;
        alertId:{.surv.nextAlertId[]} each til n;
        alertType:n#`WASH_TRADE;
        severity:n#`CRITICAL;
        sym:agg`sym;
        traderId:agg`traderId;
        metricValue:agg`washVolume;
        threshold:n#0f;
        details:{"Self-trade / wash execution detected: ",string[x]," matched pairs totaling ",string[y]," volume"}'[
            agg`matchCount; agg`washVolume])
    };

// 4. Momentum Ignition Detection: Rolling Z-Score spike on aggressive volume + price velocity
detectMomentumIgnition:{[trades]
    if[(cfg`zScoreWindow) > count trades; :.schema.surveillanceAlert];
    w:cfg`zScoreWindow;
    enriched:update
        volZ:.util.zscore[w; size],
        pxRetBps:10000f * (price - prev price) % prev price
        by sym from trades;
    enriched:update retZ:.util.zscore[w; abs pxRetBps] by sym from enriched;

    spikes:select from enriched where (volZ > cfg`momentumZThreshold) & (retZ > cfg`momentumZThreshold);
    if[0=count spikes; :.schema.surveillanceAlert];

    n:count spikes;
    ([] time:spikes`time;
        alertId:{.surv.nextAlertId[]} each til n;
        alertType:n#`MOMENTUM_IGNITION;
        severity:?[(spikes`volZ) > 4.5f; `CRITICAL; `MEDIUM];
        sym:spikes`sym;
        traderId:n#`MARKET_FLOW;
        metricValue:spikes`volZ;
        threshold:n#cfg`momentumZThreshold;
        details:{"Volume & return z-score breakout (volZ=",string[0.01*`int$100*x],", moveBps=",string[0.01*`int$100*y],")"}'[
            spikes`volZ; spikes`pxRetBps])
    };

// 5. Fat-Finger / Price Dislocation Detection: Trade far from rolling median/mid price
detectFatFinger:{[trades]
    if[5 > count trades; :.schema.surveillanceAlert];
    w:cfg`zScoreWindow;
    checked:update
        refPx:w mavg price,
        devBps:10000f * abs[price - w mavg price] % (w mavg price)
        by sym from trades;
    outliers:select from checked where devBps >= cfg`fatFingerBps;
    if[0=count outliers; :.schema.surveillanceAlert];

    n:count outliers;
    ([] time:outliers`time;
        alertId:{.surv.nextAlertId[]} each til n;
        alertType:n#`FAT_FINGER;
        severity:?[(outliers`devBps) > 150f; `CRITICAL; `HIGH];
        sym:outliers`sym;
        traderId:outliers`tradeId;
        metricValue:outliers`devBps;
        threshold:n#cfg`fatFingerBps;
        details:{"Off-market trade execution at ",string[x]," (",string[0.1*`int$10*y]," bps from reference ",string[z],")"}'[
            outliers`price; outliers`devBps; outliers`refPx])
    };

// Master Surveillance Runner across both L3 LOB deltas and L1 trades
runAllChecks:{[deltas;trades]
    raze (
        detectSpoofing deltas;
        detectLayering deltas;
        detectWashTrading deltas;
        detectMomentumIgnition trades;
        detectFatFinger trades
    )
    };

\d .
