// ============================================================================
// gw.q - Non-Blocking Query Gateway with Deferred IPC (-30!) & Entitlements
// ============================================================================

\l src/common/util.q

.util.setProc[`GW];

\d .gw

// User Role & Entitlement Table
users:([user:`u#`symbol$()]
    role:`symbol$();
    allowedTables:();
    maxRows:`long$()
    );

`.gw.users upsert (`quant_desk;  `QUANT;      `trade`quote`lobDelta`lobSnapshot`parentOrder`childExecution`metrics1m; 10000000j);
`.gw.users upsert (`compliance;  `COMPLIANCE; `trade`quote`lobDelta`surveillanceAlert`parentOrder`childExecution;     10000000j);
`.gw.users upsert (`exec_trader; `TRADER;     `trade`quote`lobSnapshot`metrics1m`parentOrder`childExecution;          1000000j);
`.gw.users upsert (`guest;       `GUEST;      `metrics1m`lobSnapshot;                                                 10000j);

// Check if user is authorized for requested table
checkAccess:{[usr;tbl]
    u:$[usr in key[users]`user; usr; `guest];
    allowed:users[u]`allowedTables;
    if[not tbl in allowed;
        '`$"ACCESS_DENIED: User ",string[u]," is not permitted to query table ",string tbl];
    u
    };

// Pending deferred requests: clientHandle -> (startTime; targetService)
pending:([clientHandle:`int$()] startTime:`timestamp$(); service:`symbol$());

// Callback invoked by backend worker (RDB/HDB/RTE) when async query completes
callback:{[clientHandle;isError;result]
    `.gw.pending _ clientHandle;
    // -30!(handle; isError; result) sends deferred response to waiting client
    -30!(clientHandle; isError; result);
    };

// Dispatch asynchronous deferred query to backend service (`RDB, `HDB, or `RTE)
routeAsync:{[svc;expr]
    h:.util.connect svc;
    if[null h; '"SERVICE_UNAVAILABLE: ",string svc];
    clientH:.z.w;
    `.gw.pending upsert (clientH; .z.p; svc);
    // Send async request to worker; worker evaluates and calls back `.gw.callback`
    (neg h)({[ch;ex]
        res:@[(0b;)eval@; ex; {(1b;x)}];
        (neg .z.w)(`.gw.callback; ch; first res; last res)
        }; clientH; expr);
    // Defer response to client until callback arrives
    -30!(::)
    };

// Synchronous federated query across both HDB (historical dates) and RDB (today)
queryAcrossRdbHdb:{[tbl;syms;startTs;endTs]
    usr:$[null .z.u;`quant_desk;.z.u];
    checkAccess[usr;tbl];
    today:"d"$.z.P;
    qExpr:(`select; tbl; (`within;`time;(startTs;endTs)); (`in;`sym;enlist syms));
    res:();
    if[("d"$startTs) < today;
        hHdb:.util.connect`HDB;
        if[not null hHdb;
            res,:hHdb (`?[;((`within;`date;("d"$startTs;today-1));(`in;`sym;enlist syms));0b;()]; tbl)]];
    if[("d"$endTs) >= today;
        hRdb:.util.connect`RDB;
        if[not null hRdb;
            res,:hRdb (`?[;((`within;`time;(startTs;endTs));(`in;`sym;enlist syms));0b;()]; tbl)]];
    res
    };

\d .

port:.util.getOpt[`port;5014i];
rdbHp:.util.getOpt[`rdb;`localhost:5011];
hdbHp:.util.getOpt[`hdb;`localhost:5012];
rteHp:.util.getOpt[`rte;`localhost:5013];

system "p ",string port;

.util.registerConn[`RDB;`$":",string rdbHp];
.util.registerConn[`HDB;`$":",string hdbHp];
.util.registerConn[`RTE;`$":",string rteHp];

.util.info "Gateway listening on port ",string port;
