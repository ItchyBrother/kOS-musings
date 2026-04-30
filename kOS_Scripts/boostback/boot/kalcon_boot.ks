// ============================================================
//  kalcon_boot.ks  |  Kalcon Booster RTLS Boot Script
//  Kerbal Scale  |  Stock Aero
// ============================================================
//
//  PRE-FLIGHT SETUP (one time, from the Kalcon kOS terminal
//  while on the pad and the vessel is fully assembled):
//
//    PROCESSOR("Kalcon9"):BOOTFILENAME IS "kalcon_boot.ks".
//
//  Then copy this file and falcon9_rtls.ks to Kalcon's
//  volume 0 (the kOS disk on the Kalcon processor part).
//
//  ── HOW IT WORKS ─────────────────────────────────────────
//  kragon_ascent.ks writes pad coordinates to a small file
//  called rtls_params.ks on this volume just before activating
//  this processor.  This script checks for that file, loads
//  it if present, then runs falcon9_rtls.ks.
//
//  If rtls_params.ks is missing (e.g. testing standalone),
//  the hardcoded defaults below are used instead.
//
//  ── TIMING NOTE ──────────────────────────────────────────
//  This script starts when kragon_ascent.ks calls:
//      PROCESSOR("Kalcon9"):ACTIVATE()
//  It reads params, then waits for separation before handing
//  off to falcon9_rtls.ks.  The RTLS script itself expects
//  to start running at or near MECO.
// ============================================================

@LAZYGLOBAL OFF.
CLEARSCREEN.
PRINT "Kalcon boot — RTLS standby".

// ── Hardcoded fallback defaults ───────────────────────────
//  Edit these to match your landing site if running standalone.
GLOBAL rtls_pad_lat IS -0.0972.    // KSC Landing Zone 1
GLOBAL rtls_pad_lng IS -74.5577.
//GLOBAL rtls_pad_alt IS 67.

// ── Load parameters from Kragon if available ─────────────
//  kragon.ks writes rtls_params.ks containing SET statements for
//  rtls_pad_lat / rtls_pad_lng / rtls_pad_alt.
IF EXISTS("0:/rtls_params.ks") {
    PRINT "Loading pad params from Kragon...".
    RUNPATH("0:/rtls_params.ks").
    PRINT "  Pad: " + rtls_pad_lat + ", " + rtls_pad_lng.// Alt: " + rtls_pad_alt + " m".
} ELSE IF EXISTS("rtls_params.ks") {
    PRINT "Loading pad params from Kragon...".
    RUNPATH("rtls_params.ks").
    PRINT "  Pad: " + rtls_pad_lat + ", " + rtls_pad_lng.  //Alt: " + rtls_pad_alt + " m".
} ELSE {
    PRINT "No rtls_params.ks found — using hardcoded defaults.".
    PRINT "  Pad: " + rtls_pad_lat + ", " + rtls_pad_lng . //  Alt: " + rtls_pad_alt + " m".
}

PRINT "".
PRINT "Waiting for separation...".

// ── Wait for separation ───────────────────────────────────
//  Before separation we are still part of the Kragon vessel
//  and have no thrust of our own.  Wait until we are the
//  active vessel (kOS switches control when the Kalcon becomes
//  a separate vessel after staging) OR until the Kragon
//  processor deactivates us mid-flight (if you ever want that).
//
//  Detection method: SHIP:PARTCOUNT drops sharply when the
//  Kragon upper stage separates.  We cache the initial count
//  at boot time.  A significant drop means we are free.
//
//  Alternatively, watch SHIP:VELOCITY:SURFACE:MAG — once
//  Kragon ignites and accelerates away, our relative
//  velocity diverges.  Both checks are included; first one
//  to trigger wins.
LOCAL bootPartCount IS SHIP:PARTs:LENGTH.

UNTIL FALSE {
    LOCAL nowParts IS SHIP:PARTs:LENGTH.

    // Primary: part count dropped (separation occurred)
    IF nowParts < bootPartCount * 0.85 {
        PRINT "Separation detected — " + nowParts + " parts remain.".
        BREAK.
    }

    // Secondary: we are already in uncontrolled free fall
    // (SHIP:CONTROL:PILOTMAINTHROTTLE = 0 and engines are off,
    //  vertical speed is negative — i.e. we are past apoapsis)
    IF SHIP:VERTICALSPEED < -5 AND SHIP:AVAILABLETHRUST < 0.01 {
        PRINT "Free-fall detected — assuming post-separation.".
        BREAK.
    }

    WAIT 0.2.
}

PRINT "".
PRINT "Separation confirmed.  Handing off to RTLS...".
WAIT 0.5.
SWITCH TO 0.
// ── Hand off to RTLS script ───────────────────────────────
RUNPATH("0:/rtls.ks", rtls_pad_lat, rtls_pad_lng).

// ── If RTLS ever returns (touchdown) ─────────────────────
PRINT "RTLS returned — Kalcon script complete.".
UNLOCK THROTTLE.
UNLOCK STEERING.
SAS ON.
