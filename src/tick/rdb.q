// ============================================================================
// rdb.q - Real-Time Database with TP Log Replay, EOD Persistence & GC
// ============================================================================

\l src/common/schema.q
\l src/common/util.q

.util.setProc[`RDB];
initTables[];

\d .u

// Initialize schema and replay tickerplant log up to checkpoint
rep:{[tbls;logInfo]
    (.[;();:;].)each tbls;
    if[null first logInfo; :()];
    .util.info "Replaying ",string[first logInfo]," records from TP log ",string last logInfo;
    -11!logInfo;
    .util.info "TP log replay complete";
    };

// End-of-Day handler: splay tables to date partition in HDB, notify HDB, clear RAM
end:{[dt]
    t:tables`.;
    t@:where `g=attr each t@\:`sym;
    .util.info "Starting EOD save for date ",string[dt]," across tables: ",", " sv string t;
    // .Q.hdpf[hdbPort; hdbDir; partition; p#field]
    .Q.hdpf[`$":",string .rdb.hdbHostPort; `$(":",string .rdb.hdbDir); dt; `sym];
    @[;`sym;`g#] each t;
    .Q.gc[];
    .util.info "EOD save & garbage collection finished. Memory used: ",string .Q.w[]`used;
    };

\d .

// Standard insert handler for real-time updates
upd:insert;

// Configuration & Startup
port:.util.getOpt[`port;5011i];
.rdb.tpHostPort:.util.getOpt[`tp;`localhost:5010];
.rdb.hdbHostPort:.util.getOpt[`hdb;`localhost:5012];
.rdb.hdbDir:.util.getOpt[`hdbdir;`hdb];

system "p ",string port;
system "mkdir -p ",string .rdb.hdbDir;

// Connect to Tickerplant if available, subscribe to all tables & symbols, replay log
connectTP:{[]
    h:.util.registerConn[`TP;`$":",string .rdb.tpHostPort];
    if[not null h;
        .u.rep .(h"(.u.sub[`;`];`.u `i`L)");
        ];
    };

connectTP[];
.util.info "RDB ready on port ",string port;
