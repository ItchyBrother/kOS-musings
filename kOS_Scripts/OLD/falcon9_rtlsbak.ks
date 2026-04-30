// ============================================================
//  falcon9_rtls.ks  |  RTLS Guidance  |  Kerbal Scale
//  Experimental ballistic RTLS test - boostback then passive fall + last-moment suicide burn
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
//  Experimental profile for diagnosis:
//    1. Boostback only
//    2. Passive ballistic fall (no RCS trim, no active fin steering, no entry burn)
//    3. Last-moment retrograde suicide burn, then simple vertical touchdown
//
//  Grid fins (AG1) may deploy passively for stability only.
//  No active lateral steering is used after boostback; this is an A/B test
//  to see where the unguided ballistic arc naturally wants to land.
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
LOCAL ENTRY_ALT      IS 40000.  // ASL (m) - arm entry burn below this
LOCAL ENTRY_SPEED    IS 290.    // m/s surface speed to END entry burn

// ── Grid fin steering ───────────────────────────────────────
LOCAL FIN_AUTH_COAST IS 15.     // % authority during coast (passive drag)
LOCAL FIN_AUTH_AERO  IS 52.     // % authority during aero (active steering) - slightly stronger last-bit honing
LOCAL LEAN_MAX_DEG   IS 7.      // max lean angle toward pad (degrees) - a bit more final trim authority
LOCAL LEAN_FULL_KM   IS 3.0.    // km - full lean applied beyond this distance
LOCAL LEAN_FADE_KM   IS 0.15.   // km - keep fin trim active closer to the pad before fadeout

// ── Landing burn ────────────────────────────────────────────
LOCAL VSPEED_COEFF   IS 0.10.   // P-controller: tgtVS = -(altAGL * coeff)
//  At 2000m: -200 m/s (freefall through)
//  At 1000m: -100 m/s (braking starts)
//  At  500m: -50  m/s
//  At  200m: -20  m/s
//  At  100m: -10  m/s (1-engine takes over)
LOCAL FINAL_VSPEED   IS -0.3.   // touchdown speed floor (m/s) - slightly softer final touchdown target
LOCAL CTRL_KP        IS 0.86.   // P-gain on vertical speed error - slightly firmer late touchdown response
LOCAL MAX_DESCENT    IS -200.   // fastest target VS under P-control (m/s)
LOCAL BRAKE_EXIT_VS  IS -120.   // m/s - stay in brake longer so the main burn can also build pad-closing speed
LOCAL BRAKE_EXIT_ALT IS 1300.    // AGL (m) - stay in brake longer so pad-closing can build before descent

// ── Engine config ───────────────────────────────────────────
//  3 engines: 840 kN  hover floor 33%
//  1 engine @ 100%: 400 kN  hover floor 68%
LOCAL MIN_THR_3ENG   IS 0.33.
LOCAL MIN_THR_1ENG   IS 0.82.
LOCAL SWITCH_ALT     IS 120.    // AGL (m) - keep v37 geometry but give 1-engine a touch more time to flare

// ── Boostback ───────────────────────────────────────────────
LOCAL BB_TOL_KM         IS 1.20.   // good-enough predicted impact for boostback cutoff
LOCAL PRED_INTERVAL     IS 0.5.    // seconds between ballistic predictions
LOCAL BB_BASE_NORTH_M   IS 330.     // 375 slightly less north bias - recent run ended a bit north of pad
LOCAL BB_BASE_EAST_M    IS -3200.   // -2550 tiny extra west bias - recent run still finished a bit east of center
LOCAL BB_TARGET_EAST_M  IS 1600.0.   // tiny extra west cutoff shift - recent run still finished a bit east of center
LOCAL BB_AIM_GAIN       IS 3.0.   // fraction of predicted impact N/E error fed into boostback aimpoint
LOCAL BB_MAX_OFFSET_M   IS 12000.  // clamp dynamic boostback aimpoint offset
LOCAL BB_EAST_GAIN      IS 2.0.   // extra east/west authority - recent runs still stop east of pad
LOCAL BB_AXIS_TOL_M     IS 600.    // require each axis to be reasonably close before ending on tolerance

// ── Leg deployment ──────────────────────────────────────────
LOCAL LEG_DEPLOY_ALT IS 500.    // AGL (m)

// ── Brake geometry ──────────────────────────────────────────
LOCAL BRAKE_ANGLE    IS 60.     // max degrees from vertical for brake burn
LOCAL BRAKE_PAD_LEAN IS 55.     // max extra lean toward pad during brake
LOCAL BRAKE_PAD_FULL_KM IS 4.0. // full brake lean beyond this miss distance
LOCAL BRAKE_CLOSE_PER_KM IS 48. // desired pad-closing speed during brake (m/s per km miss)
LOCAL BRAKE_CLOSE_MAX   IS 110. // cap desired pad-closing speed during brake
LOCAL BRAKE_CLOSE_GAIN  IS 1.05. // extra brake lean per m/s of missing closing speed
LOCAL BRAKE_NORTH_WEIGHT IS 1.05. // nearly neutral now that the persistent south miss is fixed
LOCAL BRAKE_DESCENT_FAST IS -260. // keep brake descending at high altitude - no high hover
LOCAL BRAKE_DESCENT_SLOW IS -120. // do not fully arrest VS during brake unless nearly over the pad
LOCAL BRAKE_DESCENT_KP   IS 0.070. // vertical-speed gain for brake throttle
LOCAL BRAKE_HOVER_BREAKOUT_ALT IS 6000. // if brake has flattened out this high, hand over to descent
LOCAL BRAKE_HOVER_BREAKOUT_VS  IS 20.   // m/s window that counts as an unhelpful hover during brake
LOCAL BRAKE_TOWARD_GAIN IS 0.55. // brake: toward-pad velocity error -> lateral accel
LOCAL BRAKE_SIDE_DAMP  IS 0.28. // brake: kill sideways drift without cancelling closing motion
LOCAL BRAKE_UP_BIAS_ACC IS 14.0. // brake: upward bias when converting lateral accel into tilt
LOCAL BRAKE_MAX_TILT   IS 60.0. // brake: prevent crazy tilt while still far/high

// ── Lateral correction during descent ───────────────────────
//  Two-axis cascaded control: position→velocity→tilt.
//  North and east controlled independently - corrects drift
//  in ALL directions for any pad location automatically.
LOCAL LAT_KP_POS IS 0.030.    // outer: desired lateral speed per metre of miss
LOCAL LAT_MAX_VEL IS 95.0.     // m/s - cap on commanded lateral speed
LOCAL LAT_KP_VEL IS 0.28.      // velocity error -> lateral accel command
LOCAL LAT_MAX_DEG IS 38.0.     // hard tilt cap (degrees)
LOCAL LAT_STOP_ACC IS 9.0.     // m/s^2 assumed usable lateral stopping authority
LOCAL LAT_DEADBAND_M IS 120.0. // inside this, prefer damping over translation
LOCAL LAT_MAX_ACC IS 13.5.     // m/s^2 max lateral accel command
LOCAL LAT_UP_BIAS_ACC IS 18.0. // m/s^2 vertical bias used to convert accel -> tilt
LOCAL LAT_NO_REVERSE_M IS 500. // do not command away-from-pad accel outside this zone unless needed to stop
LOCAL LAT_NORTH_WEIGHT IS 1.05. // nearly neutral now that the persistent south miss is fixed
LOCAL LAT_CAPTURE_ALT_M  IS 1200. // below this, shift from chase to capture-over-pad behavior
LOCAL LAT_CAPTURE_DIST_M IS 500.  // start braking lateral closure instead of chasing hard
LOCAL LAT_CAPTURE_FINAL_M IS 120. // inside this, command essentially zero crossrange for straight-down landing
LOCAL KERBIN_M_PER_DEG IS 10471. // metres per degree on Kerbin

// ── RCS terminal trim ────────────────────────────────────────
LOCAL RCS_ENABLE_ALT_M IS 2200.  // allow fine translational trim from higher in the landing burn
LOCAL RCS_FULL_ALT_M   IS 180.   // full RCS authority near the deck
LOCAL RCS_ENABLE_DIST_M IS 1600.  // keep terminal RCS available while still hundreds of metres off-pad
LOCAL RCS_CAPTURE_M    IS 90.    // inside this, stop chasing and kill crossrange
LOCAL RCS_DEADBAND_M   IS 18.    // do nothing for tiny residual miss
LOCAL RCS_KP_POS       IS 0.012. // desired close speed per metre of miss
LOCAL RCS_MAX_CLOSE    IS 7.0.   // let RCS contribute a bit more real pad-closing late
LOCAL RCS_KP_VEL       IS 0.10.  // velocity error -> translation command
LOCAL RCS_MAX_CMD      IS 0.35.  // stronger late trim now that final steering is intentionally active
LOCAL RCS_DAMP_ONLY_M  IS 120.0.    // near pad, prefer pure damping over chase

// ── Tiny engine-gimbal pad trim (very low / very close only) ─────────
LOCAL FINAL_GIMBAL_ENABLE_M IS 8000. // allow tiny engine trim from landing ignition instead of waiting until very low altitude
LOCAL FINAL_GIMBAL_FADE_M   IS 30.   // fade back upright very near the surface
LOCAL FINAL_GIMBAL_DIST_M   IS 1800. // keep trim available from higher / farther in terminal
LOCAL FINAL_GIMBAL_MAX_DEG  IS 7.0.  // allow more meaningful engine-centering tilt in terminal
LOCAL FINAL_GIMBAL_MAX_HSPD IS 90.0. // do not wait until horizontal speed is already tiny

// ── Active terminal steering (last couple km only) ─────────────────────
LOCAL TERM_STEER_ENABLE_M    IS 8000.  // engage active terminal steering from landing ignition
LOCAL TERM_STEER_DIST_M      IS 2000.  // allow steering while still a significant fraction of a kilometre off
LOCAL TERM_STEER_FADE_M      IS 35.    // fade back upright very near touchdown
LOCAL TERM_STEER_NORTH_WT    IS 0.70.  // north/south is already close, bias less here
LOCAL TERM_STEER_EAST_WT     IS 2.60.  // east/west is the persistent miss; bias much harder here
LOCAL TERM_STEER_KP_POS      IS 0.028. // command more real closing during terminal steering
LOCAL TERM_STEER_MAX_VEL     IS 45.0.  // allow active steering to matter before the deck is close
LOCAL TERM_STEER_KP_VEL      IS 0.34.  // stronger response to the persistent west bias
LOCAL TERM_STEER_MAX_ACC     IS 9.5.   // still bounded, but high enough to actually move the footprint
LOCAL TERM_STEER_MAX_DEG     IS 15.0.  // allow visible tilt authority in terminal
LOCAL TERM_STEER_DEADBAND_M  IS 25.0.  // keep correcting until the miss is actually small
LOCAL TERM_STEER_FINAL_M     IS 8.0.   // stay in active closure until nearly centered
LOCAL PAD_TRIM_NORTH_M       IS 55.     // was 55 was 39 cross-pad trim offset
LOCAL PAD_TRIM_EAST_M        IS 0.     // was -15 was -38 -40 persistent west miss compensation (small extra east pre-bias)

// ── Clean-sheet landing-phase controller ─────────────────────
LOCAL LAND_FINAL_ALT_M        IS 280.0. // hand off from approach capture to final settle
LOCAL LAND_FINAL_PAD_M        IS 0. // was 120.0 if already very near the pad, settle earlier
LOCAL LAND_POS_KP_APPROACH    IS 0.026. // m/s desired lateral speed per metre of miss
LOCAL LAND_POS_KP_FINAL       IS 0.010.
LOCAL LAND_MAX_VEL_APPROACH   IS 10.0. // was 7 was 22.0 - half lateral speed cap.
LOCAL LAND_MAX_VEL_FINAL      IS 3.0.
LOCAL LAND_VEL_KP_APPROACH    IS 0.18.  // velocity error -> lateral acceleration
LOCAL LAND_VEL_KP_FINAL       IS 0.22.
LOCAL LAND_MAX_ACC_APPROACH   IS 9.0.
LOCAL LAND_MAX_ACC_FINAL      IS 3.5.
LOCAL LAND_TILT_MAX_APPROACH  IS 16.0.
LOCAL LAND_TILT_MAX_FINAL     IS 6.0.
LOCAL LAND_UP_BIAS_ACC        IS 21.0.
LOCAL LAND_EAST_WEIGHT        IS 1.0.  // east/west remains the persistent bias
LOCAL LAND_NORTH_WEIGHT       IS 1.2.
LOCAL LAND_THR_KP_APPROACH    IS 0.60.
LOCAL LAND_THR_KP_FINAL       IS 0.90.
LOCAL LAND_FINAL_ONE_ENG_ALT  IS 40.0.
LOCAL LAND_FINAL_ONE_ENG_VS   IS -10.0.
LOCAL LAND_RCS_ENABLE_ALT_M   IS 450.0.
LOCAL LAND_RCS_ENABLE_PAD_M   IS 500.0.

// ── RCS midcourse trim (boostback / post-entry) ──────────────
LOCAL MID_RCS_MIN_ALT_M    IS 30000. // keep RCS active only in very thin air / vacuum
LOCAL MID_RCS_FULL_ALT_M   IS 35000. // full midcourse authority above this altitude
LOCAL MID_RCS_ENABLE_DIST_M IS 70000. // allow tiny trim puffs during boostback / high coast
LOCAL MID_RCS_DEADBAND_M   IS 120.   // no RCS for tiny midcourse miss
LOCAL MID_RCS_CAPTURE_M    IS 250.   // inside this, switch to damping rather than chase
LOCAL MID_RCS_KP_POS       IS 0.004. // desired close speed per metre of miss
LOCAL MID_RCS_MAX_CLOSE    IS 5.0.   // m/s cap for midcourse pad-closing
LOCAL MID_RCS_KP_VEL       IS 0.004. // velocity error -> translation command (tiny puffs only)
LOCAL MID_RCS_MAX_CMD      IS 0.04.  // tiny puffs only - never let RCS drive the trajectory

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
LOCAL activePadGeo IS padGeo.
LOCAL oneEngine    IS FALSE.
LOCAL legsOut      IS FALSE.
LOCAL lastPredTime IS -999.
LOCAL cachedImpact IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL bbMinDist    IS 99999.
LOCAL bbPrevDist   IS 99999.
LOCAL bbRiseCount  IS 0.
LOCAL bbStartTime  IS 0.
LOCAL GridFin      IS FALSE.
LOCAL finAeroSet   IS FALSE.    // true once fins raised to AERO authority
LOCAL lbrakeDone   IS FALSE.
LOCAL lastLogTime  IS -999.
LOCAL LOG_FILE     IS "0:/rtls_log.txt".
LOCAL boundsBox    IS SHIP:BOUNDS.
LOCAL aeroBestPadKm IS 99999.
LOCAL aeroClosePass IS FALSE.
LOCAL aeroFinTrimEnabled IS TRUE.

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
    LOG "RTLS Log - Pad: " + PAD_LAT + " / " + PAD_LNG + " / " + PAD_ALT TO LOG_FILE.
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
    LOCAL padBrng  IS bearingTo(activePadGeo).
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
//  No atmosphere - used for boostback targeting only.
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

FUNCTION boostbackAimGeo {
    LOCAL impactPos IS getImpact().

    // Predicted impact error in the local tangent plane.
    // Positive northErr means the current impact is south of the pad.
    // Positive eastErr means the current impact is west of the pad.
    LOCAL northErrM IS (PAD_LAT - impactPos:LAT) * KERBIN_M_PER_DEG.
    LOCAL eastErrM  IS (PAD_LNG - impactPos:LNG) * KERBIN_M_PER_DEG
                      * COS(PAD_LAT).

    // Empirical correction: this profile consistently arrives east of the pad after aero,
    // so during boostback we intentionally target a ballistic impact several kilometres
    // west of the pad instead of trying to drive the vacuum predictor to zero.
    LOCAL eastTargetErrM IS eastErrM - BB_TARGET_EAST_M.

    LOCAL aimNorthM IS Clamp(BB_BASE_NORTH_M + northErrM * BB_AIM_GAIN,
                             -BB_MAX_OFFSET_M, BB_MAX_OFFSET_M).
    LOCAL aimEastM  IS Clamp(BB_BASE_EAST_M + eastTargetErrM * BB_AIM_GAIN * BB_EAST_GAIN,
                             -BB_MAX_OFFSET_M, BB_MAX_OFFSET_M).

    LOCAL aimLat IS PAD_LAT + aimNorthM / KERBIN_M_PER_DEG.
    LOCAL lngScale IS KERBIN_M_PER_DEG * MAX(0.20, COS(PAD_LAT)).
    LOCAL aimLng IS PAD_LNG + aimEastM / lngScale.

    RETURN LATLNG(aimLat, aimLng).
}


// ============================================================
//  KINEMATIC IGNITION ALTITUDE
//  Conservative late-burn model:
//    - vertical speed does most of the work
//    - horizontal speed contributes only a small penalty
//  Returns radar-altitude (AGL) to start the landing burn.
// ============================================================
FUNCTION ignitionAlt {
    LOCAL vertSpd   IS MAX(0, -SHIP:VERTICALSPEED).
    LOCAL horizSpd  IS hSpeed().
    LOCAL gravAccel IS BODY:MU / (SHIP:ALTITUDE + BODY:RADIUS)^2.
    LOCAL aMax      IS (MAXTHRUST / SHIP:MASS) - gravAccel.
    IF aMax < 0.5 { RETURN 5000. }

    // Bias hard toward a low hover-slam. Vertical stop distance matters most.
    // Horizontal speed is only a small penalty, otherwise ignition starts far too high.
    LOCAL vertStopDist IS (vertSpd * vertSpd) / (2 * aMax).
    LOCAL horizPenalty IS horizSpd * 4.5.

    RETURN vertStopDist * 0.58 + horizPenalty + 40.
}

// ============================================================
//  TERRAIN AGL
// ============================================================
FUNCTION terrainAGL {
    LOCAL h IS boundsBox:BOTTOMALTRADAR.
    IF h < 0 { RETURN 0. }
    RETURN h.
}

FUNCTION finalPadGeo {
    LOCAL lngScale IS KERBIN_M_PER_DEG * MAX(0.20, COS(PAD_LAT)).
    RETURN LATLNG(
        PAD_LAT + PAD_TRIM_NORTH_M / KERBIN_M_PER_DEG,
        PAD_LNG + PAD_TRIM_EAST_M / lngScale
    ).
}

FUNCTION nsText {
    PARAMETER northErrM.
    IF northErrM >= 0 { RETURN "N:" + ROUND(northErrM,0). }
    RETURN "S:" + ROUND(ABS(northErrM),0).
}

FUNCTION ewText {
    PARAMETER eastErrM.
    IF eastErrM >= 0 { RETURN "E:" + ROUND(eastErrM,0). }
    RETURN "W:" + ROUND(ABS(eastErrM),0).
}


FUNCTION targetNorthErrM {
    RETURN (activePadGeo:LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
}

FUNCTION targetEastErrM {
    RETURN (activePadGeo:LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG * COS(SHIP:LATITUDE).
}

FUNCTION clearRcsAssist {
    SET SHIP:CONTROL:FORE TO 0.
    SET SHIP:CONTROL:TOP TO 0.
    SET SHIP:CONTROL:STARBOARD TO 0.
}

FUNCTION setRcsVecFromCmd {
    PARAMETER cmdVecIn, cmdCap.

    LOCAL foreAxisR IS SHIP:FACING:FOREVECTOR.
    LOCAL topAxisR  IS SHIP:FACING:TOPVECTOR.
    LOCAL starAxisR IS VCRS(topAxisR, foreAxisR).
    IF starAxisR:MAG < 0.001 {
        clearRcsAssist().
        RETURN "BADAXIS".
    }
    SET starAxisR TO starAxisR:NORMALIZED.

    LOCAL topCmdR  IS Clamp(VDOT(cmdVecIn, topAxisR), -cmdCap, cmdCap).
    LOCAL starCmdR IS Clamp(VDOT(cmdVecIn, starAxisR), -cmdCap, cmdCap).

    SET SHIP:CONTROL:FORE TO 0.
    SET SHIP:CONTROL:TOP TO topCmdR.
    SET SHIP:CONTROL:STARBOARD TO starCmdR.

    RETURN "TOP:" + ROUND(topCmdR,2) + " ST:" + ROUND(starCmdR,2).
}

FUNCTION updateMidcourseRcsAssist {
    PARAMETER targetGeo.

    LOCAL altAGL IS terrainAGL().
    LOCAL northErrM IS (targetGeo:LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
    LOCAL eastErrM  IS (targetGeo:LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG * COS(SHIP:LATITUDE).
    LOCAL errVecM   IS HEADING(0,0):FOREVECTOR * northErrM + HEADING(90,0):FOREVECTOR * eastErrM.
    LOCAL errMagM   IS errVecM:MAG.

    IF NOT RCS OR altAGL < MID_RCS_MIN_ALT_M OR errMagM > MID_RCS_ENABLE_DIST_M OR errMagM < MID_RCS_DEADBAND_M {
        clearRcsAssist().
        RETURN "OFF".
    }

    LOCAL horizVelM IS SHIP:VELOCITY:SURFACE
                    - VDOT(SHIP:VELOCITY:SURFACE, UP:FOREVECTOR) * UP:FOREVECTOR.

    LOCAL desVelVecM IS V(0,0,0).
    IF errMagM <= MID_RCS_CAPTURE_M {
        SET desVelVecM TO V(0,0,0).
    } ELSE {
        LOCAL desCloseM IS MIN(MID_RCS_MAX_CLOSE, (errMagM - MID_RCS_CAPTURE_M) * MID_RCS_KP_POS).
        SET desVelVecM TO errVecM:NORMALIZED * desCloseM.
    }

    LOCAL cmdVecM IS (desVelVecM - horizVelM) * MID_RCS_KP_VEL.
    LOCAL fadeM IS Clamp((altAGL - MID_RCS_MIN_ALT_M) / MAX(1, (MID_RCS_FULL_ALT_M - MID_RCS_MIN_ALT_M)), 0.20, 1.0).
    SET cmdVecM TO cmdVecM * fadeM.

    RETURN "MID:" + setRcsVecFromCmd(cmdVecM, MID_RCS_MAX_CMD).
}

FUNCTION updateRcsAssist {
    PARAMETER padDistKmIn.

    LOCAL altAGL IS terrainAGL().
    LOCAL padDistM IS padDistKmIn * 1000.

    IF NOT RCS OR altAGL > RCS_ENABLE_ALT_M OR padDistM > RCS_ENABLE_DIST_M {
        clearRcsAssist().
        RETURN "OFF".
    }

    LOCAL northAxisR IS HEADING(0, 0):FOREVECTOR.
    LOCAL eastAxisR  IS HEADING(90, 0):FOREVECTOR.

    LOCAL northErrR IS targetNorthErrM().
    LOCAL eastErrR  IS targetEastErrM().   // positive means pad is east of the booster; trim east
    LOCAL errVecR   IS northAxisR * northErrR + eastAxisR * eastErrR.
    LOCAL errMagR   IS errVecR:MAG.

    IF errMagR < RCS_DEADBAND_M {
        clearRcsAssist().
        RETURN "DB".
    }

    LOCAL horizVelR IS SHIP:VELOCITY:SURFACE
                    - VDOT(SHIP:VELOCITY:SURFACE, UP:FOREVECTOR) * UP:FOREVECTOR.

    LOCAL desVelVecR IS V(0,0,0).
    IF errMagR < RCS_DAMP_ONLY_M OR (errMagR < RCS_CAPTURE_M AND altAGL < 250) {
        SET desVelVecR TO V(0,0,0).
    } ELSE {
        LOCAL desCloseR IS MIN(RCS_MAX_CLOSE, errMagR * RCS_KP_POS).
        SET desVelVecR TO errVecR:NORMALIZED * desCloseR.
    }

    LOCAL velErrVecR IS desVelVecR - horizVelR.
    LOCAL cmdVecR IS velErrVecR * RCS_KP_VEL.

    LOCAL fadeR IS 1.0.
    IF altAGL > RCS_FULL_ALT_M {
        SET fadeR TO Clamp((RCS_ENABLE_ALT_M - altAGL) / MAX(1, (RCS_ENABLE_ALT_M - RCS_FULL_ALT_M)), 0.25, 1.0).
    }
    SET cmdVecR TO cmdVecR * fadeR.

    RETURN setRcsVecFromCmd(cmdVecR, RCS_MAX_CMD).
}

// ============================================================
//  FINAL GIMBAL STEERING
//  Tiny pad-centering tilt only when already very close. This is not
//  a chase controller - it just nudges the thrust vector toward the pad
//  during the last couple hundred metres.
// ============================================================
FUNCTION finalGimbalDir {
    PARAMETER padDistKmIn.

    LOCAL altAGL IS MAX(0, terrainAGL()).
    LOCAL padDistM IS padDistKmIn * 1000.
    LOCAL upVec IS UP:FOREVECTOR.

    IF altAGL > FINAL_GIMBAL_ENABLE_M OR altAGL < FINAL_GIMBAL_FADE_M OR padDistM > FINAL_GIMBAL_DIST_M {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    // North/south is already well tuned on the other pads, so bias the tiny
    // engine-centering trim toward east/west where the repeatable miss remains.
    LOCAL northErrM IS targetNorthErrM() * 0.35.
    LOCAL eastErrM  IS targetEastErrM().   // positive means pad is east of the booster; tilt east
    LOCAL northAxis IS HEADING(0,0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90,0):FOREVECTOR.
    LOCAL toPadVec  IS northAxis * northErrM + eastAxis * eastErrM.
    LOCAL horizVec  IS toPadVec - VDOT(toPadVec, upVec) * upVec.

    IF horizVec:MAG < 0.001 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL altFade IS Clamp((altAGL - FINAL_GIMBAL_FADE_M) / MAX(1, (FINAL_GIMBAL_ENABLE_M - FINAL_GIMBAL_FADE_M)), 0, 1).
    LOCAL distFade IS Clamp((FINAL_GIMBAL_DIST_M - padDistM) / FINAL_GIMBAL_DIST_M, 0.35, 1).
    LOCAL tiltDeg IS FINAL_GIMBAL_MAX_DEG * altFade * distFade.
    LOCAL steerVec IS upVec + horizVec:NORMALIZED * TAN(tiltDeg).

    RETURN LOOKDIRUP(steerVec:NORMALIZED, SHIP:FACING:TOPVECTOR).
}

// ============================================================
//  SUICIDE THROTTLE
//  Hover-slam style ratio controller. Keep descending until low altitude
//  instead of zeroing out all velocity kilometres above the pad.
// ============================================================
FUNCTION terminalPadSteerDir {
    PARAMETER padDistKmIn.

    LOCAL altAGL IS MAX(0, terrainAGL()).
    LOCAL padDistM IS padDistKmIn * 1000.
    LOCAL upVec IS UP:FOREVECTOR.

    IF altAGL > TERM_STEER_ENABLE_M OR altAGL < TERM_STEER_FADE_M OR padDistM > TERM_STEER_DIST_M {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL northAxis IS HEADING(0,0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90,0):FOREVECTOR.

    LOCAL northErr IS targetNorthErrM() * TERM_STEER_NORTH_WT.
    LOCAL eastErr  IS targetEastErrM()  * TERM_STEER_EAST_WT.
    LOCAL errVec   IS northAxis * northErr + eastAxis * eastErr.
    LOCAL errMag   IS errVec:MAG.

    LOCAL horizVel IS SHIP:VELOCITY:SURFACE
                   - VDOT(SHIP:VELOCITY:SURFACE, upVec) * upVec.

    LOCAL desVel IS V(0,0,0).
    IF errMag > TERM_STEER_DEADBAND_M {
        LOCAL closeSpd IS MIN(TERM_STEER_MAX_VEL, errMag * TERM_STEER_KP_POS).
        IF errMag < TERM_STEER_FINAL_M {
            SET closeSpd TO 0.
        }
        SET desVel TO errVec:NORMALIZED * closeSpd.
    }

    LOCAL accCmd IS (desVel - horizVel) * TERM_STEER_KP_VEL.
    IF accCmd:MAG > TERM_STEER_MAX_ACC {
        SET accCmd TO accCmd:NORMALIZED * TERM_STEER_MAX_ACC.
    }

    IF accCmd:MAG < 0.05 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL altFade IS Clamp((altAGL - TERM_STEER_FADE_M) / MAX(1, (TERM_STEER_ENABLE_M - TERM_STEER_FADE_M)), 0, 1).
    LOCAL maxLatMag IS (LAT_UP_BIAS_ACC * TAN(TERM_STEER_MAX_DEG)) * altFade.
    IF accCmd:MAG > maxLatMag {
        SET accCmd TO accCmd:NORMALIZED * maxLatMag.
    }

    LOCAL aimVec IS (upVec * LAT_UP_BIAS_ACC + accCmd):NORMALIZED.
    RETURN LOOKDIRUP(aimVec, SHIP:FACING:TOPVECTOR).
}


// ============================================================
//  CLEAN-SHEET LANDING GUIDANCE
//  One capped PD lateral controller for the landing burn.
//  It commands tilt directly from north/east position and velocity,
//  instead of switching among several competing terminal controllers.
// ============================================================
FUNCTION landingGuideDir {
    PARAMETER finalMode.

    LOCAL upVec IS UP:FOREVECTOR.
    // IF terrainAGL() < 150 {
    //     // Last 100 m: strictly upright for straight up/down touchdown.
    //     RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    // }
    LOCAL horizVel IS SHIP:VELOCITY:SURFACE
                - VDOT(SHIP:VELOCITY:SURFACE, upVec) * upVec.
    LOCAL hSpd IS horizVel:MAG.

    IF terrainAGL() < 150 AND hSpd < 1.0 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL northAxis IS HEADING(0,0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90,0):FOREVECTOR.

    LOCAL nErr IS targetNorthErrM() * LAND_NORTH_WEIGHT.
    LOCAL eErr IS targetEastErrM()  * LAND_EAST_WEIGHT.

    LOCAL nVel IS VDOT(SHIP:VELOCITY:SURFACE, northAxis).
    LOCAL eVel IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    LOCAL padDistM IS SQRT(nErr * nErr + eErr * eErr).
    LOCAL horizVelVec IS northAxis * nVel + eastAxis * eVel.
    LOCAL hSpdLocal IS horizVelVec:MAG.
    LOCAL altAGL IS MAX(0, terrainAGL()).

    // ===== ADD THIS RIGHT HERE =====
    IF altAGL < 400 AND padDistM < 80 {
        LOCAL posToPad IS (northAxis * nErr + eastAxis * eErr).
        LOCAL killVec IS (-1 * horizVelVec) + (0.35 * posToPad).

        IF killVec:MAG > 0.001 {
            SET killVec TO killVec:NORMALIZED * MIN(LAND_UP_BIAS_ACC * TAN(8), MAX(0.6, hSpdLocal)).
            RETURN LOOKDIRUP((upVec * LAND_UP_BIAS_ACC + killVec):NORMALIZED, SHIP:FACING:TOPVECTOR).
        }
    }
    // ===== END INSERT =====

    // If we are already basically over the pad, stop chasing position
    // and just kill sideways motion.
    IF padDistM < 80 AND hSpdLocal > 1.0 {
        LOCAL killVec IS (-1 * horizVelVec).
        IF killVec:MAG > 0.001 {
            SET killVec TO killVec:NORMALIZED * MIN(LAND_UP_BIAS_ACC * TAN(12), hSpdLocal * 0.8).
            RETURN LOOKDIRUP((upVec * LAND_UP_BIAS_ACC + killVec):NORMALIZED, SHIP:FACING:TOPVECTOR).
        }
    }

    LOCAL posKp IS LAND_POS_KP_APPROACH.
    LOCAL maxVel IS LAND_MAX_VEL_APPROACH.
    LOCAL velKp IS LAND_VEL_KP_APPROACH.
    LOCAL maxAcc IS LAND_MAX_ACC_APPROACH.
    LOCAL maxTilt IS LAND_TILT_MAX_APPROACH.

    IF finalMode {
        SET posKp TO LAND_POS_KP_FINAL.
        SET maxVel TO LAND_MAX_VEL_FINAL.
        SET velKp TO LAND_VEL_KP_FINAL.
        SET maxAcc TO LAND_MAX_ACC_FINAL.
        SET maxTilt TO LAND_TILT_MAX_FINAL.
    }

    LOCAL desNVel IS Clamp(nErr * posKp, -maxVel, maxVel).
    LOCAL desEVel IS Clamp(eErr * posKp, -maxVel, maxVel).

    // Inside a tiny box, stop trying to translate and just damp what remains.
    IF ABS(nErr) < 12 { SET desNVel TO 0. }
    IF ABS(eErr) < 12 { SET desEVel TO 0. }

    LOCAL nAcc IS Clamp((desNVel - nVel) * velKp, -maxAcc, maxAcc).
    LOCAL eAcc IS Clamp((desEVel - eVel) * velKp, -maxAcc, maxAcc).

    LOCAL accVec IS northAxis * nAcc + eastAxis * eAcc.

    IF accVec:MAG < 0.03 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL maxLatMag IS LAND_UP_BIAS_ACC * TAN(maxTilt).
    IF accVec:MAG > maxLatMag {
        SET accVec TO accVec:NORMALIZED * maxLatMag.
    }

    LOCAL steerVec IS (upVec * LAND_UP_BIAS_ACC + accVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

FUNCTION landingThrottleUnified {
    PARAMETER finalMode.

    LOCAL gravAccel IS BODY:MU / (SHIP:ALTITUDE + BODY:RADIUS)^2.
    LOCAL altAGL IS MAX(0, terrainAGL()).
    LOCAL kp IS LAND_THR_KP_APPROACH.
    LOCAL tgtVSpd IS -MAX(18, MIN(150, altAGL * 0.07)).

    IF finalMode {
        SET kp TO LAND_THR_KP_FINAL.
        IF altAGL > 100 {
            SET tgtVSpd TO -14.
        } ELSE IF altAGL > 60 {
            SET tgtVSpd TO -9.
        } ELSE IF altAGL > 25 {
            SET tgtVSpd TO -5.
        } ELSE IF altAGL > 10 {
            SET tgtVSpd TO -2.
        } ELSE {
            SET tgtVSpd TO -1.
        }
    }

    IF altAGL < 100 {
        SET tgtVSpd TO MAX(tgtVSpd, -10).
    }
    IF altAGL < 20 {
        SET tgtVSpd TO MAX(tgtVSpd, -6).
    }
    LOCAL accCmd IS gravAccel + (tgtVSpd - SHIP:VERTICALSPEED) * kp.
    LOCAL thrCmd IS Clamp((SHIP:MASS * accCmd) / MAXTHRUST, 0, 1).
    LOCAL hoverThr IS Clamp((SHIP:MASS * gravAccel) / MAXTHRUST, 0, 1).

    IF oneEngine {
        SET thrCmd TO MAX(MIN_THR_1ENG, thrCmd).
    } ELSE {
        SET thrCmd TO MAX(MIN_THR_3ENG, thrCmd).
    }

    // Never intentionally climb near the ground; stop the pogo.
    IF altAGL < 120 AND SHIP:VERTICALSPEED > -0.5 {
        SET thrCmd TO MIN(thrCmd, MAX(0, hoverThr - 0.02)).
    }
    IF altAGL < 40 AND SHIP:VERTICALSPEED > -0.2 {
        SET thrCmd TO MIN(thrCmd, MAX(0, hoverThr - 0.04)).
    }

    RETURN Clamp(thrCmd, 0, 1).
}

FUNCTION suicideThrottle {
    PARAMETER altAGLIn.

    LOCAL gravAccel IS BODY:MU / (SHIP:ALTITUDE + BODY:RADIUS)^2.
    LOCAL aMaxFull  IS (MAXTHRUST / SHIP:MASS) - gravAccel.
    IF aMaxFull < 0.5 { RETURN 1.0. }

    LOCAL vertSpd IS MAX(0, -SHIP:VERTICALSPEED).
    LOCAL horizSpd IS hSpeed().

    // Keep a reserve so the vehicle is still descending at ~100m instead of
    // killing all motion high and flipping / tail-chasing.
    LOCAL reserveAlt IS 120.
    LOCAL usableAlt  IS MAX(1, altAGLIn - reserveAlt).
    LOCAL vertStopDist IS (vertSpd * vertSpd) / (2 * aMaxFull).
    LOCAL ratio IS vertStopDist / usableAlt.

    // Only a small horizontal penalty here - the main burn should stay mostly vertical.
    SET ratio TO ratio + (horizSpd * 0.004).

    LOCAL thrCmd IS Clamp(ratio, 0.22, 1.0).

    // Never let the suicide phase climb intentionally while still above the reserve window.
    IF altAGLIn > 130 AND SHIP:VERTICALSPEED > -8 {
        SET thrCmd TO MIN(thrCmd, 0.82).
    }

    RETURN thrCmd.
}

// ============================================================
//  LANDING THROTTLE - P-CONTROLLER
//  Final few hundred metres only. No lateral hover floors here.
// ============================================================
FUNCTION landingThrottle {
    PARAMETER padDistKmIn.

    LOCAL gravAccel IS BODY:MU / (SHIP:ALTITUDE + BODY:RADIUS)^2.
    LOCAL altAGL    IS MAX(1, terrainAGL()).
    IF MAXTHRUST < 0.01 { RETURN 0. }

    LOCAL curveTarget IS -(altAGL * VSPEED_COEFF).
    LOCAL tgtVSpd IS MIN(FINAL_VSPEED, MAX(-35, curveTarget)).
    IF altAGL < 220 {
        SET tgtVSpd TO MAX(tgtVSpd, -10).
    }
    IF altAGL < 160 {
        SET tgtVSpd TO MAX(tgtVSpd, -7).
    }
    IF altAGL < 95 {
        SET tgtVSpd TO MAX(tgtVSpd, -4).
    }
    IF altAGL < 35 {
        SET tgtVSpd TO MAX(tgtVSpd, -1.5).
    }

    LOCAL vSpdErr IS tgtVSpd - SHIP:VERTICALSPEED.
    LOCAL accCmd  IS vSpdErr * CTRL_KP + gravAccel.
    LOCAL rawThr  IS (SHIP:MASS * accCmd) / MAXTHRUST.
    LOCAL hoverThr IS Clamp((SHIP:MASS * gravAccel) / MAXTHRUST, 0, 1).

    LOCAL thrCmd IS Clamp(rawThr, 0, 1).
    IF oneEngine AND altAGL < 100 {
        SET thrCmd TO MAX(MIN_THR_1ENG, thrCmd).
    }

    IF SHIP:VERTICALSPEED > 4 {
        SET thrCmd TO MIN(thrCmd, MAX(0, hoverThr - 0.04)).
    }

    RETURN Clamp(thrCmd, 0, 1).
}

// ============================================================
//  BRAKE STEERING
//  During the initial landing burn, do not point purely retrograde
//  when still kilometres off-pad. Blend a small lean toward the pad
//  so we preserve useful crossrange instead of zeroing Hspd too early.
// ============================================================
FUNCTION brakeSteerDir {
    PARAMETER padDistKmIn.

    LOCAL upVec       IS UP:FOREVECTOR.
    LOCAL northAxisB  IS HEADING(0,  0):FOREVECTOR.
    LOCAL eastAxisB   IS HEADING(90, 0):FOREVECTOR.
    LOCAL northErrB   IS targetNorthErrM() * BRAKE_NORTH_WEIGHT.
    LOCAL eastErrB    IS targetEastErrM().
    LOCAL toPadVecB   IS northAxisB * northErrB + eastAxisB * eastErrB.

    IF toPadVecB:MAG < 0.001 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL toPadHoriz  IS toPadVecB:NORMALIZED.
    LOCAL horizVel    IS SHIP:VELOCITY:SURFACE
                      - VDOT(SHIP:VELOCITY:SURFACE, upVec) * upVec.
    LOCAL towardVel   IS VDOT(horizVel, toPadHoriz).
    LOCAL sideVelVec  IS horizVel - toPadHoriz * towardVel.

    LOCAL desiredClose IS MIN(BRAKE_CLOSE_MAX,
                              MAX(12, padDistKmIn * BRAKE_CLOSE_PER_KM)).
    LOCAL towardErr   IS desiredClose - towardVel.
    LOCAL towardAcc   IS towardErr * BRAKE_TOWARD_GAIN.

    // Far from the pad, never point away just to kill useful closing speed.
    IF padDistKmIn > 0.60 AND towardAcc < 0 {
        SET towardAcc TO 0.
    }

    // If brake is already carrying us away from the pad, command a decisive recovery.
    IF padDistKmIn > 1.00 AND towardVel < 0 {
        SET towardAcc TO MAX(towardAcc, MIN(10, 4 + ABS(towardVel) * 0.18)).
    }

    // Kill sideways drift, but do not let side damping dominate the toward-pad command.
    LOCAL sideAccVec IS sideVelVec * -BRAKE_SIDE_DAMP.
    IF sideAccVec:MAG > 7 {
        SET sideAccVec TO sideAccVec:NORMALIZED * 7.
    }

    LOCAL latAccVec IS toPadHoriz * towardAcc + sideAccVec.
    IF latAccVec:MAG > LAT_MAX_ACC {
        SET latAccVec TO latAccVec:NORMALIZED * LAT_MAX_ACC.
    }

    LOCAL aimVec IS (upVec * BRAKE_UP_BIAS_ACC + latAccVec):NORMALIZED.
    LOCAL actualTilt IS VANG(upVec, aimVec).
    IF actualTilt > BRAKE_MAX_TILT {
        LOCAL maxLatMag IS BRAKE_UP_BIAS_ACC * TAN(BRAKE_MAX_TILT).
        IF latAccVec:MAG > 0.001 {
            SET latAccVec TO latAccVec:NORMALIZED * MIN(maxLatMag, LAT_MAX_ACC).
            SET aimVec TO (upVec * BRAKE_UP_BIAS_ACC + latAccVec):NORMALIZED.
        } ELSE {
            SET aimVec TO upVec.
        }
    }

    RETURN LOOKDIRUP(aimVec, SHIP:FACING:TOPVECTOR).
}

// ============================================================
//  LATERAL STEERING - TWO-AXIS CASCADED CONTROLLER
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
//  directions are corrected - fixes the south miss that
//  single-bearing controllers miss entirely.
// ============================================================
FUNCTION lateralSteerDir {
    PARAMETER padDistKmIn.

    LOCAL altAGL IS terrainAGL().
    IF padDistKmIn < 0.03 AND altAGL < 40 {
        RETURN LOOKDIRUP(UP:FOREVECTOR, HEADING(0,0):FOREVECTOR).
    }

    LOCAL northAxis IS HEADING(0,  0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90, 0):FOREVECTOR.

    LOCAL northErr IS targetNorthErrM().
    LOCAL eastErr  IS targetEastErrM().
    LOCAL errVec   IS northAxis * (northErr * LAT_NORTH_WEIGHT) + eastAxis * eastErr.
    LOCAL errMag   IS errVec:MAG.

    LOCAL horizVel IS SHIP:VELOCITY:SURFACE
                   - VDOT(SHIP:VELOCITY:SURFACE, UP:FOREVECTOR) * UP:FOREVECTOR.

    IF errMag < LAT_DEADBAND_M {
        LOCAL dampAccVec IS horizVel * -0.22.
        IF dampAccVec:MAG < 0.1 {
            RETURN LOOKDIRUP(UP:FOREVECTOR, HEADING(0,0):FOREVECTOR).
        }
        IF dampAccVec:MAG > 5 {
            SET dampAccVec TO dampAccVec:NORMALIZED * 5.
        }
        RETURN LOOKDIRUP((UP:FOREVECTOR * LAT_UP_BIAS_ACC + dampAccVec):NORMALIZED,
                         HEADING(0,0):FOREVECTOR).
    }

    LOCAL errUnit IS errVec:NORMALIZED.
    LOCAL closingToward IS VDOT(horizVel, errUnit).
    LOCAL stopDist IS 0.
    IF closingToward > 0 {
        SET stopDist TO (closingToward * closingToward) / (2 * LAT_STOP_ACC).
    }

    LOCAL captureMode IS FALSE.
    IF (errMag < LAT_CAPTURE_DIST_M AND altAGL < LAT_CAPTURE_ALT_M) OR altAGL < 350 {
        SET captureMode TO TRUE.
    }

    LOCAL desVelVec IS V(0,0,0).
    IF captureMode {
        LOCAL captureSpeed IS 0.
        IF errMag > LAT_CAPTURE_FINAL_M AND altAGL > 120 {
            SET captureSpeed TO MIN(18, SQRT(MAX(0, 2 * LAT_STOP_ACC * MAX(0, errMag - LAT_DEADBAND_M)))).
        }
        // If we are already crossing over the pad region quickly, start killing crossrange now.
        IF closingToward > captureSpeed + 3 {
            SET captureSpeed TO 0.
        }
        SET desVelVec TO errUnit * captureSpeed.
    } ELSE {
        LOCAL stopLimitedSpeed IS SQRT(MAX(0, 2 * LAT_STOP_ACC * MAX(0, errMag - LAT_DEADBAND_M))).
        LOCAL desiredSpeed IS MIN(MIN(LAT_MAX_VEL, errMag * LAT_KP_POS), stopLimitedSpeed).
        SET desVelVec TO errUnit * desiredSpeed.

        IF errMag > LAT_NO_REVERSE_M AND stopDist < errMag * 0.60 AND closingToward > desiredSpeed {
            SET desVelVec TO errUnit * closingToward.
        }
    }

    LOCAL velGain IS LAT_KP_VEL.
    IF captureMode {
        SET velGain TO LAT_KP_VEL * 1.35.
    }
    LOCAL accCmdVec IS (desVelVec - horizVel) * velGain.

    IF NOT captureMode AND errMag > LAT_NO_REVERSE_M AND stopDist < errMag * 0.60 {
        LOCAL towardAcc IS VDOT(accCmdVec, errUnit).
        IF towardAcc < 0 {
            LOCAL tangentialAcc IS accCmdVec - errUnit * VDOT(accCmdVec, errUnit).
            SET accCmdVec TO tangentialAcc * 0.25.
        }
    }

    LOCAL accScale IS 1.0.
    IF captureMode {
        IF altAGL < 1800 {
            SET accScale TO Clamp((altAGL - 60) / 1740, 0.55, 1.0).
        }
    } ELSE IF altAGL < 1800 {
        SET accScale TO Clamp((altAGL - 150) / 1650, 0.35, 1.0).
    }
    SET accCmdVec TO accCmdVec * accScale.

    IF accCmdVec:MAG > LAT_MAX_ACC {
        SET accCmdVec TO accCmdVec:NORMALIZED * LAT_MAX_ACC.
    }

    IF accCmdVec:MAG < 0.1 {
        RETURN LOOKDIRUP(UP:FOREVECTOR, HEADING(0,0):FOREVECTOR).
    }

    LOCAL aimVec IS (UP:FOREVECTOR * LAT_UP_BIAS_ACC + accCmdVec):NORMALIZED.
    LOCAL actualTilt IS VANG(UP:FOREVECTOR, aimVec).
    IF actualTilt > LAT_MAX_DEG {
        LOCAL maxLatMag IS LAT_UP_BIAS_ACC * TAN(LAT_MAX_DEG).
        SET accCmdVec TO accCmdVec:NORMALIZED * MIN(maxLatMag, LAT_MAX_ACC).
        SET aimVec TO (UP:FOREVECTOR * LAT_UP_BIAS_ACC + accCmdVec):NORMALIZED.
    }

    RETURN LOOKDIRUP(aimVec, HEADING(0,0):FOREVECTOR).
}

// ============================================================
//  INITIALIZATION
// ============================================================
CLEARSCREEN.
logOpen().
logEvent("SCRIPT START - Pad:" + PAD_LAT + "/" + PAD_LNG + "/" + PAD_ALT).

PRINT "╔══════════════════════════════════════╗" AT (0, 0).
PRINT "║   FALCON 9 RTLS  -  KERBAL SCALE     ║" AT (0, 1).
PRINT "╚══════════════════════════════════════╝" AT (0, 2).
PRINT "Pad: " + PAD_LAT + " / " + PAD_LNG           AT (0, 3).
PRINT "Elev: " + PAD_ALT + "m   Log: 0:/rtls_log.txt" AT (0, 4).
PRINT "                                        " AT (0, 5).

LOCK THROTTLE TO 0.
LOCK STEERING TO UP.
SAS OFF.
RCS ON.
clearRcsAssist().

activateAG(2).
logEvent("AG2 fired - 3 engines enabled").
logEvent("1101 CFG RCSALT:" + RCS_ENABLE_ALT_M
         + " RCSDIST:" + RCS_ENABLE_DIST_M
         + " GMBALT:" + FINAL_GIMBAL_ENABLE_M
         + " GMBDIST:" + FINAL_GIMBAL_DIST_M
         + " GMBDEG:" + FINAL_GIMBAL_MAX_DEG
         + " GMBHSPD:" + FINAL_GIMBAL_MAX_HSPD).

PRINT "1101 CFG RCS:" + RCS_ENABLE_ALT_M + "/" + RCS_ENABLE_DIST_M
      + " GMB:" + FINAL_GIMBAL_ENABLE_M + "/" + FINAL_GIMBAL_DIST_M
      + " deg:" + FINAL_GIMBAL_MAX_DEG
      AT (0, 5).        

// ============================================================
//  MAIN GUIDANCE LOOP
// ============================================================
UNTIL phase = PH_TOUCHDOWN {

    IF phase < PH_AERO {
        SET activePadGeo TO padGeo.
    } ELSE {
        SET activePadGeo TO finalPadGeo().
    }

    LOCAL altAGL    IS terrainAGL().
    LOCAL padDistKm IS distKm(SHIP:GEOPOSITION, activePadGeo).
    LOCAL hSpd      IS hSpeed().

    // ──────────────────────────────────────────────────────
    //  PHASE 0: FLIP
    //  Rotate to level heading aimed directly at the pad.
    //  Aim uses predicted-impact N/E error, not a fixed due-west guess.
    // ──────────────────────────────────────────────────────
    IF phase = PH_FLIP {
        LOCAL aimGeo     IS boostbackAimGeo().
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
            SET bbPrevDist  TO 99999.
            SET bbRiseCount TO 0.
            SET phase TO PH_BOOSTBACK.
            logEvent("FLIP complete - BOOSTBACK brng:" + ROUND(padBearing,1)).
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 1: BOOSTBACK
    //  Level burn aimed using predicted-impact N/E correction.
    //  Throttle tapers 100% → 3% as predicted impact closes
    //  to prevent overshooting. Terminates on:
    //    - predicted impact within BB_TOL_KM of pad
    //    - overshoot detected (impact moving away)
    //    - timeout (120 s)
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_BOOSTBACK {
        LOCAL aimGeo     IS boostbackAimGeo().
        LOCAL padBearing IS bearingTo(aimGeo).
        LOCK STEERING TO HEADING(padBearing, 0).

        LOCAL impactPos IS getImpact().
        LOCAL impDist   IS distKm(impactPos, padGeo).
        LOCAL northErrImp IS ROUND((PAD_LAT - impactPos:LAT) * KERBIN_M_PER_DEG, 0).
        LOCAL eastErrImp  IS ROUND((PAD_LNG - impactPos:LNG) * KERBIN_M_PER_DEG
                                   * COS(PAD_LAT), 0).

        // Target metric for boostback: north error near zero, east error intentionally
        // WEST of the pad to compensate the systematic east drift seen after aero.
        LOCAL bbTargetDist IS SQRT(northErrImp^2 + (eastErrImp - BB_TARGET_EAST_M)^2) / 1000.
        IF bbTargetDist < bbMinDist { SET bbMinDist TO bbTargetDist. }

        // Throttle taper against the bias-corrected target distance, not the raw pad miss.
        LOCAL bbThr IS 1.0.
        IF bbTargetDist < 20 { SET bbThr TO Clamp(bbTargetDist / 20, 0.15, 1.0). }
        IF bbTargetDist < 10 { SET bbThr TO Clamp(bbTargetDist / 35, 0.06, bbThr). }
        LOCK THROTTLE TO bbThr.

        LOCAL bbElapsed IS TIME:SECONDS - bbStartTime.
        LOCAL bbRcsStatus IS "OFF".
        RCS ON.
        SET bbRcsStatus TO updateMidcourseRcsAssist(aimGeo).

        // Overshoot detection against the bias-corrected target.
        IF bbTargetDist > bbPrevDist + 0.05 {
            SET bbRiseCount TO bbRiseCount + 1.
        } ELSE IF bbTargetDist < bbPrevDist - 0.05 {
            SET bbRiseCount TO 0.
        }
        SET bbPrevDist TO bbTargetDist.

        LOCAL axisGood IS (ABS(northErrImp) < BB_AXIS_TOL_M
                           AND ABS(eastErrImp - BB_TARGET_EAST_M) < BB_AXIS_TOL_M).
        LOCAL overshoot IS (axisGood AND ((bbMinDist < 1.8 AND bbRiseCount >= 2)
                           OR (bbMinDist < 3.0 AND bbRiseCount >= 4))).

        PRINT "[ BOOSTBACK ]  Pred:" + ROUND(impDist,1) + "km  Tgt:"
              + ROUND(bbTargetDist,1) + "km   " AT (0, 6).
        PRINT "  Thr:" + ROUND(bbThr*100,0) + "%  Spd:"
              + ROUND(SHIP:VELOCITY:SURFACE:MAG,0) + "m/s RCS:"
              + bbRcsStatus + "   " AT (0, 7).
        logPeriodic("pred:" + ROUND(impDist,1) + " tgt:" + ROUND(bbTargetDist,1)
                    + " min:" + ROUND(bbMinDist,1)
                    + " thr:" + ROUND(bbThr*100,0) + " Hspd:" + ROUND(hSpd,1)
                    + " rise:" + bbRiseCount + " N:" + northErrImp + " E:" + eastErrImp
                    + " Etgt:" + ROUND(BB_TARGET_EAST_M,0)
                    + " aimBrg:" + ROUND(padBearing,1)
                    + " rcs:" + bbRcsStatus).

        IF (bbTargetDist < BB_TOL_KM AND axisGood) OR overshoot OR bbElapsed > 120 {
            LOCK THROTTLE TO 0.
            SET lastPredTime TO -999.
            SET phase TO PH_COAST.
            logEvent("BOOSTBACK end - pred:" + ROUND(impDist,1) + " tgt:"
                     + ROUND(bbTargetDist,1) + " min:" + ROUND(bbMinDist,1)
                     + " Hspd:" + ROUND(hSpd,1)
                     + " rise:" + bbRiseCount + " overshoot:" + overshoot + " elapsed:"
                     + ROUND(bbElapsed,0) + " N:" + northErrImp + " E:" + eastErrImp).
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
        LOCAL coastRcsStatus IS "OFF".
        RCS ON.

        IF SHIP:ALTITUDE < 45000 AND SHIP:VERTICALSPEED < -50
        AND NOT GridFin {
            activateAG(1).
            setFinAuthority(FIN_AUTH_COAST).
            SET GridFin TO TRUE.
            logEvent("Fins deployed passive auth:" + FIN_AUTH_COAST
                     + "%, alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "km").
        }

        IF SHIP:VERTICALSPEED < -1 {
            LOCK STEERING TO SHIP:SRFRETROGRADE.
        } ELSE {
            LOCK STEERING TO UP.
        }

        IF SHIP:ALTITUDE > MID_RCS_MIN_ALT_M {
            SET coastRcsStatus TO updateMidcourseRcsAssist(padGeo).
        } ELSE {
            clearRcsAssist().
            SET coastRcsStatus TO "COAST".
        }

        LOCAL impactPos IS getImpact().
        LOCAL impDist   IS distKm(impactPos, padGeo).
        LOCAL northErrCo IS ROUND(targetNorthErrM(), 0).
        LOCAL eastErrCo  IS ROUND(targetEastErrM(), 0).

        PRINT "[ COAST ]  Alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "km  VS:"
              + ROUND(SHIP:VERTICALSPEED,0) + "m/s   " AT (0, 6).
        PRINT "  Pred:" + ROUND(impDist,1) + "km  " + nsText(northErrCo)
              + "  " + ewText(eastErrCo) + " RCS:" + coastRcsStatus + "   " AT (0, 7).
        logPeriodic("BALLISTIC pred:" + ROUND(impDist,1) + " pad:" + ROUND(padDistKm,1)
                    + " N:" + northErrCo + " E:" + eastErrCo
                    + " rcs:" + coastRcsStatus).

        IF SHIP:VERTICALSPEED < -1 AND SHIP:ALTITUDE < ENTRY_ALT {
            SET phase TO PH_ENTRY.
            logEvent("COAST->ENTRY spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                     + " pad:" + ROUND(padDistKm,2) + "km").
        }
        ELSE IF SHIP:VERTICALSPEED < -1
        AND altAGL <= ignitionAlt() {
            LOCK THROTTLE TO 0.
            clearRcsAssist().
            SET phase TO PH_LANDING.
            logEvent("COAST->LANDING alt:" + ROUND(SHIP:ALTITUDE/1000,1)
                     + "km VS:" + ROUND(SHIP:VERTICALSPEED,0)
                     + " ignAlt:" + ROUND(ignitionAlt()/1000,1) + "km").
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 3: ENTRY BURN
    //  Full throttle SRFRETROGRADE to kill speed to 400 m/s.
    //  Fins at 60% steer laterally toward pad during the burn.
    //  This is the first of the two burns - mimics real F9
    //  entry burn that protects engines from aero heating.
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_ENTRY {
        LOCK STEERING TO SHIP:SRFRETROGRADE.
        LOCK THROTTLE TO 1.0.
        RCS ON.
        LOCAL entryRcsStatus IS "OFF".
        IF SHIP:ALTITUDE > MID_RCS_MIN_ALT_M {
            SET entryRcsStatus TO updateMidcourseRcsAssist(padGeo).
        } ELSE {
            clearRcsAssist().
            SET entryRcsStatus TO "COAST".
        }

        IF GridFin AND NOT finAeroSet {
            setFinAuthority(FIN_AUTH_AERO).
            SET finAeroSet TO TRUE.
        }

        PRINT "[ ENTRY ]  Spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0) + "m/s   " AT (0, 6).
        PRINT "  Pad:" + ROUND(padDistKm,2) + "km  RCS:" + entryRcsStatus + "      " AT (0, 7).
        logPeriodic("ENTRY spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                    + " pad:" + ROUND(padDistKm,2)
                    + " hspd:" + ROUND(hSpd,1)
                    + " rcs:" + entryRcsStatus).

        IF SHIP:VELOCITY:SURFACE:MAG <= ENTRY_SPEED {
            LOCK THROTTLE TO 0.
            clearRcsAssist().
            SET phase TO PH_AERO.
            logEvent("ENTRY->AERO spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                     + " pad:" + ROUND(padDistKm,2) + "km hspd:" + ROUND(hSpd,1)).
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 4: AERO DESCENT
    //  Engines off. Fins at 60% authority actively steer the
    //  booster laterally toward the pad by leaning the nose
    //  toward the pad from the SRFRETROGRADE vector.
    //  This replaces the bias correction system - the fins
    //  do the lateral work aerodynamically.
    //  Transition to LANDING when ignitionAlt reached.
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_AERO {
        LOCK THROTTLE TO 0.
        RCS ON.

        IF GridFin AND NOT finAeroSet {
            setFinAuthority(FIN_AUTH_AERO).
            SET finAeroSet TO TRUE.
        }

        IF padDistKm < aeroBestPadKm {
            SET aeroBestPadKm TO padDistKm.
        }
        IF padDistKm < 0.50 {
            SET aeroClosePass TO TRUE.
        }
        IF aeroFinTrimEnabled
           AND aeroClosePass
           AND padDistKm > aeroBestPadKm + 0.35
           AND SHIP:ALTITUDE < 28000 {
            SET aeroFinTrimEnabled TO FALSE.
            logEvent("AERO trim disabled after close pass best:" + ROUND(aeroBestPadKm,2)
                     + " now:" + ROUND(padDistKm,2)).
        }

        LOCAL aeroRcsStatus IS "OFF".
        IF SHIP:ALTITUDE > MID_RCS_MIN_ALT_M {
            SET aeroRcsStatus TO updateMidcourseRcsAssist(activePadGeo).
        } ELSE {
            clearRcsAssist().
            SET aeroRcsStatus TO "OFF".
        }

        IF aeroFinTrimEnabled {
            LOCK STEERING TO finSteerDir(padDistKm).
        } ELSE {
            LOCK STEERING TO SHIP:SRFRETROGRADE.
        }

        LOCAL ignAlt IS ignitionAlt().
        LOCAL northErrA IS ROUND(targetNorthErrM(), 0).
        LOCAL eastErrA  IS ROUND(targetEastErrM(), 0).
        LOCAL aeroFinText IS "OFF".
        IF aeroFinTrimEnabled { SET aeroFinText TO "ON". }

        PRINT "[ AERO ]  Alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "km  VS:"
              + ROUND(SHIP:VERTICALSPEED,0) + "m/s   " AT (0, 6).
        PRINT "  Hspd:" + ROUND(hSpd,1) + "  " + nsText(northErrA)
              + "  " + ewText(eastErrA)
              + " F:" + aeroFinText
              + " RCS:" + aeroRcsStatus + "   " AT (0, 7).
        logPeriodic("AERO pad:" + ROUND(padDistKm,2) + " hspd:" + ROUND(hSpd,1)
                    + " ignAlt:" + ROUND(ignAlt/1000,1)
                    + " VS:" + ROUND(SHIP:VERTICALSPEED,0)
                    + " N:" + northErrA + " E:" + eastErrA
                    + " fin:" + aeroFinText
                    + " rcs:" + aeroRcsStatus).

        IF altAGL <= ignAlt {
            LOCK THROTTLE TO 0.
            clearRcsAssist().
            SET phase TO PH_LANDING.
            logEvent("AERO->LANDING alt:" + ROUND(SHIP:ALTITUDE/1000,1)
                     + "km AGL:" + ROUND(altAGL,0)
                     + "m VS:" + ROUND(SHIP:VERTICALSPEED,0)
                     + " Hspd:" + ROUND(hSpd,1)
                     + " pad:" + ROUND(padDistKm,2) + "km"
                     + " ignAlt:" + ROUND(ignAlt/1000,1) + "km").
        }
    }

    // ──────────────────────────────────────────────────────
    //  PHASE 5: LANDING BURN
    //  This is the second burn - the suicide/hover-slam.
    //
    //  SUB-PHASE A - SRFRETROGRADE BRAKE
    //    Full throttle SRFRETROGRADE from ignition altitude.
    //    Kills both VS and Hspd proportionally.
    //    Throttle = 0 if ascending (brief overshoot recovery).
    //    Exits when VS > BRAKE_EXIT_VS (-80 m/s) or < 1500m AGL.
    //
    //  SUB-PHASE B - P-CONTROLLER DESCENT
    //    Steers UP. Freefalls from brake exit (~4km) until
    //    curve target takes over (~1.2km). Then arrests sharply.
    //    3 engines -> 1 engine at SWITCH_ALT when VS > -15.
    // ──────────────────────────────────────────────────────
    ELSE IF phase = PH_LANDING {

        RCS ON.
        LOCAL landRcsStatus IS "OFF".

        IF NOT legsOut AND altAGL < LEG_DEPLOY_ALT {
            GEAR ON.
            SET legsOut TO TRUE.
            logEvent("LEGS deployed at " + ROUND(altAGL,0) + "m AGL").
            PRINT "*** LEGS DEPLOYED ***              " AT (0, 9).
        }

        // Approach -> Final handoff: do it once, at a sane altitude, not on the deck.
        IF NOT lbrakeDone {
            IF ((altAGL < 80) AND hSpd < 1.5 AND (padDistKm * 1000) < 80)
            OR (altAGL < 20) {
                SET lbrakeDone TO TRUE.
                clearRcsAssist().
                logEvent("APPROACH->FINAL VS:" + ROUND(SHIP:VERTICALSPEED,1)
                        + " Hspd:" + ROUND(hSpd,1)
                        + " alt:" + ROUND(altAGL,0) + "m"
                        + " pad:" + ROUND(padDistKm,2) + "km").
                PRINT "*** FINAL SETTLE ***              " AT (0, 9).
            }
        }

        IF lbrakeDone
        AND NOT oneEngine
        AND altAGL < LAND_FINAL_ONE_ENG_ALT
        AND SHIP:VERTICALSPEED < -1
        AND SHIP:VERTICALSPEED > LAND_FINAL_ONE_ENG_VS
        AND hSpd < 3.0 {
            activateAG(3).
            SET oneEngine TO TRUE.
            logEvent("1-ENGINE at " + ROUND(altAGL,0) + "m VS:"
                     + ROUND(SHIP:VERTICALSPEED,1)
                     + " Hspd:" + ROUND(hSpd,1)).
            PRINT "*** 1 ENGINE ***                   " AT (0, 9).
        }

        LOCK STEERING TO landingGuideDir(lbrakeDone).

        IF ((padDistKm * 1000) < 120 AND hSpd > 0.8)
        OR ((padDistKm * 1000) < 250 AND altAGL < 600)
        OR (lbrakeDone AND altAGL < LAND_RCS_ENABLE_ALT_M) {
            SET landRcsStatus TO updateRcsAssist(padDistKm).
        } ELSE {
            clearRcsAssist().
            SET landRcsStatus TO "OFF".
        }

        LOCAL landThrCmd IS landingThrottleUnified(lbrakeDone).
        LOCK THROTTLE TO landThrCmd.

        LOCAL northErrDisp IS ROUND(targetNorthErrM(), 0).
        LOCAL eastErrDisp  IS ROUND(targetEastErrM(), 0).
        LOCAL modeText IS "APPROACH".
        IF lbrakeDone { SET modeText TO "FINAL". }

        PRINT "[ " + modeText + " ]  AGL:" + ROUND(altAGL,0) + "m  VS:"
              + ROUND(SHIP:VERTICALSPEED,1) + "   " AT (0, 6).
        PRINT "  Thr:" + ROUND(landThrCmd*100,0) + "%  "
              + nsText(northErrDisp) + "  " + ewText(eastErrDisp)
              + "  RCS:" + landRcsStatus + "   " AT (0, 7).

        LOCAL engineText IS "3".
        IF oneEngine { SET engineText TO "1". }
        logPeriodic(modeText + " thr:" + ROUND(landThrCmd*100,0)
                    + " VS:" + ROUND(SHIP:VERTICALSPEED,1)
                    + " Hspd:" + ROUND(hSpd,1)
                    + " pad:" + ROUND(padDistKm,2)
                    + " N:" + northErrDisp + " E:" + eastErrDisp
                    + " rcs:" + landRcsStatus
                    + " eng:" + engineText).

        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED"
        OR (altAGL < 1.5
            AND SHIP:VERTICALSPEED > -4
            AND SHIP:VERTICALSPEED < 2
            AND hSpd < 3) {
            SET phase TO PH_TOUCHDOWN.
            logEvent("TOUCHDOWN VS:" + ROUND(SHIP:VERTICALSPEED,1)
                     + " Hspd:" + ROUND(hSpd,1)
                     + " Pad:" + ROUND(padDistKm,2) + "km"
                     + " lat:" + ROUND(SHIP:LATITUDE,4)
                     + " lng:" + ROUND(SHIP:LONGITUDE,4)).
        }
    }
    WAIT 0.
}

// ============================================================
//  TOUCHDOWN - clean up
// ============================================================
LOCK THROTTLE TO 0.
clearRcsAssist().
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.  // Resets all control inputs (including RCS translation)
WAIT 1.
UNLOCK STEERING.
WAIT 1.
UNLOCK THROTTLE.
WAIT 1.
SAS OFF.
RCS OFF.
WAIT 1.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
setFinAuthority(0).

LOCAL finalDist IS distKm(SHIP:GEOPOSITION, padGeo).
logEvent("SCRIPT END - lat:" + ROUND(SHIP:LATITUDE,4)
         + " lng:" + ROUND(SHIP:LONGITUDE,4)
         + " pad dist:" + ROUND(finalDist,2) + "km").

PRINT "                                        " AT (0, 6).
PRINT "                                        " AT (0, 7).
PRINT "+--------------------------------------+" AT (0, 6).
PRINT "| TOUCHDOWN - Engines cut.             |" AT (0, 7).
PRINT "| Log saved: 0:/rtls_log.txt           |" AT (0, 8).
PRINT "+--------------------------------------+" AT (0, 9).
PRINT "Dist to pad: " + ROUND(finalDist,2) + " km          " AT (0, 10).
SAS OFF. 
WAIT 1.
UNLOCK ALL.
WAIT 1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.  // Resets all control inputs (including RCS translation)
WAIT 1.
PRINT "Booster disabled." AT (0, 10).
PRINT "END PROGRAM." AT (0, 11).
