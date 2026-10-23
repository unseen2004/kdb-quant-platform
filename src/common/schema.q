// ============================================================================
// schema.q - Unified Schemas for Tick Plant, L2/L3 LOB, Orders, TCA & Alerts
// ============================================================================

\d .schema

// Market Trades (L1)
trade:([]
    time:`timestamp$();
    sym:`g#`symbol$();
    exchange:`symbol$();
    price:`float$();
    size:`float$();
    side:`symbol$();        // `B or `S (aggressor side)
    tradeId:`symbol$();
    cond:`char$()
    );

// Top-of-Book Quotes (L1 BBO)
quote:([]
    time:`timestamp$();
    sym:`g#`symbol$();
    exchange:`symbol$();
    bid:`float$();
    ask:`float$();
    bsize:`float$();
    asize:`float$()
    );

// L3 Order Book Delta Events (Add / Modify / Cancel / Execute)
lobDelta:([]
    time:`timestamp$();
    sym:`g#`symbol$();
    seqNum:`long$();
    orderId:`symbol$();
    traderId:`symbol$();
    action:`symbol$();      // `ADD`MOD`CAN`EXEC
    side:`symbol$();        // `B or `S
    price:`float$();
    size:`float$()
    );

// Reconstructed L2 Order Book Snapshots (Top 5 Levels)
lobSnapshot:([]
    time:`timestamp$();
    sym:`g#`symbol$();
    bidPrices:();           // list of float vectors (L1..L5)
    bidSizes:();            // list of float vectors (L1..L5)
    askPrices:();           // list of float vectors (L1..L5)
    askSizes:();            // list of float vectors (L1..L5)
    mid:`float$();
    spreadBps:`float$();
    imbalance:`float$();    // (bsize1 - asize1) / (bsize1 + asize1)
    microprice:`float$()    // volume-weighted mid price
    );

// Parent Orders (Institutional Algo Orders for TCA)
parentOrder:([]
    time:`timestamp$();
    parentId:`u#`symbol$();
    clientId:`symbol$();
    sym:`g#`symbol$();
    side:`symbol$();        // `B or `S
    algo:`symbol$();        // `VWAP`TWAP`IS`POV
    totalQty:`float$();
    arrivalPrice:`float$();
    startTime:`timestamp$();
    endTime:`timestamp$();
    limitPrice:`float$()
    );

// Child Executions (Fills linked to Parent Orders)
childExecution:([]
    time:`timestamp$();
    execId:`symbol$();
    parentId:`g#`symbol$();
    sym:`g#`symbol$();
    venue:`symbol$();       // `BINANCE`COINBASE`KRAKEN`LMAX
    side:`symbol$();
    fillPrice:`float$();
    fillQty:`float$();
    liquidityFlag:`symbol$(); // `MAKER or `TAKER
    feeBps:`float$()
    );

// Real-Time Intraday Aggregations (RTE Output)
metrics1m:([]
    time:`timestamp$();
    sym:`g#`symbol$();
    open:`float$();
    high:`float$();
    low:`float$();
    close:`float$();
    volume:`float$();
    vwap:`float$();
    twap:`float$();
    tradeCount:`long$()
    );

// Surveillance & Market Abuse Alerts (CEP Engine Output)
surveillanceAlert:([]
    time:`timestamp$();
    alertId:`symbol$();
    alertType:`symbol$();   // `SPOOFING`LAYERING`WASH_TRADE`MOMENTUM_IGNITION`FAT_FINGER
    severity:`symbol$();    // `LOW`MEDIUM`HIGH`CRITICAL
    sym:`g#`symbol$();
    traderId:`symbol$();
    metricValue:`float$();
    threshold:`float$();
    details:()              // string description
    );

\d .

// Initialize empty global tables from schema namespace
initTables:{[]
    { (`$string x) set value ` sv `.schema,x } each key[.schema] except `null;
    };
