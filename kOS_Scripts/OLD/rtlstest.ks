// ============================================================
//  rtls.ks  —  Quick launcher for testing
//  Usage: run rtls.
//  Reads pad coordinates from 0:/rtls_params.ks and runs
//  falcon9_rtls with those parameters.
// ============================================================

LOCAL paramsFile IS "0:/rtls_params.ks".

IF NOT EXISTS(paramsFile) {
    PRINT "ERROR: " + paramsFile + " not found.".
    PRINT "Launch normally first to generate params file.".
} ELSE {
    // Declare variables BEFORE running params so SET can find them
    GLOBAL rtls_pad_lat IS 0.
    GLOBAL rtls_pad_lng IS 0.
    
    RUN "0:/rtls_params.ks".

    PRINT "Pad: " + rtls_pad_lat + " / " + rtls_pad_lng.
    PRINT "Running falcon9_rtls...".

    RUN falcon9_rtls(rtls_pad_lat, rtls_pad_lng).
}