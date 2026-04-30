// ============================================================
//  falcon9_rtls.ks  |  RTLS Guidance  |  Kerbal Scale
//  Clean rewrite — grid fin lateral steering, two-burn profile
// ============================================================
//  Usage (from kalcon_boot.ks or terminal):
//    run falcon9_rtls(PAD_LAT, PAD_LNG, PAD_ALT).
//
//  VAB Action Groups:
//    AG1  Grid fins deploy
//    AG2  Enable 3 center engines (called at script start)
//    AG3  Shut down 2 outer engines (1 engine remaining)
//    GEAR Landing legs
//
//  Two-burn profile (mimics real Falcon 9):
//    1. Entry burn  — ~40km ASL, kills speed to 400 m/s
//    2. Landing burn — suicide burn from ~10-15km to touchdown
//
//  Grid fins (AG1) deploy during coast and steer the booster
//  laterally toward the pad during aero descent — no bias
//  constants needed.
//
//  Log: 0:/rtls_log.txt
// ============================================================

@LAZYGLOBAL OFF.

// ============================================================
//  PARAMETERS  (compatible with existing rtls_params.ks)
// ============================================================
PARAMETER PAD_LAT IS -0.0972.
PARAMETER PAD_LNG IS -74.5577.
PARAMETER PAD_ALT IS 67.

// ── Entry burn ──────────────────────────────────────────────
LOCAL ENTRY_ALT      IS 40000.  // ASL (m) — arm entry burn below this
LOCAL ENTRY_SPEED    IS 400.    // m/s surface speed to END entry burn

// ── Grid fin steering ───────────────────────────────────────
LOCAL FIN_AUTH_COAST IS 15.     // % authority during coast (passive drag)
LOCAL FIN_AUTH_AERO  IS 60.     // % authority during aero (active steering)
LOCAL LEAN_MAX_DEG   IS 10.     // max lean angle toward pad (degrees)
LOCAL LEAN_FULL_KM   IS 4.      // km — full lean applied beyond this distance
LOCAL LEAN_FADE_KM   IS 0.3.    // km — lean fades to zero inside this distance

// ── Landing burn ────────────────────────────────────────────
LOCAL VSPEED_COEFF   IS 0.10.   // P-controller: tgtVS = -(altAGL * coeff)
//  At 2000m: -200 m/s (freefall through)
//  At 1000m: -100 m/s (braking starts)
//  At  500m: -50  m/s
//  At  200m: -20  m/s
//  At  100m: -10  m/s (1-engine takes over)
LOCAL FINAL_VSPEED   IS -2.0.   // touchdown speed floor (m/s)
LOCAL CTRL_KP        IS 0.65.   // P-gain on vertical speed error
LOCAL MAX_DESCENT    IS -200.   // fastest target VS under P-control (m/s)
LOCAL BRAKE_EXIT_VS  IS -80.    // m/s — exit SRFRETROGRADE brake phase

// ── Engine config ───────────────────────────────────────────
//  3 engines: 840 kN  hover floor 33%
//  1 engine @ 100%: 400 kN  hover floor 68%
LOCAL MIN_THR_3ENG   IS 0.33.
LOCAL MIN_THR_1ENG   IS 0.68.
LOCAL SWITCH_ALT     IS 200.    // AGL (m) — 3->1 engine when VS > -15

// ── Boostback ───────────────────────────────────────────────
LOCAL BB_TOL_KM      IS 0.5.    // terminate when predicted impact < this from pad
LOCAL PRED_INTERVAL  IS 1.      // seconds between ballistic predictions
LOCAL BB_NORTH_AIM   IS 0.04.  // aim 1km north of pad during boostback

// ── Leg deployment ──────────────────────────────────────────
LOCAL LEG_DEPLOY_ALT IS 500.    // AGL (m)

// ── Brake geometry ──────────────────────────────────────────
LOCAL BRAKE_ANGLE    IS 35.     // max degrees from vertical for brake burn

// ── Lateral correction during descent ───────────────────────
//  Two-axis cascaded control: position→velocity→tilt.
//  North and east controlled independently — corrects drift
//  in ALL directions for any pad location automatically.
LOCAL LAT_KP_POS IS 0.004.    // outer: m/s commanded per m of error
LOCAL LAT_MAX_VEL IS 20.0.    // m/s — max commanded lateral velocity
LOCAL LAT_KP_VEL IS 1.5.      // inner: degrees tilt per m/s vel error
LOCAL LAT_MAX_DEG IS 20.0.    // hard tilt cap (degrees)
LOCAL KERBIN_M_PER_DEG IS 10471. // metres per degree on Kerbin

// ============================================================
//  PHASE IDs
// ============================================================
LOCAL PH_FLIP      IS 0.
LOCAL PH_BOOSTBACK IS 1.
LOCAL PH_COAST     IS 2.
LOCAL PH_ENTRY     IS 3.
LOCAL PH_AERO      IS 4.
LOCAL PH_LANDING   IS 5.
LOCAL PH_TOUCHDOWN IS 6.

LOCAL PHASE_NAMES IS LIST(
    "FLIP", "BOOSTBACK", "COAST", "ENTRY", "AERO", "LANDING", "TOUCHDOWN"
).

// ============================================================
//  STATE VARIABLES
// ============================================================
LOCAL phase        IS PH_FLIP.
LOCAL padGeo       IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL oneEngine    IS FALSE.
LOCAL legsOut      IS FALSE.
LOCAL lastPredTime IS -999.
LOCAL cachedImpact IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL bbMinDist    IS 99999.
LOCAL bbStartTime  IS 0.
LOCAL GridFin      IS FALSE.
LOCAL finAeroSet   IS FALSE.    // true once fins raised to AERO authority
LOCAL lbrakeDone   IS FALSE.
LOCAL lastLogTime  IS -999.
LOCAL LOG_FILE     IS "0:/rtls_log.txt".

// ============================================================
//  UTILITY
// ============================================================
FUNCTION Clamp {
    PARAMETER x, lo, hi.
    IF x < lo { RETURN lo. }
    IF x > hi { RETURN hi. }
    RETURN x.
}

// ============================================================
//  LOGGING
// ============================================================
LOCAL LOG_INTERVAL IS 3.

FUNCTION logOpen {
    IF EXISTS(LOG_FILE) { DELETEPATH(LOG_FILE). }
    LOG "RTLS Log — Pad: " + PAD_LAT + " / " + PAD_LNG + " / " + PAD_ALT TO LOG_FILE.
    LOG "T+sec | Phase | Alt km | VS m/s | Hspd m/s | Pad km | Thr% | Message" TO LOG_FILE.
    LOG "----------------------------------------------------------------------" TO LOG_FILE.
}

FUNCTION logLine {
    PARAMETER msg.
    LOCAL ts    IS ROUND(TIME:SECONDS, 1).
    LOCAL altKm IS ROUND(SHIP:ALTITUDE / 1000, 2).
    LOCAL vs    IS ROUND(SHIP:VERTICALSPEED, 1).
    LOCAL hspd  IS ROUND(SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2
                                    - SHIP:VERTICALSPEED^2)), 1).
    LOCAL pad   IS ROUND(distKm(SHIP:GEOPOSITION, padGeo), 2).
    LOCAL thr   IS ROUND(THROTTLE * 100, 0).
    LOCAL pName IS PHASE_NAMES[phase].
    LOG "T+" + ts + " | " + pName + " | " + altKm + "km | VS:" + vs
        + " | H:" + hspd + " | Pad:" + pad + "km | Thr:" + thr
        + "% | " + msg TO LOG_FILE.
}

FUNCTION logEvent {
    PARAMETER msg.
    logLine("*** " + msg + " ***").
}

FUNCTION logPeriodic {
    PARAMETER msg IS "".
    IF (TIME:SECONDS - lastLogTime) >= LOG_INTERVAL {
        logLine(msg).
        SET lastLogTime TO TIME:SECONDS.
    }
}

// ============================================================
//  ACTION GROUPS
// ============================================================
FUNCTION activateAG {
    PARAMETER agNum.
    IF      agNum = 1 { AG1 ON. }
    ELSE IF agNum = 2 { AG2 ON. }
    ELSE IF agNum = 3 { AG3 ON. }
    ELSE IF agNum = 4 { AG4 ON. }
    ELSE IF agNum = 5 { AG5 ON. }
}

// ============================================================
//  GEOMETRY UTILITIES
// ============================================================
FUNCTION bearingTo {
    PARAMETER tgt.
    LOCAL lat0 IS SHIP:GEOPOSITION:LAT.
    LOCAL brng IS ARCTAN2(
        (tgt:LNG - SHIP:GEOPOSITION:LNG) * COS(lat0),
        tgt:LAT - lat0
    ).
    IF brng < 0 { SET brng TO brng + 360. }
    RETURN brng.
}

FUNCTION distKm {
    PARAMETER geo1, geo2.
    RETURN (geo1:POSITION - geo2:POSITION):MAG / 1000.
}

FUNCTION hSpeed {
    RETURN SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2 - SHIP:VERTICALSPEED^2)).
}

FUNCTION rotVec {
    PARAMETER vecIn, axisIn, angleDeg.
    LOCAL cosA IS COS(angleDeg).
    LOCAL sinA IS SIN(angleDeg).
    RETURN vecIn * cosA + VCRS(axisIn, vecIn) * sinA
           + axisIn * VDOT(axisIn, vecIn) * (1 - cosA).
}

// ============================================================
//  GRID FIN AUTHORITY
// ============================================================
FUNCTION setFinAuthority {
    PARAMETER authPct.
    FOR pt IN SHIP:PARTS {
        IF pt:HASMODULE("ModuleControlSurface") {
            LOCAL fmod IS pt:GETMODULE("ModuleControlSurface").
            IF fmod:HASFIELD("authority limiter") {
                fmod:SETFIELD("authority limiter", authPct).
            }
        }
    }
}

// ============================================================
//  GRID FIN STEERING DIRECTION
//  Returns a direction vector blending SRFRETROGRADE with a
//  lean toward the pad. Lean angle is proportional to pad
//  distance, fading to zero close in to avoid overshoot.
//  The fins at 60% authority execute the lateral correction.
// ============================================================
FUNCTION finSteerDir {
    PARAMETER padDistKmIn.
    LOCAL srfRetro IS SHIP:SRFRETROGRADE:FOREVECTOR.

    // Lean fraction: 0 inside LEAN_FADE_KM, 1 beyond LEAN_FULL_KM
    LOCAL leanFrac IS Clamp(
        (padDistKmIn - LEAN_FADE_KM) / (LEAN_FULL_KM - LEAN_FADE_KM),
        0, 1
    ).
    LOCAL leanDeg IS LEAN_MAX_DEG * leanFrac.

    IF leanDeg < 0.1 { RETURN LOOKDIRUP(srfRetro, SHIP:FACING:TOPVECTOR). }

    // Direction from current position toward pad, in vessel frame
    LOCAL padBrng  IS bearingTo(padGeo).
    LOCAL toPad    IS HEADING(padBrng, 0):FOREVECTOR.

    // Component of toPad perpendicular to srfRetro
    LOCAL lean     IS toPad - VDOT(toPad, srfRetro) * srfRetro.
    IF lean:MAG < 0.001 {
        RETURN LOOKDIRUP(srfRetro, SHIP:FACING:TOPVECTOR).
    }
    SET lean TO lean:NORMALIZED * SIN(leanDeg).
    LOCAL aimVec IS (srfRetro + lean):NORMALIZED.
    RETURN LOOKDIRUP(aimVec, SHIP:FACING:TOPVECTOR).
}

// ============================================================
//  BALLISTIC IMPACT PREDICTOR
//  RK2 Keplerian integration with Kerbin rotation correction.
//  No atmosphere — used for boostback targeting only.
// ============================================================
FUNCTION predictImpact {
    LOCAL mu      IS BODY:MU.
    LOCAL bodyR   IS BODY:RADIUS.
    LOCAL bPos0   IS BODY:POSITION.
    LOCAL posVec  IS -bPos0.
    LOCAL orbVel  IS SHIP:VELOCITY:ORBIT.
    LOCAL rotPer  IS BODY:ROTATIONPERIOD.
    LOCAL rotAxis IS V(0, 1, 0).
    IF BODY:ANGULARVEL:MAG > 0.000001 {
        SET rotAxis TO BODY:ANGULARVEL:NORMALIZED.
    }
    LOCAL intDt IS 5.
    LOCAL tof   IS 0.
    UNTIL tof > 1500 {
        LOCAL posMag IS posVec:MAG.
        LOCAL accVec IS -(mu / (posMag^3)) * posVec.
        LOCAL posMid IS posVec + orbVel * (intDt / 2).
        LOCAL velMid IS orbVel + accVec * (intDt / 2).
        LOCAL accMid IS -(mu / (posMid:MAG^3)) * posMid.
        SET posVec TO posVec + velMid * intDt.
        SET orbVel TO orbVel + accMid * intDt.
        SET tof    TO tof + intDt.
        IF posVec:MAG - bodyR <= PAD_ALT {
            LOCAL rotDeg IS 360 * tof / rotPer.
            LOCAL posAdj IS rotVec(posVec, rotAxis, -rotDeg).
            RETURN BODY:GEOPOSITIONOF(posAdj + bPos0).
        }
    }
    RETURN SHIP:GEOPOSITION.
}

FUNCTION getImpact {
    IF (TIME:SECONDS - lastPredTime) >= PRED_INTERVAL {
        SET cachedImpact TO predictImpact().
        SET lastPredTime TO TIME:SECONDS.
    }
    RETURN cachedImpact.
}

// ============================================================
//  KINEMATIC IGNITION ALTITUDE
//  Returns ASL altitude to start the suicide brake burn.
//  Based on vertical speed only — Hspd handled by SRFRETROGRADE.
// ============================================================
FUNCTION ignitionAlt {
    LOCAL vertSpd   IS ABS(SHIP:VERTICALSPEED).
    LOCAL gravAccel IS BODY:MU / (SHIP:ALTITUDE + BODY:RADIUS)^2.
    LOCAL aMax      IS (MAXTHRUST / SHIP:MASS) - gravAccel.
    IF aMax < 0.5 { RETURN 5000. }
    LOCAL stopDist IS (vertSpd * vertSpd) / (2 * aMax).
    RETURN stopDist + PAD_ALT + 500.  // 500m buffer
}

// ============================================================
//  TERRAIN AGL
// ============================================================
FUNCTION terrainAGL {
    LOCAL h IS SHIP:ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT.
    IF h < 0 { RETURN 0. }
    RETURN h.
}

// ============================================================
//  LANDING THROTTLE — P-CONTROLLER
//  Aggressive curve: freefalls above 800m, arrests sharply below.
// ============================================================
FUNCTION landingThrottle {
    // Add at the very top of landingThrottle(), before anything else:
    IF SHIP:VERTICALSPEED > 0 { RETURN 0. }  // ascending — cut thrust immediately
    LOCAL gravAccel IS BODY:MU / (SHIP:ALTITUDE + BODY:RADIUS)^2.
    LOCAL altAGL    IS MAX(1, terrainAGL()).
    IF MAXTHRUST < 0.01 { RETURN 0. }

    LOCAL curveTarget IS -(altAGL * VSPEED_COEFF).
    LOCAL tgtVSpd IS MIN(FINAL_VSPEED, MAX(MAX_DESCENT, curveTarget)).

    LOCAL vSpdErr IS tgtVSpd - SHIP:VERTICALSPEED.
    LOCAL accCmd  IS vSpdErr * CTRL_KP + gravAccel.
    LOCAL rawThr  IS (SHIP:MASS * accCmd) / MAXTHRUST.

    // Keep engine on when lateral error is large — tilt needs thrust
    LOCAL northErrM IS ABS(PAD_LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
    LOCAL eastErrM  IS ABS(PAD_LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG
                      * COS(SHIP:LATITUDE).
    LOCAL lateralErrM IS SQRT(northErrM^2 + eastErrM^2).
    LOCAL latFloor IS 0.
    IF lateralErrM > 1000 AND altAGL > 200 {
        SET latFloor TO 0.70.  // was 0.33 — 70% gives real lateral authority
    } ELSE IF lateralErrM > 300 AND altAGL > 200 {
        SET latFloor TO 0.45.
    }

    IF altAGL > 800 {
        RETURN MAX(latFloor, MIN(1.0, rawThr)).
    }

    LOCAL thrFloor IS CHOOSE MIN_THR_1ENG IF oneEngine ELSE MIN_THR_3ENG.
    RETURN MAX(MAX(thrFloor, latFloor), MIN(1.0, rawThr)).
}

// ============================================================
//  LATERAL STEERING — TWO-AXIS CASCADED CONTROLLER
//
//  Outer loop (position → velocity):
//    desNorthVel = KP_POS × northErr
//    desEastVel  = KP_POS × eastErr
//
//  Inner loop (velocity → tilt):
//    northTilt = KP_VEL × (desNorthVel - actualNorthVel)
//    eastTilt  = KP_VEL × (desEastVel  - actualEastVel)
//
//  North and east are controlled independently so ALL drift
//  directions are corrected — fixes the south miss that
//  single-bearing controllers miss entirely.
// ============================================================
FUNCTION lateralSteerDir {
    PARAMETER padDistKmIn.

    IF padDistKmIn < 0.05 OR terrainAGL() < 200 {
        RETURN LOOKDIRUP(UP:FOREVECTOR, SHIP:FACING:TOPVECTOR).
    }

    // ── Position error (metres, north+ east+) ─────────────────
    LOCAL northErr IS (PAD_LAT - SHIP:LATITUDE)  * KERBIN_M_PER_DEG.
    LOCAL eastErr  IS (PAD_LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG
                     * COS(SHIP:LATITUDE).

    // ── Outer loop: desired lateral velocity ──────────────────
    LOCAL desNorthVel IS Clamp(northErr * LAT_KP_POS,
                               -LAT_MAX_VEL, LAT_MAX_VEL).
    LOCAL desEastVel  IS Clamp(eastErr  * LAT_KP_POS,
                               -LAT_MAX_VEL, LAT_MAX_VEL).

    // ── Current velocity decomposed into north and east ────────
    LOCAL northVel IS VDOT(SHIP:VELOCITY:SURFACE, HEADING(0,  0):FOREVECTOR).
    LOCAL eastVel  IS VDOT(SHIP:VELOCITY:SURFACE, HEADING(90, 0):FOREVECTOR).

    // ── Inner loop: tilt per axis ─────────────────────────────
    LOCAL northTilt IS Clamp((desNorthVel - northVel) * LAT_KP_VEL,
                             -LAT_MAX_DEG, LAT_MAX_DEG).
    LOCAL eastTilt  IS Clamp((desEastVel  - eastVel)  * LAT_KP_VEL,
                             -LAT_MAX_DEG, LAT_MAX_DEG).

    // ── Combine into single bearing + pitch ───────────────────
    LOCAL totalTilt IS MIN(LAT_MAX_DEG, SQRT(northTilt^2 + eastTilt^2)).
    IF totalTilt < 0.1 {
        RETURN LOOKDIRUP(UP:FOREVECTOR, SHIP:FACING:TOPVECTOR).
    }
    LOCAL tiltBrng IS ARCTAN2(eastTilt, northTilt).
    IF tiltBrng < 0 { SET tiltBrng TO tiltBrng + 360. }

    RETURN HEADING(tiltBrng, 90 - totalTilt).
}

// ============================================================
//  INITIALIZATION
// ============================================================
CLEARSCREEN.
logOpen().
logEvent("SCRIPT START — Pad:" + PAD_LAT + "/" + PAD_LNG + "/" + PAD_ALT).

PRINT "╔══════════════════════════════════════╗" AT (0, 0).
PRINT "║   FALCON 9 RTLS  —  KERBAL SCALE     ║" AT (0, 1).
PRINT "╚══════════════════════════════════════╝" AT (0, 2).
PRINT "Pad: " + PAD_LAT + " / " + PAD_LNG           AT (0, 3).
PRINT "Elev: " + PAD_ALT + "m   Log: 0:/rtls_log.txt" AT (0, 4).
PRINT "                                        " AT (0, 5).

LOCK THROTTLE TO 0.
LOCK STEERING TO UP.
SAS OFF.
RCS ON.

activateAG(2).
logEvent("AG2 fired — 3 engines enabled").

// ============================================================
//  MAIN GUIDANCE LOOP
// ============================================================
UNTIL phase = PH_TOUCHDOWN {

    LOCAL altAGL    IS terrainAGL().
    LOCAL padDistKm IS distKm(SHIP:GEOPOSITION, padGeo).
    LOCAL hSpd      IS hSpeed().

    // ──────────────────────────────────────────────────────
    //  PHASE 0: FLIP
    //  Rotate to level heading aimed directly at the pad.
    //  No bias — the boostback aims straight at the pad.
    // ──────────────────────────────────────────────────────
    IF phase = PH_FLIP {
        LOCAL aimGeo     IS LATLNG(PAD_LAT + BB_NORTH_AIM, PAD_LNG).
        LOCAL padBearing IS bearingTo(aimGeo).
        LOCK STEERING TO HEADING(padBearing, 0).
        LOCAL flipAngle IS VANG(SHIP:FACING:FOREVECTOR,
                                HEADING(padBearing, 0):FOREVECTOR).

        PRINT "[ FLIP ]  Err:" + ROUND(flipAngle,1) + " deg              " AT (0, 6).
        PRINT "  Alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "km  Brng:"
              + ROUND(padBearing,1) + " deg      " AT (0, 7).
        logPeriodic("flipAngle:" + ROUND(flipAngle,1)).

        IF flipAngle < 10 {
            SET bbStartTime TO TIME:SECONDS.
            SET bbMinDist   TO 99999.
            SET phase TO PH_BOOSTBACK.
            logEvent("FLIP complete — BOOSTBACK brng:" + ROUND(padBearing,1)).
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 1: BOOSTBACK
    //  Level burn aimed at the pad.
    //  Throttle tapers 100% → 3% as predicted impact closes
    //  to prevent overshooting. Terminates on:
    //    - predicted impact within BB_TOL_KM of pad
    //    - overshoot detected (impact moving away)
    //    - timeout (120 s)
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_BOOSTBACK {
        LOCAL aimGeo     IS LATLNG(PAD_LAT + BB_NORTH_AIM, PAD_LNG).
        LOCAL padBearing IS bearingTo(aimGeo).
        LOCK STEERING TO HEADING(padBearing, 0).

        LOCAL impactPos IS getImpact().
        LOCAL impDist   IS distKm(impactPos, padGeo).
        IF impDist < bbMinDist { SET bbMinDist TO impDist. }

        // Throttle taper
        LOCAL bbThr IS 1.0.
        IF impDist < 20 { SET bbThr TO MAX(0.03, impDist / 20). }
        LOCK THROTTLE TO bbThr.

        LOCAL bbElapsed IS TIME:SECONDS - bbStartTime.
        LOCAL overshoot IS (bbMinDist < 5 AND impDist > bbMinDist + 0.2).

        PRINT "[ BOOSTBACK ]  Pred:" + ROUND(impDist,1) + "km  Min:"
              + ROUND(bbMinDist,1) + "km   " AT (0, 6).
        PRINT "  Thr:" + ROUND(bbThr*100,0) + "%  Spd:"
              + ROUND(SHIP:VELOCITY:SURFACE:MAG,0) + "m/s  "
              + ROUND(bbElapsed,0) + "s    " AT (0, 7).
        logPeriodic("pred:" + ROUND(impDist,1) + " min:" + ROUND(bbMinDist,1)
                    + " thr:" + ROUND(bbThr*100,0) + " Hspd:" + ROUND(hSpd,1)).

        IF impDist < BB_TOL_KM OR overshoot OR bbElapsed > 120 {
            LOCK THROTTLE TO 0.
            SET lastPredTime TO -999.
            SET phase TO PH_COAST.
            logEvent("BOOSTBACK end — pred:" + ROUND(impDist,1) + " min:"
                     + ROUND(bbMinDist,1) + " Hspd:" + ROUND(hSpd,1)
                     + " overshoot:" + overshoot + " elapsed:"
                     + ROUND(bbElapsed,0)).
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 2: COAST
    //  Ballistic arc to apoapsis and back down.
    //  Steering: UP until fins deploy, then SRFRETROGRADE.
    //  Fins deploy at 45km descending at 15% authority
    //  (passive drag + stabilisation).
    //  Authority raised to 60% when ENTRY or AERO begins.
    //  Direct transition to LANDING when ignitionAlt reached.
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_COAST {
        LOCK THROTTLE TO 0.

        // Deploy fins (passive) during descent
        IF SHIP:ALTITUDE < 45000 AND SHIP:VERTICALSPEED < -50
        AND NOT GridFin {
            activateAG(1).
            setFinAuthority(FIN_AUTH_COAST).
            RCS OFF.
            SET GridFin TO TRUE.
            logEvent("Fins deployed auth:" + FIN_AUTH_COAST
                     + "%, RCS OFF, alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "km").
        }

        IF GridFin {
            LOCK STEERING TO SHIP:SRFRETROGRADE.
        } ELSE {
            LOCK STEERING TO UP.
        }

        LOCAL impactPos IS getImpact().
        LOCAL impDist   IS distKm(impactPos, padGeo).

        PRINT "[ COAST ]  Alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "km  VS:"
              + ROUND(SHIP:VERTICALSPEED,0) + "m/s   " AT (0, 6).
        PRINT "  Spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0) + "m/s  Pred:"
              + ROUND(impDist,1) + "km  Pad:" + ROUND(padDistKm,1)
              + "km    " AT (0, 7).
        logPeriodic("pred:" + ROUND(impDist,1) + " pad:" + ROUND(padDistKm,1)
                    + " spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)).

        // Entry burn trigger
        IF SHIP:VERTICALSPEED < -1
        AND SHIP:ALTITUDE < ENTRY_ALT
        AND SHIP:VELOCITY:SURFACE:MAG > ENTRY_SPEED {
            // Raise fin authority for active steering
            IF GridFin AND NOT finAeroSet {
                setFinAuthority(FIN_AUTH_AERO).
                SET finAeroSet TO TRUE.
                logEvent("Fins authority raised to " + FIN_AUTH_AERO + "% for entry/aero").
            }
            SET phase TO PH_ENTRY.
            logEvent("COAST->ENTRY spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                     + " pad:" + ROUND(padDistKm,1) + "km").
        }
        // Skip entry burn — speed already low, go straight to aero
        ELSE IF SHIP:VERTICALSPEED < -1
        AND SHIP:ALTITUDE < ENTRY_ALT
        AND SHIP:VELOCITY:SURFACE:MAG <= ENTRY_SPEED {
            IF GridFin AND NOT finAeroSet {
                setFinAuthority(FIN_AUTH_AERO).
                SET finAeroSet TO TRUE.
                logEvent("Fins authority raised to " + FIN_AUTH_AERO + "% for aero").
            }
            SET phase TO PH_AERO.
            logEvent("COAST->AERO (skip entry, spd:"
                     + ROUND(SHIP:VELOCITY:SURFACE:MAG,0) + ")").
        }
        // Direct ignition — entry already skipped and ignition alt reached
        ELSE IF SHIP:VERTICALSPEED < -1
        AND terrainAGL() <= ignitionAlt() - PAD_ALT {
            LOCK THROTTLE TO 0.
            SET phase TO PH_LANDING.
            logEvent("COAST->LANDING (direct) alt:" + ROUND(SHIP:ALTITUDE/1000,1)
                     + "km VS:" + ROUND(SHIP:VERTICALSPEED,0)
                     + " ignAlt:" + ROUND(ignitionAlt()/1000,1) + "km").
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 3: ENTRY BURN
    //  Full throttle SRFRETROGRADE to kill speed to 400 m/s.
    //  Fins at 60% steer laterally toward pad during the burn.
    //  This is the first of the two burns — mimics real F9
    //  entry burn that protects engines from aero heating.
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_ENTRY {
        LOCK THROTTLE TO 1.0.
        // Lean slightly toward pad during entry burn
        LOCK STEERING TO finSteerDir(padDistKm).

        LOCAL entrySpd IS SHIP:VELOCITY:SURFACE:MAG.
        PRINT "[ ENTRY ]  Spd:" + ROUND(entrySpd,0) + " -> "
              + ENTRY_SPEED + " m/s   " AT (0, 6).
        PRINT "  Pad:" + ROUND(padDistKm,1) + "km  Hspd:"
              + ROUND(hSpd,1) + "   " AT (0, 7).
        logPeriodic("spd:" + ROUND(entrySpd,0) + " pad:"
                    + ROUND(padDistKm,1) + " hspd:" + ROUND(hSpd,1)).

        IF entrySpd < ENTRY_SPEED {
            LOCK THROTTLE TO 0.
            SET phase TO PH_AERO.
            logEvent("ENTRY->AERO spd:" + ROUND(entrySpd,0)
                     + " pad:" + ROUND(padDistKm,1) + "km"
                     + " hspd:" + ROUND(hSpd,1)).
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 4: AERO DESCENT
    //  Engines off. Fins at 60% authority actively steer the
    //  booster laterally toward the pad by leaning the nose
    //  toward the pad from the SRFRETROGRADE vector.
    //  This replaces the bias correction system — the fins
    //  do the lateral work aerodynamically.
    //  Transition to LANDING when ignitionAlt reached.
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_AERO {
        LOCK THROTTLE TO 0.

        // Active fin steering toward pad
        LOCK STEERING TO finSteerDir(padDistKm).

        LOCAL ignAlt IS ignitionAlt().
        PRINT "[ AERO ]  Alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "km  VS:"
              + ROUND(SHIP:VERTICALSPEED,0) + "m/s   " AT (0, 6).
        PRINT "  Hspd:" + ROUND(hSpd,1) + "  Pad:" + ROUND(padDistKm,1)
              + "km  Ign@" + ROUND(ignAlt/1000,1) + "km   " AT (0, 7).
        logPeriodic("pad:" + ROUND(padDistKm,1) + " hspd:" + ROUND(hSpd,1)
                    + " ignAlt:" + ROUND(ignAlt/1000,1)
                    + " VS:" + ROUND(SHIP:VERTICALSPEED,0)).

        IF SHIP:ALTITUDE <= ignAlt {
            LOCK THROTTLE TO 0.
            SET phase TO PH_LANDING.
            logEvent("AERO->LANDING alt:" + ROUND(SHIP:ALTITUDE/1000,1)
                     + "km VS:" + ROUND(SHIP:VERTICALSPEED,0)
                     + " Hspd:" + ROUND(hSpd,1)
                     + " pad:" + ROUND(padDistKm,1) + "km"
                     + " ignAlt:" + ROUND(ignAlt/1000,1) + "km").
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 5: LANDING BURN
    //  This is the second burn — the suicide/hover-slam.
    //
    //  SUB-PHASE A — SRFRETROGRADE BRAKE
    //    Full throttle SRFRETROGRADE from ignition altitude.
    //    Kills both VS and Hspd proportionally.
    //    Throttle = 0 if ascending (brief overshoot recovery).
    //    Exits when VS > BRAKE_EXIT_VS (-80 m/s) or < 1500m AGL.
    //
    //  SUB-PHASE B — P-CONTROLLER DESCENT
    //    Steers UP. Freefalls from brake exit (~4km) until
    //    curve target takes over (~1.2km). Then arrests sharply.
    //    3 engines -> 1 engine at SWITCH_ALT when VS > -15.
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_LANDING {

        IF NOT lbrakeDone {

            // Cap retrograde angle from vertical for safety
            LOCAL srfRetroDir IS SHIP:SRFRETROGRADE:FOREVECTOR.
            LOCAL upVec       IS UP:FOREVECTOR.
            LOCAL srfAngle    IS VANG(srfRetroDir, upVec).

            LOCAL safeSrfRetro IS srfRetroDir.
            IF srfAngle > BRAKE_ANGLE {
                LOCAL blendAmt IS BRAKE_ANGLE / srfAngle.
                SET safeSrfRetro TO (srfRetroDir * blendAmt
                                     + upVec * (1 - blendAmt)):NORMALIZED.
            }

            LOCAL aimError IS VANG(SHIP:FACING:FOREVECTOR, safeSrfRetro).
            LOCAL brakeThr IS 0.
            IF SHIP:VERTICALSPEED >= 0 {
                SET brakeThr TO 0.       // ascending — wait for gravity
            } ELSE IF aimError < 15 {
                SET brakeThr TO 1.0.
            } ELSE IF aimError < 30 {
                SET brakeThr TO Clamp((30 - aimError) / 15, 0.1, 1.0).
            }

            LOCK STEERING TO LOOKDIRUP(safeSrfRetro, SHIP:FACING:TOPVECTOR).
            LOCK THROTTLE TO brakeThr.

            // Leg deployment
            IF NOT legsOut AND terrainAGL() < LEG_DEPLOY_ALT {
                GEAR ON.
                SET legsOut TO TRUE.
                logEvent("LEGS deployed at " + ROUND(altAGL,0) + "m AGL").
                PRINT "*** LEGS DEPLOYED ***              " AT (0, 9).
            }

            PRINT "[ BRAKE ]  AGL:" + ROUND(altAGL,0) + "m  VS:"
                  + ROUND(SHIP:VERTICALSPEED,1) + "   " AT (0, 6).
            PRINT "  Hspd:" + ROUND(hSpd,1) + "  Ang:" + ROUND(srfAngle,1)
                  + "  Aim:" + ROUND(aimError,1) + "  Thr:"
                  + ROUND(brakeThr*100,0) + "%  " AT (0, 7).
            logPeriodic("BRAKE hspd:" + ROUND(hSpd,1) + " VS:"
                        + ROUND(SHIP:VERTICALSPEED,1) + " ang:"
                        + ROUND(srfAngle,1) + " aim:" + ROUND(aimError,1)
                        + " thr:" + ROUND(brakeThr*100,0)).

            // Exit brake
            IF terrainAGL() < 1500 OR SHIP:VERTICALSPEED > BRAKE_EXIT_VS {
                SET lbrakeDone TO TRUE.
                logEvent("BRAKE done — VS:" + ROUND(SHIP:VERTICALSPEED,1)
                         + " Hspd:" + ROUND(hSpd,1)
                         + " alt:" + ROUND(altAGL,0) + "m").
                PRINT "*** BRAKE DONE ***                 " AT (0, 9).
            }

        } ELSE {

            // 3 -> 1 engine when low and slow
            IF NOT oneEngine
            AND terrainAGL() < SWITCH_ALT
            AND SHIP:VERTICALSPEED > -15 {
                activateAG(3).
                SET oneEngine TO TRUE.
                logEvent("1-ENGINE at " + ROUND(altAGL,0) + "m VS:"
                         + ROUND(SHIP:VERTICALSPEED,1)
                         + " Hspd:" + ROUND(hSpd,1)).
                PRINT "*** 1 ENGINE ***                   " AT (0, 9).
            }

            // Legs if not already deployed
            IF NOT legsOut AND terrainAGL() < LEG_DEPLOY_ALT {
                GEAR ON.
                SET legsOut TO TRUE.
                logEvent("LEGS deployed at " + ROUND(altAGL,0) + "m AGL").
                PRINT "*** LEGS DEPLOYED ***              " AT (0, 9).
            }

            LOCK STEERING TO lateralSteerDir(padDistKm).
            LOCAL thrCmd IS landingThrottle().
            LOCK THROTTLE TO thrCmd.

            // Compute components for display
            LOCAL northErrDisp IS ROUND((PAD_LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG, 0).
            LOCAL eastErrDisp  IS ROUND((PAD_LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG * COS(SHIP:LATITUDE), 0).

            PRINT "[ DESCENT ]  AGL:" + ROUND(altAGL,0) + "m  VS:"
                  + ROUND(SHIP:VERTICALSPEED,1) + "   " AT (0, 6).
            PRINT "  Thr:" + ROUND(thrCmd*100,0) + "%  N:" + northErrDisp
                  + "m  E:" + eastErrDisp + "m  Pad:"
                  + ROUND(padDistKm,2) + "km  " AT (0, 7).
            logPeriodic("DESCENT thr:" + ROUND(thrCmd*100,0)
                        + " VS:" + ROUND(SHIP:VERTICALSPEED,1)
                        + " pad:" + ROUND(padDistKm,2)
                        + " N:" + northErrDisp + " E:" + eastErrDisp
                        + " eng:" + (CHOOSE "1" IF oneEngine ELSE "3")).

            // Touchdown detection
            IF (terrainAGL() < 20
                AND SHIP:VERTICALSPEED > -3
                AND hSpd < 3)
            OR terrainAGL() < 2 {
                SET phase TO PH_TOUCHDOWN.
                logEvent("TOUCHDOWN VS:" + ROUND(SHIP:VERTICALSPEED,1)
                         + " Hspd:" + ROUND(hSpd,1)
                         + " Pad:" + ROUND(padDistKm,2) + "km"
                         + " lat:" + ROUND(SHIP:LATITUDE,4)
                         + " lng:" + ROUND(SHIP:LONGITUDE,4)).
            }
        }
    }

    WAIT 0.
}

// ============================================================
//  TOUCHDOWN — clean up
// ============================================================
LOCK THROTTLE TO 0.
UNLOCK STEERING.
UNLOCK THROTTLE.
SAS ON.
RCS ON.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
setFinAuthority(100).

LOCAL finalDist IS distKm(SHIP:GEOPOSITION, padGeo).
logEvent("SCRIPT END — lat:" + ROUND(SHIP:LATITUDE,4)
         + " lng:" + ROUND(SHIP:LONGITUDE,4)
         + " pad dist:" + ROUND(finalDist,2) + "km").

PRINT "                                        " AT (0, 6).
PRINT "                                        " AT (0, 7).
PRINT "+--------------------------------------+" AT (0, 6).
PRINT "| TOUCHDOWN — Engines cut.             |" AT (0, 7).
PRINT "| Log saved: 0:/rtls_log.txt           |" AT (0, 8).
PRINT "+--------------------------------------+" AT (0, 9).
PRINT "Dist to pad: " + ROUND(finalDist,2) + " km          " AT (0, 10).
