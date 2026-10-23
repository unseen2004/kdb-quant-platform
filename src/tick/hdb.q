// ============================================================================
// hdb.q - Partitioned Historical Database with Query Profiling & Compression
// ============================================================================

\l src/common/util.q
\l src/tick/hdb_maint.q

.util.setProc[`HDB];

port:.util.getOpt[`port;5012i];
hdbDir:string .util.getOpt[`hdbdir;`hdb];

system "p ",string port;
system "mkdir -p ",hdbDir;

// Load HDB directory if partitions exist
reload:{[]
    if[count key hsym `$hdbDir;
        system "l ",hdbDir;
        .util.info "Loaded HDB from ",hdbDir,". Tables: ",", " sv string tables`.;
        ];
    };

reload[];
.util.info "HDB listening on port ",string port;
