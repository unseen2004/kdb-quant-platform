// ============================================================================
// hdb_maint.q - HDB Compression (-19!/-21!), Attribute Integrity & Query Audit
// ============================================================================

\d .hdb

// Query execution audit log
queryLog:([]
    time:`timestamp$();
    user:`symbol$();
    handle:`int$();
    sync:`boolean$();
    durationUs:`long$();
    memDeltaBytes:`long$();
    status:`symbol$();
    query:()
    );

slowThresholdUs:50000; // 50ms threshold for slow query warnings

// Profiled query wrapper for .z.pg and .z.ps
execTracked:{[isSync;q]
    t0:.z.p;
    m0:.Q.w[]`used;
    usr:$[null .z.u;`anon;.z.u];
    res:@[(1b;)value@;q;{(0b;x)}];
    dt:(`long$.z.p - t0) div 1000;
    dm:(.Q.w[]`used) - m0;
    st:$[first res;`OK;`ERR];
    `.hdb.queryLog insert (.z.p;usr;.z.w;isSync;dt;dm;st;enlist $[10h=type q;q;-3!q]);
    if[dt > slowThresholdUs;
        .util.warn "SLOW QUERY (",string[dt]," us) by ",string[usr],": ",$[10h=type q;q;-3!q]];
    if[not first res; 'last res];
    last res
    };

// Compression presets: (blockSize; algo; zipLevel)
// algo: 0=none, 1=kdb+ IPC, 2=gzip, 3=snappy, 4=lz4hc, 5=zstd
compressionPresets:(!) . flip (
    (`none;     17 0 0);
    (`kdb;      17 1 0);
    (`gzip;     17 2 6);
    (`snappy;   17 3 0);
    (`lz4;      17 4 6);
    (`zstd;     17 5 3)
    );

// Compress a splayed column file and return compression stats (-21!)
compressColumn:{[colPath;preset]
    params:compressionPresets preset;
    outPath:`$(string colPath),"_c";
    -19!(colPath;outPath),params;
    stats:-21!outPath;
    // Replace original column file with compressed file
    system "mv ",(1_string outPath)," ",(1_string colPath);
    @[stats;`ratio;:;stats[`uncompressedLength] % stats`compressedLength]
    };

// Benchmark compression presets on an in-memory table column
benchmarkCompression:{[tbl;col;tmpDir]
    system "mkdir -p ",tmpDir;
    srcPath:`$":",tmpDir,"/",string col;
    srcPath set tbl col;
    origBytes:hcount srcPath;
    runOne:{[srcPath;origBytes;tmpDir;preset]
        dstPath:`$":",tmpDir,"/",string[preset],"_",string last ` vs srcPath;
        t0:.z.p;
        // Fallback safely to kdb native if OS lacks external shared lib
        ok:@[{-19!x;1b};(srcPath;dstPath),compressionPresets preset;0b];
        dtUs:(`long$.z.p - t0) % 1000;
        if[not ok;
            :`preset`available`compBytes`ratio`writeTimeUs`readTimeUs!(preset;0b;origBytes;1f;0N;0N)];
        cBytes:hcount dstPath;
        t1:.z.p;
        _ : get dstPath;
        readUs:(`long$.z.p - t1) % 1000;
        `preset`available`compBytes`ratio`writeTimeUs`readTimeUs!(
            preset;1b;cBytes;origBytes % cBytes;dtUs;readUs)
        }[srcPath;origBytes;tmpDir;] each key compressionPresets;
    runOne
    };

// Audit parted (`#p`) and sorted (`#s`) attributes across a table
auditAttributes:{[tblName]
    v:value tblName;
    c:cols v;
    ([] table:count[c]#tblName;
        column:c;
        datatype:type each flip v;
        attribute:attr each flip v)
    };

\d .
