// ============================================================
// rtls.ks  (RTLS with accuracy-recovered fast landing profile)
//
// Proof-of-geometry RTLS with terminal hoverslam/settle. Entry and AERO
// still do the heavy precision work; the landing burn should preserve the
// solved miss instead of chasing tiny final errors into horizontal speed.
//
// Phases:
//   INIT -> FLIP -> BOOSTBACK -> CORRECTIVE -> COAST -> ENTRY -> AERO -> LANDING -> TOUCHDOWN -> IMPACT
//
// Design notes:
//   * Controls are locked once before the phase loop; the loop only updates
//     throttle and steering command variables.
//   * Entry and AERO solve the lateral approach before powered landing.
//   * LANDING uses predicted miss and ZEM/ZEV-style capture while preserving
//     vertical thrust margin for the hoverslam.
//   * TOUCHDOWN is a short settle/cutoff phase, not a lateral chase phase.
//
// ============================================================

@LAZYGLOBAL OFF.

PARAMETER padLatP IS -0.0972.
PARAMETER padLngP IS -74.5577.

// ------------------------------------------------------------
// Constants
// ------------------------------------------------------------
// Debug logging. TRUE generates 0:/rtls_log.txt for post-flight review.
LOCAL DEBUG_LOG          IS FALSE.
LOCAL LOG_PATH           IS "0:/rtls_log.txt".
LOCAL LOG_DT             IS 1.5.

// Terminal display. Designed for a 50 x 36 kOS terminal.
LOCAL DISP_W             IS 50.
LOCAL DISP_H             IS 36.
LOCAL DISP_BAR           IS "==================================================".

// Boostback
LOCAL FLIP_PITCH         IS 6.
LOCAL FLIP_TOL           IS 4.
LOCAL BB_TOWARD_BAND     IS 5.
LOCAL BB_HEADING_MAX     IS 6.
LOCAL BB_MAX_TIME        IS 96.
LOCAL BB_REV_FLOOR       IS 10.
// Dynamic boostback target bounds + over-boost margin
LOCAL BB_TOWARD_MIN      IS 55.      // hard floor (very close pads)
LOCAL BB_TOWARD_MAX      IS 150.     // hard ceiling; avoid excessive padward energy
LOCAL BB_TOWARD_MARGIN   IS 2.       // small boostback bias; avoid overshooting the pad
LOCAL BB_AH_FRAC         IS 0.70.    // conservative fraction of thrust*sin(lean)

// Corrective
LOCAL CORR_MAX_TIME      IS 20.
LOCAL CORR_TURN_ERR      IS 6.
LOCAL CORR_ALIGN_VELERR  IS 1.5.
LOCAL CORR_ALIGN_CROSS   IS 3.
LOCAL CORR_ALIGN_MIN_T   IS 2.5.
LOCAL CORR_ALIGN_THR     IS 0.10.

// Coast
LOCAL COAST_FIN_ALT      IS 45000.

// Entry (ZEM/ZEV guidance, short burn)
LOCAL ENTRY_TRIGGER_ALT  IS 35000.
LOCAL ENTRY_MIN_TIME     IS 2.
LOCAL ENTRY_MAX_TIME     IS 20.       // tight runaway guard; typical burn 8-14s
LOCAL ENTRY_MISS_EXIT    IS 250.      // "centered" fallback exit (rarely needed)
LOCAL ENTRY_HS_EXIT      IS 35.       // HS braked enough for AERO to handle.
LOCAL ENTRY_CENTER_PRED_EXIT IS 500.   // do not drop engines just because current miss crosses pad; predicted miss must also be reasonable
                                      // Tighter values can chase zero-velocity-at-pad and oscillate,
                                      // wasting fuel and bleeding VS toward hover.
LOCAL ENTRY_ALT_FLOOR    IS 3500.     // safety bail altitude
LOCAL ENTRY_MAX_SIN      IS 0.52.     // sin(31 deg) - lean cap; at this angle
                                      // net vertical accel is +6 m/s^2 up (fast
                                      // descent braking but no climb). Given
                                      // HS_EXIT=35 and typical HS=128, the
                                      // short burn (~13s) costs ~80 m/s of VS
                                      // - ship exits entry still at -300 to
                                      // -400 VS, "screaming in" as intended.
LOCAL ENTRY_MIN_LEAN_DEG IS 0.5.      // avoid noise at near-zero lean
LOCAL ENTRY_LEAN_DEG     IS 14.       // reference lean for boostback planning
                                      // (PEG entry computes lean dynamically)

// Aero (fin-driven, sign inverted from ENTRY)
LOCAL AERO_LEAN_DEG      IS 9.
LOCAL AERO_POS_K         IS 0.020.   // position gain (both axes)
LOCAL AERO_POS_CAP       IS 12.      // clamp on the current-position term
LOCAL AERO_PRED_K        IS 0.010.   // predicted-touchdown nudge; catches fast pad crossings
LOCAL AERO_PRED_CAP      IS 24.      // allow prediction to dominate current miss when needed
LOCAL AERO_PRED_MIN      IS 120.     // below this, avoid prediction twitching and use current miss
LOCAL IMPACT_CLR         IS 2.

// Landing burn (hoverslam: 3 engines then 1)
//
// VAB action-group bindings (matching the existing booster setup):
//   AG2 - fired once at script startup (line below the main setup
//         header). Transitions 6->3 engines. This is the flight/
//         landing configuration used through all descent phases.
//   AG3 - fired during the landing burn when 1 engine alone can
//         hold the required deceleration. Transitions 3->1 engine
//         for the final low-thrust touchdown.
//
// Consequence: at LANDING_BURN entry the booster already has 3
// engines enabled (from the AG2 fire at script startup). SHIP:MAXTHRUST
// therefore reflects 3-engine capability, so no further AG fire
// is needed until the 3->1 transition. The script reads live thrust
// values throughout, so it adapts to whatever thrust the AGs
// actually produce.
LOCAL LANDING_HANDOFF_CLR   IS 6000.  // AERO->LANDING trigger (m above pad)
LOCAL LANDING_IGNITE_MARGIN IS 60.    // extra cushion so the terminal brake is not saturated near the ground
LOCAL LANDING_SAFETY_FRAC   IS 0.97.  // reserve a little more braking authority than v4
LOCAL LANDING_SOLO_THR_OK   IS 0.85.  // switch to 1 eng if projected thr<=85%
LOCAL LANDING_SOLO_VS_MAX   IS 55.    // keep 3 engines until most vertical speed is arrested
LOCAL LANDING_GEAR_CLR      IS 250.   // deploy gear before the terminal brake gets busy
LOCAL LANDING_EXIT_CLR      IS 45.    // hand off only after the main brake is controlled, with room to settle
LOCAL LANDING_EXIT_VS       IS 6.     // do not enter TOUCHDOWN while still carrying a hard vertical rate
LOCAL LANDING_LEAN_CAP_DEG  IS 25.    // hard cap on lean during landing when far from the pad
LOCAL LANDING_FAR_LEAN_CAP_DEG IS 16.  // if not captured, avoid a sideways last-ditch pad chase
LOCAL LANDING_FAR_LOW_LEAN_CAP_DEG IS 8.
LOCAL LANDING_FAR_TERMINAL_LEAN_CAP_DEG IS 3.
LOCAL LANDING_FINAL_LEAN_CLR     IS 140. // preserve lateral authority until close to touchdown
LOCAL LANDING_FINAL_LEAN_CAP_DEG IS 8.   // enough late authority to brake overshoot without a kick
LOCAL LANDING_CAPTURE_MISS       IS 350. // if AERO already solved miss, landing burn must preserve it
LOCAL LANDING_CAPTURE_POS_K      IS 0.028. // base powered pull toward pad in precision capture mode
LOCAL LANDING_CAPTURE_POS_CAP    IS 2.2.   // cap position pull; altitude-adaptive below
LOCAL LANDING_CAPTURE_VEL_K      IS 0.90.  // damp closure without cancelling the pad pull too early
LOCAL LANDING_CAPTURE_VEL_CAP    IS 2.4.
LOCAL LANDING_CAPTURE_LEAN_CAP_DEG IS 12. // capture mode can use a little more lean while still high
LOCAL LANDING_CAPTURE_ZEM_VEL_K  IS 4.0. // terminal-velocity weight for precision ZEM/ZEV capture
LOCAL LANDING_CAPTURE_ZEM_TGO_MIN IS 4.0. // keep capture horizon realistic; avoids twitchy low-altitude chase
LOCAL LANDING_CAPTURE_ZEM_TGO_MAX IS 11.0.
LOCAL LANDING_FINAL_FREEZE_CLR   IS 25.  // only freeze in the last meters when already close
LOCAL LANDING_FINAL_FREEZE_MISS  IS 18.  // freeze only when the miss is already pad-sized
LOCAL LANDING_TGO_MIN       IS 2.5.
LOCAL LANDING_TGO_MAX       IS 14.
LOCAL LANDING_TARGET_FAST    IS 125.   // fast high-altitude descent without starving correction time
LOCAL LANDING_TARGET_MID     IS 105.   // keep near 100 m/s through mid altitude
LOCAL LANDING_TARGET_LOW     IS 65.    // begin meaningful braking before the last few hundred meters
LOCAL LANDING_TARGET_FINAL   IS 22.    // final pre-flare target; no long hover
LOCAL LANDING_TARGET_FLARE   IS 5.     // short final flare target, slow enough that TOUCHDOWN is not overloaded
LOCAL LANDING_GATE_CLR       IS 650.   // below this, force speed to be safe by the TOUCHDOWN handoff altitude
LOCAL LANDING_GATE_MARGIN    IS 8.     // minimum distance for terminal gate calculations

// Touchdown (hover-and-settle to pad)
//
// TOUCH_TARGET_VS is the main fuel-efficiency knob. A more negative
// target (faster descent) proportionally reduces time-to-ground,
// which proportionally reduces fuel burn since throttle during
// steady descent is near hover (~40%). -6 m/s is about 3x faster
// than -2 m/s and saves roughly 2/3 of TOUCHDOWN fuel.
LOCAL TOUCH_TARGET_VS     IS -4.5.  // terminal descent after hoverslam has already arrested the main speed
LOCAL TOUCH_TARGET_VS_LOW IS -2.0.  // last-meter flare only; avoid hover or bounce
LOCAL TOUCH_LOW_CLR       IS 6.     // final flare band
LOCAL TOUCH_VS_GAIN       IS 0.34.  // a little firmer now that LANDING hands off slower
LOCAL TOUCH_POS_K         IS 0.10.  // horizontal position pull
LOCAL TOUCH_POS_CAP       IS 4.     // cap on position term
LOCAL TOUCH_VEL_K         IS 0.55.  // horizontal velocity damping
LOCAL TOUCH_VEL_CAP       IS 4.     // cap on velocity term
LOCAL TOUCH_MAX_LEAN      IS 3.     // max lean during touchdown
LOCAL TOUCH_MAX_LEAN_LOW  IS 1.0.   // nearly vertical in the final meters
LOCAL TOUCH_FREEZE_CLR    IS 8.     // freeze only at the very end if already close
LOCAL TOUCH_FREEZE_MISS   IS 15.    // freeze lateral chase only when already pad-sized
LOCAL TOUCH_COMMIT_CLR    IS 3.0.   // below this, stop hovering and let legs settle
LOCAL TOUCH_COMMIT_VS     IS -2.0.  // commit when descending slower than this
LOCAL TOUCH_UPWARD_CUT_CLR IS 5.0.  // if rising this low, cut thrust immediately
LOCAL TOUCH_SOFT_CLR      IS 0.8.   // non-status fallback; was 3m and caused hop/re-drop
LOCAL TOUCH_SOFT_VS       IS 2.5.   // fallback only when truly near-ground and slow
LOCAL TOUCH_SOFT_HS       IS 4.0.   // fallback only when horizontal motion is settled

LOCAL PH_INIT            IS 0.
LOCAL PH_FLIP            IS 1.
LOCAL PH_BOOSTBACK       IS 2.
LOCAL PH_CORRECTIVE      IS 3.
LOCAL PH_COAST           IS 4.
LOCAL PH_ENTRY           IS 5.
LOCAL PH_AERO            IS 6.
LOCAL PH_LANDING_BURN    IS 7.
LOCAL PH_TOUCHDOWN       IS 8.
LOCAL PH_IMPACT          IS 9.
LOCAL PHASE_NAMES IS LIST("INIT","FLIP","BOOSTBACK","CORRECTIVE","COAST","ENTRY","AERO","LANDING","TOUCHDOWN","IMPACT").

// ------------------------------------------------------------
// State
// ------------------------------------------------------------
LOCAL phase              IS PH_INIT.
LOCAL padGeo             IS LATLNG(padLatP, padLngP).
LOCAL padAlt             IS padGeo:TERRAINHEIGHT.
LOCAL padG               IS SHIP:BODY:MU / ((SHIP:BODY:RADIUS + padAlt)^2).
LOCAL lastLogTime        IS -999.

LOCAL bbStartTime        IS 0.
LOCAL bbTargetToward     IS 0.
LOCAL bbMode             IS 0.
LOCAL bbRevBias          IS 0.
LOCAL bbRevHeading       IS 0.
LOCAL bbAimBrg           IS 0.
LOCAL corrStartTime      IS 0.
LOCAL corrMode           IS 0.
LOCAL coastFinsOut       IS FALSE.
LOCAL coastApoSeen       IS FALSE.
LOCAL entryStartTime     IS 0.
LOCAL aeroStartTime      IS 0.
LOCAL landingStartTime   IS 0.
LOCAL landingIgnited     IS FALSE.
LOCAL landingSoloMode    IS FALSE.
LOCAL landingGearOut     IS FALSE.
LOCAL touchStartTime     IS 0.
LOCAL touchCommitMode    IS FALSE.
LOCAL bestMissSeen       IS 99999.
LOCAL bestMissAlt        IS 0.

// Boostback target diagnostic values (computed inline during PH_INIT)
LOCAL bbDiagDbb          IS 0.
LOCAL bbDiagTcoast       IS 0.
LOCAL bbDiagAh           IS 0.
LOCAL bbDiagVcalc        IS 0.

// Cached nav state - refreshed once per loop
LOCAL navErrN            IS 0.
LOCAL navErrE            IS 0.
LOCAL navMiss            IS 0.
LOCAL navVelN            IS 0.
LOCAL navVelE            IS 0.
LOCAL navHs              IS 0.
LOCAL navToward          IS 0.
LOCAL navCross           IS 0.
LOCAL navPadBrg          IS 0.
LOCAL navAgl             IS 0.
LOCAL navClearance       IS 0.
LOCAL navSrfSpd          IS 0.
LOCAL navAlign           IS 0.
LOCAL dbgSteerN          IS 0.
LOCAL dbgSteerE          IS 0.

// Landing prediction fields used by guidance and logging.
LOCAL dbgTTouch          IS 0.
LOCAL dbgPredN           IS 0.
LOCAL dbgPredE           IS 0.
LOCAL dbgPredMiss        IS 0.
LOCAL dbgAimBiasN        IS 0.
LOCAL dbgAimBiasE        IS 0.

// ------------------------------------------------------------
// Small helpers
// ------------------------------------------------------------
FUNCTION Clamp {
    PARAMETER valueIn, lo, hi.
    IF valueIn < lo { RETURN lo. }
    IF valueIn > hi { RETURN hi. }
    RETURN valueIn.
}



FUNCTION padClearance {
    LOCAL clr IS SHIP:ALTITUDE - padAlt.
    IF clr < 0 { RETURN 0. }
    RETURN clr.
}


FUNCTION touchClearance {
    LOCAL padClr   IS padClearance().
    LOCAL radarClr IS ALT:RADAR.
    LOCAL outClr   IS padClr.

    // Keep this clearance path light because updateNav() runs in the main
    // control loop.
    IF radarClr > 0 AND radarClr < outClr + 200 {
        SET outClr TO MIN(outClr, radarClr).
    }
    RETURN outClr.
}


FUNCTION nsText {
    PARAMETER meterValue.
    IF meterValue >= 0 { RETURN "N:" + ROUND(meterValue,0). }
    RETURN "S:" + ROUND(ABS(meterValue),0).
}

FUNCTION ewText {
    PARAMETER meterValue.
    IF meterValue >= 0 { RETURN "E:" + ROUND(meterValue,0). }
    RETURN "W:" + ROUND(ABS(meterValue),0).
}

FUNCTION wrapBrg {
    PARAMETER brgIn.
    LOCAL bOut IS brgIn.
    UNTIL bOut >= 0 { SET bOut TO bOut + 360. }
    UNTIL bOut < 360 { SET bOut TO bOut - 360. }
    RETURN bOut.
}

FUNCTION velBearing {
    IF navHs < 0.1 { RETURN navPadBrg. }
    RETURN wrapBrg(ARCTAN2(navVelE, navVelN)).
}

FUNCTION brgError {
    PARAMETER fromBrg, toBrg.
    LOCAL dBrg IS toBrg - fromBrg.
    IF dBrg > 180 { SET dBrg TO dBrg - 360. }
    IF dBrg < -180 { SET dBrg TO dBrg + 360. }
    RETURN dBrg.
}

FUNCTION impactDetected {
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" { RETURN TRUE. }
    IF touchClearance() <= IMPACT_CLR { RETURN TRUE. }
    IF SHIP:ALTITUDE < 50 AND ABS(SHIP:VERTICALSPEED) < 3 AND navHs < 5 { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION landingTargetDown {
    PARAMETER clr.
    IF clr > 2500 { RETURN LANDING_TARGET_FAST. }
    IF clr > 900  { RETURN LANDING_TARGET_MID. }
    IF clr > 650  { RETURN LANDING_TARGET_LOW. }
    IF clr > 220  { RETURN LANDING_TARGET_FINAL. }
    RETURN LANDING_TARGET_FLARE.
}

FUNCTION fitLine {
    PARAMETER msg.
    LOCAL s IS "" + msg.

    IF s:LENGTH > DISP_W {
        SET s TO s:SUBSTRING(0, DISP_W).
    }

    RETURN s:PADRIGHT(DISP_W).
}

FUNCTION sayAt {
    PARAMETER rowNum, msg.
    IF rowNum >= 0 AND rowNum < DISP_H {
        PRINT fitLine(msg) AT (0, rowNum).
    }
}

FUNCTION showStatus {
    PARAMETER title, detail1 IS "", detail2 IS "".

    LOCAL dbgTxt IS "OFF".
    IF DEBUG_LOG { SET dbgTxt TO "ON". }

    sayAt(0, DISP_BAR).
    sayAt(1, "RTLS BULLSEYE  PH:" + title + "  DBG:" + dbgTxt).
    sayAt(2, "ALT:" + ROUND(SHIP:ALTITUDE/1000,2) + "km CLR:" + ROUND(navClearance,0) + "m VS:" + ROUND(SHIP:VERTICALSPEED,1)).
    sayAt(3, "HS:" + ROUND(navHs,1) + "m/s MISS:" + ROUND(navMiss,0) + "m BEST:" + ROUND(bestMissSeen,0) + "m").
    sayAt(4, "PAD " + nsText(navErrN) + " " + ewText(navErrE) + " BRG:" + ROUND(navPadBrg,1)).
    sayAt(5, "VEL toward:" + ROUND(navToward,0) + " cross:" + ROUND(navCross,0) + " spd:" + ROUND(navSrfSpd,0)).
    sayAt(6, "STEER N/E:" + ROUND(dbgSteerN,1) + "/" + ROUND(dbgSteerE,1) + "  GEAR:" + landingGearOut).
    sayAt(7, "D1 " + detail1).
    sayAt(8, "D2 " + detail2).
    sayAt(9, DISP_BAR).

    // Clear a few old rows from the previous compact display.
    sayAt(10, "").
    sayAt(11, "").
    sayAt(12, "").
}

// Cached nav update
// ------------------------------------------------------------
FUNCTION updateNav {
    LOCAL padPos  IS padGeo:ALTITUDEPOSITION(padAlt).
    LOCAL relVec  IS padPos - SHIP:POSITION.
    SET navErrN   TO VDOT(relVec, HEADING(0,0):FOREVECTOR).
    SET navErrE   TO VDOT(relVec, HEADING(90,0):FOREVECTOR).
    SET navMiss   TO SQRT(navErrN^2 + navErrE^2).
    SET navVelN   TO VDOT(SHIP:VELOCITY:SURFACE, HEADING(0,0):FOREVECTOR).
    SET navVelE   TO VDOT(SHIP:VELOCITY:SURFACE, HEADING(90,0):FOREVECTOR).
    SET navHs     TO SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2 - SHIP:VERTICALSPEED^2)).
    SET navPadBrg TO padGeo:HEADING.
    LOCAL terrainHeightNow IS SHIP:GEOPOSITION:TERRAINHEIGHT.
    IF terrainHeightNow < 0 { SET terrainHeightNow TO 0. }
    SET navAgl    TO SHIP:ALTITUDE - terrainHeightNow.
    IF navAgl < 0 { SET navAgl TO 0. }
    SET navClearance TO touchClearance().
    SET navSrfSpd TO SHIP:VELOCITY:SURFACE:MAG.

    // Diagnostic prediction only: where the pad-relative horizontal
    // error would be at touchdown if the current horizontal velocity
    // continued for a simple clearance / vertical-speed time estimate.
    // This is intentionally not used for guidance decisions yet.
    IF SHIP:VERTICALSPEED < -0.1 {
        SET dbgTTouch TO Clamp(navClearance / MAX(0.1, ABS(SHIP:VERTICALSPEED)), 0, 999).
    } ELSE {
        SET dbgTTouch TO 0.
    }
    SET dbgPredN TO navErrN - navVelN * dbgTTouch.
    SET dbgPredE TO navErrE - navVelE * dbgTTouch.
    SET dbgPredMiss TO SQRT(dbgPredN^2 + dbgPredE^2).

    IF navMiss > 0.1 {
        SET navToward TO (navVelN*navErrN + navVelE*navErrE) / navMiss.
        SET navCross  TO (navVelE*navErrN - navVelN*navErrE) / navMiss.
    } ELSE {
        SET navToward TO 0.
        SET navCross  TO 0.
    }

    IF navHs > 0.1 {
        SET navAlign TO Clamp(navToward / navHs, -1, 1).
    } ELSE {
        SET navAlign TO 0.
    }
}

// ------------------------------------------------------------
// Logging
// ------------------------------------------------------------
FUNCTION logLine {
    PARAMETER msg.
    IF NOT DEBUG_LOG { RETURN. }
    LOG "T+" + ROUND(TIME:SECONDS,1)
      + " | " + PHASE_NAMES[phase]
      + " | " + ROUND(SHIP:ALTITUDE/1000,2) + "km"
      + " | VS:" + ROUND(SHIP:VERTICALSPEED,1)
      + " | HS:" + ROUND(navHs,1)
      + " | Act:" + ROUND(navMiss,0)
      + " | Thr:" + ROUND(THROTTLE*100,0)
      + " | pAct:" + ROUND(dbgPredMiss,0)
      + " | tTouch:" + ROUND(dbgTTouch,1)
      + " | vNE:" + ROUND(navVelN,1) + "/" + ROUND(navVelE,1)
      + " | predNE:" + ROUND(dbgPredN,0) + "/" + ROUND(dbgPredE,0)
      + " | biasNE:" + ROUND(dbgAimBiasN,1) + "/" + ROUND(dbgAimBiasE,1)
      + " | " + msg TO LOG_PATH.
}

FUNCTION logEvent {
    PARAMETER msg.
    logLine("*** " + msg + " ***").
}

FUNCTION logPeriodic {
    PARAMETER msg IS "".
    IF NOT DEBUG_LOG { RETURN. }
    IF TIME:SECONDS - lastLogTime >= LOG_DT {
        logLine(msg).
        SET lastLogTime TO TIME:SECONDS.
    }
}

// ------------------------------------------------------------
// AG / fins
// ------------------------------------------------------------
FUNCTION activateAG {
    PARAMETER agNum.
    IF agNum = 1 { AG1 ON. }
    ELSE IF agNum = 2 { AG2 ON. }
    ELSE IF agNum = 3 { AG3 ON. }
    ELSE IF agNum = 4 { AG4 ON. }
}

FUNCTION setFinAuthority {
    PARAMETER pct.
    FOR partObj IN SHIP:PARTS {
        IF partObj:HASMODULE("ModuleControlSurface") {
            LOCAL moduleObj IS partObj:GETMODULE("ModuleControlSurface").
            IF moduleObj:HASFIELD("authority limiter") {
                moduleObj:SETFIELD("authority limiter", pct).
            }
        }
    }
}

// ------------------------------------------------------------
// Direction helpers
// ------------------------------------------------------------
FUNCTION rollRefVec {
    PARAMETER lookVec.
    IF ABS(VDOT(lookVec:NORMALIZED, HEADING(0,0):FOREVECTOR)) < 0.92 { RETURN HEADING(0,0):FOREVECTOR. }
    RETURN HEADING(90,0):FOREVECTOR.
}

// Engine-first descent attitude. On this booster, FOREVECTOR is the
// engine/thrust direction, so facing up -> thrust up (decelerates
// descent). Leaning nose toward (corrN, corrE) puts a horizontal
// component into thrust in that same direction.
FUNCTION tailDownDir {
    PARAMETER corrNorth, corrEast, leanDeg.
    LOCAL horizMag IS SQRT(corrNorth^2 + corrEast^2).
    LOCAL noseVec IS UP:FOREVECTOR.

    IF horizMag > 0.01 AND leanDeg > 0 {
        LOCAL horizVec IS HEADING(0,0):FOREVECTOR*corrNorth + HEADING(90,0):FOREVECTOR*corrEast.
        SET noseVec TO UP:FOREVECTOR*COS(leanDeg) + horizVec:NORMALIZED*SIN(leanDeg).
    }

    RETURN LOOKDIRUP(noseVec:NORMALIZED, rollRefVec(noseVec)).
}

// ------------------------------------------------------------
// Debug vectors
// ------------------------------------------------------------
// CLEARVECDRAWS().
// LOCAL vdPad IS VECDRAW(
//     { RETURN padGeo:ALTITUDEPOSITION(padAlt + 1500). },
//     { RETURN padGeo:ALTITUDEPOSITION(padAlt) - padGeo:ALTITUDEPOSITION(padAlt + 1500). },
//     GREEN, "LZ", 1.0, TRUE, 0.45, TRUE, FALSE).

// LOCAL vdVel IS VECDRAW(
//     { RETURN SHIP:POSITION. },
//     { RETURN (HEADING(0,0):FOREVECTOR*navVelN + HEADING(90,0):FOREVECTOR*navVelE) * 18. },
//     RED, "VEL", 1.0, TRUE, 0.40, TRUE, FALSE).

// LOCAL vdPadErr IS VECDRAW(
//     { RETURN SHIP:POSITION. },
//     { RETURN (HEADING(0,0):FOREVECTOR*navErrN + HEADING(90,0):FOREVECTOR*navErrE). },
//     CYAN, "PAD", 1.0, TRUE, 0.38, TRUE, FALSE).

// LOCAL vdSteer IS VECDRAW(
//     { RETURN SHIP:POSITION. },
//     { RETURN (HEADING(0,0):FOREVECTOR*dbgSteerN + HEADING(90,0):FOREVECTOR*dbgSteerE) * 20. },
//     YELLOW, "STEER", 1.0, TRUE, 0.40, TRUE, FALSE).

// ------------------------------------------------------------
// Main setup
// ------------------------------------------------------------
SET TERMINAL:WIDTH TO DISP_W.
SET TERMINAL:HEIGHT TO DISP_H.
CLEARSCREEN.
RCS ON.
activateAG(2).
GEAR OFF.
IF DEBUG_LOG {
    IF EXISTS(LOG_PATH) { DELETEPATH(LOG_PATH). }
    LOG "RTLS - Pad: " + padLatP + " / " + padLngP + " TerrainAlt:" + ROUND(padAlt,2) TO LOG_PATH.
    LOG "T+sec | Phase | Alt km | VS | HS | Act m | Thr% | pAct | tTouch | vN/vE | predN/E | biasN/E | Msg" TO LOG_PATH.
    LOG "----------------------------------------------------------------" TO LOG_PATH.
}
PRINT fitLine("Loaded RTLS - debug/display combined") AT (0, 14).
updateNav().
IF DEBUG_LOG { logEvent("SCRIPT START terrainAlt:" + ROUND(padAlt,2) + " miss:" + ROUND(navMiss,0)).}

// Steering/throttle are locked once here. The phase loop below only
// updates these command variables; it does not re-lock controls.
LOCAL rtlsThrottleCmd IS 0.
LOCAL rtlsSteeringCmd IS HEADING(navPadBrg, FLIP_PITCH).
LOCK THROTTLE TO rtlsThrottleCmd.
LOCK STEERING TO rtlsSteeringCmd.

UNTIL FALSE {
    updateNav().
    SET dbgSteerN TO 0.
    SET dbgSteerE TO 0.

    // Track best miss seen so we can see in the log how close we got
    IF navMiss < bestMissSeen {
        SET bestMissSeen TO navMiss.
        SET bestMissAlt TO SHIP:ALTITUDE.
    }

    // ------------------------------------------------------------
    // Dynamic boostback target computed once during PH_INIT
    //
    // Solve for padward velocity at boostback end such that, after a
    // ballistic coast to entry trigger altitude, the entry burn can
    // close the remaining horizontal distance while nulling HS within
    // its decel budget.
    //
    // CRITICAL: dBB must be the miss at BOOSTBACK END, not at INIT.
    // Between INIT and boostback end the ship keeps drifting away
    // because it has to align (flip) and then kill its away-velocity
    // (reverse burn). For Falcon-class boosters that drift is on the
    // order of 3-6 km and was the silent killer of the previous build.
    //
    // dBB_proj = navMiss
    //          + awayNow * tFlipEst                 (drift during flip)
    //          + awayNow^2 / (2 * aFull)            (drift during reverse)
    //
    // Coast time is computed from the PROJECTED altitude and VS at
    // boostback end, not the current ones, because flip+boostback adds
    // significant altitude (the thrust is mostly horizontal, so VS
    // is near-ballistic during that window).
    //
    //   dBB_proj = vCoast * tCoast + vCoast^2 / (2 * aH)
    //   => vCoast = sqrt(aH^2 * tCoast^2 + 2*aH*dBB_proj) - aH*tCoast
    //
    // BB_TOWARD_MARGIN is added so we over-boost slightly (entry handles
    // overshoot better than undershoot).
    // ------------------------------------------------------------
    // --------------------------------------------------------
    IF phase = PH_INIT {
        LOCAL dBBnow   IS navMiss.
        LOCAL awayNow  IS MAX(0, -navToward).
        LOCAL vsNow    IS SHIP:VERTICALSPEED.
        LOCAL altNow   IS SHIP:ALTITUDE.
        LOCAL gLocal   IS SHIP:BODY:MU / ((SHIP:BODY:RADIUS + altNow)^2).

        // Full-thrust horizontal decel during REV (thrust is near-
        // retrograde in the horizontal plane, so use cos(FLIP_PITCH)).
        LOCAL aFull IS 15.
        IF SHIP:MASS > 0.1 AND SHIP:AVAILABLETHRUST > 0.1 {
            SET aFull TO MAX(5, SHIP:AVAILABLETHRUST / SHIP:MASS * COS(FLIP_PITCH)).
        }

        // Time budget from INIT to end of boostback
        LOCAL tFlipEst    IS 8.                      // alignment duration
        LOCAL tReverseEst IS awayNow / aFull.        // full-thrust away-kill
        LOCAL tSetEst     IS 5.                      // SET/FINE cleanup overhead
        LOCAL tPreCoast   IS tFlipEst + tReverseEst + tSetEst.

        // Horizontal drift during flip + reverse burn
        LOCAL driftFlip IS awayNow * tFlipEst.
        LOCAL driftRev  IS awayNow * awayNow / (2 * aFull).
        LOCAL dBBproj   IS dBBnow + driftFlip + driftRev.

        // Projected altitude and VS at boostback end (vertical is near-
        // ballistic during flip+boostback since thrust is near-horizontal)
        LOCAL vsProj  IS vsNow - gLocal * tPreCoast.
        LOCAL altProj IS altNow + vsNow * tPreCoast - 0.5 * gLocal * tPreCoast * tPreCoast.

        // Ballistic coast time from boostback end to entry trigger altitude
        LOCAL altDelta  IS altProj - ENTRY_TRIGGER_ALT.
        LOCAL tCoastEst IS 60.
        IF vsProj > 0 {
            // Ascending after boostback - arc, fall to entry alt
            LOCAL discT IS vsProj*vsProj + 2*gLocal*altDelta.
            IF discT < 0 { SET discT TO 0. }
            SET tCoastEst TO (vsProj + SQRT(discT)) / gLocal.
        } ELSE {
            // Already descending
            LOCAL absVs IS ABS(vsProj).
            IF altDelta <= 0 {
                SET tCoastEst TO 4.
            } ELSE {
                LOCAL discT IS absVs*absVs + 2*gLocal*altDelta.
                IF discT < 0 { SET discT TO 0. }
                SET tCoastEst TO (-absVs + SQRT(discT)) / gLocal.
            }
        }
        SET tCoastEst TO Clamp(tCoastEst, 12, 180).

        // Horizontal decel available during entry burn
        LOCAL aHest IS 5.0.
        IF SHIP:MASS > 0.1 AND SHIP:AVAILABLETHRUST > 0.1 {
            LOCAL tAcc IS SHIP:AVAILABLETHRUST / SHIP:MASS.
            SET aHest TO MAX(3.0, tAcc * SIN(ENTRY_LEAN_DEG) * BB_AH_FRAC).
        }

        // Solve quadratic using PROJECTED dBB
        LOCAL discV      IS aHest*aHest*tCoastEst*tCoastEst + 2*aHest*dBBproj.
        LOCAL vCoastCalc IS SQRT(discV) - aHest*tCoastEst.
        LOCAL vCoastTgt  IS vCoastCalc + BB_TOWARD_MARGIN.

        // Diagnostics - log shows PROJECTED dBB now, not INIT miss
        SET bbDiagDbb    TO dBBproj.
        SET bbDiagTcoast TO tCoastEst.
        SET bbDiagAh     TO aHest.
        SET bbDiagVcalc  TO vCoastCalc.

        SET bbTargetToward TO Clamp(vCoastTgt, BB_TOWARD_MIN, BB_TOWARD_MAX).
        SET phase TO PH_FLIP.
        IF DEBUG_LOG { logEvent(
            "INIT->FLIP miss:" + ROUND(navMiss,0)
          + " hs:" + ROUND(navHs,0)
          + " dBB:" + ROUND(bbDiagDbb,0)
          + " tCoast:" + ROUND(bbDiagTcoast,1)
          + " aH:" + ROUND(bbDiagAh,2)
          + " vCalc:" + ROUND(bbDiagVcalc,1)
          + " tgtToward:" + ROUND(bbTargetToward,1)
        ).}
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_FLIP {
        SET rtlsSteeringCmd TO HEADING(navPadBrg, FLIP_PITCH).
        SET rtlsThrottleCmd TO 0.
        LOCAL flipErr IS VANG(SHIP:FACING:FOREVECTOR, HEADING(navPadBrg, FLIP_PITCH):FOREVECTOR).
        showStatus("FLIP", "Aligning for boostback", "pitch err:" + ROUND(flipErr,1) + " deg  pad brg:" + ROUND(navPadBrg,1) + "  tgt toward:" + ROUND(bbTargetToward,0) + " m/s").
        IF DEBUG_LOG { logPeriodic("flip err:" + ROUND(flipErr,1) + " brg:" + ROUND(navPadBrg,1)).}

        IF flipErr < FLIP_TOL {
            SET bbStartTime   TO TIME:SECONDS.
            SET bbMode        TO 0.
            SET bbRevBias     TO 0.
            IF ABS(navCross) >= 4 {
                IF navCross > 0 {
                    SET bbRevBias TO -MIN(BB_HEADING_MAX, 1.5 + ABS(navCross)*0.08).
                } ELSE {
                    SET bbRevBias TO MIN(BB_HEADING_MAX, 1.5 + ABS(navCross)*0.08).
                }
            }
            SET bbRevHeading TO wrapBrg(navPadBrg + bbRevBias).
            SET bbAimBrg     TO bbRevHeading.
            SET phase TO PH_BOOSTBACK.
            IF DEBUG_LOG { logEvent("FLIP->BOOSTBACK brg:" + ROUND(navPadBrg,1) + " tgtToward:" + ROUND(bbTargetToward,0) + " revBias:" + ROUND(bbRevBias,1)).}
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_BOOSTBACK {

        // Stage-based boostback:
        //   0 = REV   hard reverse burn on locked heading
        //   1 = SET   padward burn with modest trim
        //   2 = FINE  low-throttle cleanup
        LOCAL crossAbs IS ABS(navCross).
        LOCAL elapsed  IS TIME:SECONDS - bbStartTime.
        LOCAL lineBrg  IS navPadBrg.
        LOCAL velBrg   IS velBearing().
        LOCAL velErr   IS brgError(velBrg, lineBrg).
        LOCAL headBias IS 0.
        LOCAL desiredAim IS bbAimBrg.
        LOCAL aimBrg   IS bbAimBrg.
        LOCAL thrCmd   IS 0.0.
        LOCAL modeName IS "REV".

        IF bbMode = 0 AND navToward >= BB_REV_FLOOR {
            SET bbMode TO 1.
            SET bbAimBrg TO lineBrg.
        }
        IF bbMode = 1 AND ABS(navErrE) <= 6000 AND navToward >= bbTargetToward - 8 AND crossAbs <= 8 AND ABS(velErr) <= 10 {
            SET bbMode TO 2.
        }
        IF bbMode = 2 AND (crossAbs > 12 OR ABS(velErr) > 12 OR ABS(navErrE) > 7000) {
            SET bbMode TO 1.
        }

        IF bbMode = 0 {
            SET modeName TO "REV".
            SET desiredAim TO bbRevHeading.
            SET bbAimBrg TO desiredAim.
            SET aimBrg TO bbAimBrg.

            IF navToward < -80 {
                SET thrCmd TO 1.0.
            } ELSE IF navToward < -20 {
                SET thrCmd TO 0.65.
            } ELSE {
                SET thrCmd TO 0.36.
            }
        }
        ELSE IF bbMode = 1 {
            SET modeName TO "SET".
            SET headBias TO Clamp((-navCross * 0.10) + Clamp((-velErr * 0.05), -2, 2), -6, 6).
            SET desiredAim TO wrapBrg(lineBrg + headBias).
            SET bbAimBrg TO wrapBrg(bbAimBrg + Clamp(brgError(bbAimBrg, desiredAim), -1.2, 1.2)).
            SET aimBrg TO bbAimBrg.

            IF navToward < bbTargetToward - 60 {
                SET thrCmd TO 1.0.
            } ELSE IF navToward < bbTargetToward - 24 {
                SET thrCmd TO 0.65.
            } ELSE IF navToward < bbTargetToward - 10 {
                SET thrCmd TO 0.22.
            } ELSE IF navToward < bbTargetToward - BB_TOWARD_BAND {
                SET thrCmd TO 0.08.
            } ELSE {
                SET thrCmd TO 0.0.
            }
        }
        ELSE {
            SET modeName TO "FINE".
            SET headBias TO Clamp((-navCross * 0.10) + Clamp((-navErrE / 7000) * 1.0, -1.5, 1.5), -4, 4).
            SET desiredAim TO wrapBrg(lineBrg + headBias).
            SET bbAimBrg TO wrapBrg(bbAimBrg + Clamp(brgError(bbAimBrg, desiredAim), -1.5, 1.5)).
            SET aimBrg TO bbAimBrg.

            IF ABS(velErr) > 4 OR crossAbs > 4 {
                SET thrCmd TO 0.06.
            } ELSE IF navToward < bbTargetToward - 4 {
                SET thrCmd TO 0.06.
            } ELSE {
                SET thrCmd TO 0.0.
            }
        }

        SET rtlsSteeringCmd TO HEADING(aimBrg, FLIP_PITCH).
        SET rtlsThrottleCmd TO thrCmd.

        showStatus("BOOSTBACK", "mode:" + modeName + "  aim:" + ROUND(aimBrg,1) + " deg  throttle:" + ROUND(thrCmd*100,0) + "%", "toward:" + ROUND(navToward,0) + "  target:" + ROUND(bbTargetToward,0) + "  cross:" + ROUND(navCross,0) + "  velErr:" + ROUND(velErr,1) + "  " + ewText(navErrE)).

        IF DEBUG_LOG { logPeriodic(
            "boost " + modeName
          + " act:" + ROUND(navMiss,0)
          + " hs:" + ROUND(navHs,0)
          + " toward:" + ROUND(navToward,0)
          + " tgt:" + ROUND(bbTargetToward,0)
          + " cross:" + ROUND(navCross,0)
          + " velErr:" + ROUND(velErr,1)
          + " aim:" + ROUND(aimBrg,1)
          + " " + nsText(navErrN)
          + " " + ewText(navErrE)
        ).}

        LOCAL bbExitReason IS "".
        IF bbMode >= 1
           AND thrCmd <= 0.001
           AND navToward >= bbTargetToward - BB_TOWARD_BAND {
            SET bbExitReason TO "throttle-zero handoff mode:" + modeName + " toward:" + ROUND(navToward,0) + " tgt:" + ROUND(bbTargetToward,0) + " cross:" + ROUND(navCross,1) + " velErr:" + ROUND(velErr,1).
        }
        ELSE IF elapsed > BB_MAX_TIME {
            SET bbExitReason TO "safety timeout mode:" + modeName + " toward:" + ROUND(navToward,0) + " cross:" + ROUND(navCross,1).
        }

        IF bbExitReason <> "" {
            SET rtlsThrottleCmd TO 0.
            SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
            SET corrStartTime TO TIME:SECONDS.
            SET corrMode TO 0.
            SET bbAimBrg TO navPadBrg.
            SET phase TO PH_CORRECTIVE.
            IF DEBUG_LOG { logEvent("BOOSTBACK->CORRECTIVE " + bbExitReason).}
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_CORRECTIVE {

        // 0 = TURN90   zero thrust, turn 90 deg from pad line
        // 1 = ALIGN90  tiny thrust, sync velocity onto pad vector
        LOCAL corrElapsed IS TIME:SECONDS - corrStartTime.
        LOCAL lineBrgC IS navPadBrg.
        LOCAL velBrgC IS velBearing().
        LOCAL velErrC IS brgError(velBrgC, lineBrgC).
        LOCAL crossAbsC IS ABS(navCross).
        LOCAL aimBrgC IS bbAimBrg.
        LOCAL thrCorr IS 0.
        LOCAL corrName IS "TURN90".
        LOCAL aimErrC IS 0.
        LOCAL turnSign IS 1.
        IF velErrC < 0 { SET turnSign TO -1. }

        IF corrMode = 0 {
            SET corrName TO "TURN90".
            SET aimBrgC TO wrapBrg(lineBrgC + (turnSign * 90)).
            SET bbAimBrg TO aimBrgC.
            SET aimErrC TO VANG(SHIP:FACING:FOREVECTOR, HEADING(aimBrgC, FLIP_PITCH):FOREVECTOR).
            SET thrCorr TO 0.
            IF aimErrC <= CORR_TURN_ERR {
                SET corrMode TO 1.
            }
        }
        ELSE {
            SET corrName TO "ALIGN90".
            SET aimBrgC TO wrapBrg(lineBrgC + (turnSign * 90)).
            SET bbAimBrg TO aimBrgC.
            SET aimErrC TO VANG(SHIP:FACING:FOREVECTOR, HEADING(aimBrgC, FLIP_PITCH):FOREVECTOR).
            IF aimErrC > CORR_TURN_ERR {
                SET thrCorr TO 0.
            } ELSE {
                SET thrCorr TO CORR_ALIGN_THR.
            }
        }

        SET rtlsSteeringCmd TO HEADING(aimBrgC, FLIP_PITCH).
        SET rtlsThrottleCmd TO thrCorr.

        showStatus("CORRECTIVE", "mode:" + corrName + "  aim:" + ROUND(aimBrgC,1) + " deg  throttle:" + ROUND(thrCorr*100,0) + "%", "toward:" + ROUND(navToward,0) + "  cross:" + ROUND(navCross,0) + "  velErr:" + ROUND(velErrC,1) + "  aimErr:" + ROUND(aimErrC,1) + "  " + ewText(navErrE)).
        IF DEBUG_LOG { logPeriodic("corrective " + corrName + " act:" + ROUND(navMiss,0) + " cross:" + ROUND(navCross,0) + " velErr:" + ROUND(velErrC,1) + " aimErr:" + ROUND(aimErrC,1)).}

        IF corrMode = 1
           AND corrElapsed >= CORR_ALIGN_MIN_T
           AND ABS(velErrC) <= CORR_ALIGN_VELERR
           AND crossAbsC <= CORR_ALIGN_CROSS {
            SET rtlsThrottleCmd TO 0.
            SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
            SET phase TO PH_COAST.
            IF DEBUG_LOG { logEvent("CORRECTIVE->COAST align solved velErr:" + ROUND(velErrC,1)).}
        }
        ELSE IF corrElapsed > CORR_MAX_TIME {
            SET rtlsThrottleCmd TO 0.
            SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
            SET phase TO PH_COAST.
            IF DEBUG_LOG { logEvent("CORRECTIVE->COAST timeout velErr:" + ROUND(velErrC,1)).}
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_COAST {
        SET rtlsThrottleCmd TO 0.
        // Engine-first coast with gentle velocity-damping trim
        LOCAL coastTgo  IS Clamp(navClearance / MAX(170, ABS(SHIP:VERTICALSPEED)), 10, 28).
        LOCAL coastDesVN IS Clamp((navErrN / MAX(14, coastTgo * 2.2)) - navVelN * 1.25, -8, 8).
        LOCAL coastDesVE IS Clamp((navErrE / MAX(14, coastTgo * 2.2)) - navVelE * 1.25, -10, 10).
        SET dbgSteerN TO coastDesVN.
        SET dbgSteerE TO coastDesVE.
        LOCAL coastAimVec IS HEADING(0,0):FOREVECTOR*(navErrN + coastDesVN * 90)
                          + HEADING(90,0):FOREVECTOR*(navErrE + coastDesVE * 90)
                          + (-UP:FOREVECTOR)*MAX(1, navClearance).
        IF coastAimVec:MAG < 0.01 {
            SET coastAimVec TO (-UP:FOREVECTOR).
        }
        SET rtlsSteeringCmd TO LOOKDIRUP((-coastAimVec):NORMALIZED, rollRefVec((-coastAimVec))).
        RCS ON.

        IF NOT coastFinsOut AND (SHIP:ALTITUDE < COAST_FIN_ALT OR SHIP:VERTICALSPEED <= 0) {
            activateAG(1).
            setFinAuthority(22).
            SET coastFinsOut TO TRUE.
            IF DEBUG_LOG { logEvent("Fins deployed auth:22").}
        }

        IF SHIP:VERTICALSPEED <= 0 { SET coastApoSeen TO TRUE. }

        showStatus("COAST", "Engine-first to LZ + trim", "fins:" + coastFinsOut + "  apo seen:" + coastApoSeen + "  pad brg:" + ROUND(navPadBrg,1)).
        IF DEBUG_LOG { logPeriodic("coast act:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0) + " desV:" + ROUND(coastDesVN,0) + "/" + ROUND(coastDesVE,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).}

        IF coastApoSeen AND SHIP:ALTITUDE < ENTRY_TRIGGER_ALT AND SHIP:VERTICALSPEED < -220 {
            SET entryStartTime TO TIME:SECONDS.
            SET phase TO PH_ENTRY.
            IF DEBUG_LOG { logEvent("COAST->ENTRY alt:" + ROUND(SHIP:ALTITUDE,0) + " spd:" + ROUND(navSrfSpd,0) + " act:" + ROUND(navMiss,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).}
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_ENTRY {
        // ZEM/ZEV pinpoint guidance. Entry exists ONLY to scrub HS
        // and fine-tune approach - NOT to reverse descent. The ship
        // should still be "screaming in" when AERO takes over.
        //
        // Required horizontal acceleration to arrive at pad with
        // zero horizontal velocity:
        //
        //   a_req = (6 / tgo^2) * navErr  -  (8 / tgo) * navVel
        //
        // This is the optimal LQR solution for arriving at a fixed
        // target position with specified terminal velocity (zero).
        // The first term pulls toward the pad. The second brakes
        // velocity. Their 6:8 balance is tuned so the commanded
        // acceleration is consistent throughout the burn - no hover
        // or terminal overshoot is required if tgo is chosen right.
        //
        // Why ZEM/ZEV beats pure retrograde: retrograde only brakes
        // the velocity vector. If velocity is not aligned with the
        // direction to the pad (e.g. the ship has some cross-track
        // drift), retrograde does nothing to close cross-track error.
        // ZEM/ZEV naturally biases the lean toward the pad, closing
        // both along-track and cross-track error simultaneously.
        //
        // tgo is chosen as the longer of:
        //   - miss / HS      (time to traverse remaining distance)
        //   - HS / aHmax     (time to null HS at max horizontal decel)
        // This is because neither physical limit can be violated.
        //
        // Lean direction = direction of a_req (steering toward the
        // required acceleration vector).
        // Lean magnitude  = asin(|a_req| / (T/m)), capped at ENTRY_MAX_SIN
        // so net vertical is never sufficient to reverse descent.
        //
        // Throttle is FULL while HS > ENTRY_HS_EXIT; zero after.

        LOCAL entryElapsed IS TIME:SECONDS - entryStartTime.
        LOCAL clrEntry     IS padClearance().
        LOCAL vsEntryNow   IS SHIP:VERTICALSPEED.
        LOCAL tAccEntry    IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
        LOCAL aHmax        IS MAX(1, tAccEntry * ENTRY_MAX_SIN).

        // tgo selection - longer of kinematic and braking time
        LOCAL tgoMiss  IS 15.
        IF navHs > 10 { SET tgoMiss TO navMiss / MAX(20, navHs). }
        LOCAL tgoBrake IS navHs / aHmax.
        LOCAL tgoEntry IS Clamp(MAX(tgoMiss, tgoBrake), 6, 20).

        // ZEM/ZEV required acceleration
        LOCAL tgo2   IS tgoEntry * tgoEntry.
        LOCAL reqAN  IS (6 / tgo2) * navErrN - (8 / tgoEntry) * navVelN.
        LOCAL reqAE  IS (6 / tgo2) * navErrE - (8 / tgoEntry) * navVelE.
        LOCAL reqAmag IS SQRT(reqAN * reqAN + reqAE * reqAE).

        // Required sine of lean angle (at full throttle)
        LOCAL reqSin IS 0.
        IF tAccEntry > 0.1 AND reqAmag > 0.01 {
            SET reqSin TO Clamp(reqAmag / tAccEntry, 0, ENTRY_MAX_SIN).
        }
        LOCAL leanEff IS 0.
        IF reqSin > 0.01 {
            SET leanEff TO ARCSIN(reqSin).
        }
        IF leanEff < ENTRY_MIN_LEAN_DEG { SET leanEff TO 0. }

        // Steering direction: toward required acceleration vector
        LOCAL corrN IS reqAN.
        LOCAL corrE IS reqAE.
        SET dbgSteerN TO corrN.
        SET dbgSteerE TO corrE.

        // Throttle: full while HS is above exit target, or while we
        // still need meaningful corrective acceleration
        LOCAL thrEntry IS 1.0.
        IF navHs < ENTRY_HS_EXIT {
            SET thrEntry TO 0.
        }
        // If the ship is close and barely moving, there's nothing to do
        IF reqAmag < 1.0 AND navHs < 15 {
            SET thrEntry TO 0.
        }

        // --------------------------------------------------------
        // ANTI-CLIMB SAFETY NET
        //
        // With ENTRY_MAX_SIN=0.52 (31 deg cap), net vertical accel
        // at full thrust is ~+6 m/s^2 up - the ship brakes descent
        // but does not reverse it. These clamps should rarely fire.
        // They exist as a safety net for degenerate geometries.
        // --------------------------------------------------------
        IF vsEntryNow >= 0 {
            SET thrEntry TO 0.
        }
        ELSE IF vsEntryNow > -30 {
            SET thrEntry TO MIN(thrEntry, 0.05).
        }
        ELSE IF vsEntryNow > -100 {
            SET thrEntry TO MIN(thrEntry, 0.5).
        }

        // Fuel-out guard
        IF SHIP:AVAILABLETHRUST <= 0.01 {
            SET thrEntry TO 0.
        }

        SET rtlsSteeringCmd TO tailDownDir(corrN, corrE, leanEff).
        SET rtlsThrottleCmd TO thrEntry.
        RCS ON.
        IF coastFinsOut { setFinAuthority(26). }

        showStatus(
            "ENTRY",
            "tgo:" + ROUND(tgoEntry,1) + "  reqA N/E:" + ROUND(reqAN,1) + "/" + ROUND(reqAE,1) + "  lean:" + ROUND(leanEff,1) + "  thr:" + ROUND(thrEntry*100,0) + "%",
            "miss:" + ROUND(navMiss,0) + "  hs:" + ROUND(navHs,1) + "  vs:" + ROUND(vsEntryNow,0) + "  best:" + ROUND(bestMissSeen,0) + "  elapsed:" + ROUND(entryElapsed,1)
        ).
        IF DEBUG_LOG { logPeriodic(
            "entry alt:" + ROUND(SHIP:ALTITUDE,0)
          + " vs:" + ROUND(vsEntryNow,0)
          + " act:" + ROUND(navMiss,0)
          + " hs:" + ROUND(navHs,1)
          + " thr:" + ROUND(thrEntry*100,0)
          + " lean:" + ROUND(leanEff,1)
          + " tgo:" + ROUND(tgoEntry,1)
          + " reqAN:" + ROUND(reqAN,1)
          + " reqAE:" + ROUND(reqAE,1)
          + " corrN:" + ROUND(corrN,1)
          + " corrE:" + ROUND(corrE,1)
          + " " + nsText(navErrN) + " " + ewText(navErrE)
        ).}

        // Exit conditions. Primary exit is HS braked below ENTRY_HS_EXIT;
        // everything else is a safety/fallback.
        LOCAL exitReason IS "".
        IF navHs < ENTRY_HS_EXIT AND entryElapsed > ENTRY_MIN_TIME {
            SET exitReason TO "HS braked miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,1).
        }
        ELSE IF navMiss < ENTRY_MISS_EXIT AND dbgPredMiss < ENTRY_CENTER_PRED_EXIT AND entryElapsed > ENTRY_MIN_TIME {
            SET exitReason TO "centered miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,1)
                          + " pAct:" + ROUND(dbgPredMiss,0).
        }
        ELSE IF SHIP:ALTITUDE - padAlt < ENTRY_ALT_FLOOR {
            SET exitReason TO "altitude floor miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,1).
        }
        ELSE IF SHIP:AVAILABLETHRUST <= 0.01 AND entryElapsed > ENTRY_MIN_TIME {
            SET exitReason TO "fuel out miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,1).
        }
        ELSE IF entryElapsed > ENTRY_MAX_TIME {
            SET exitReason TO "RUNAWAY GUARD max-time miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,1).
        }

        IF exitReason <> "" {
            SET rtlsThrottleCmd TO 0.
            SET aeroStartTime TO TIME:SECONDS.
            SET phase TO PH_AERO.
            IF DEBUG_LOG { logEvent("ENTRY->AERO " + exitReason + " alt:" + ROUND(SHIP:ALTITUDE,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).}
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_AERO {
        // Aerodynamic-only control (no engine).
        //
        // IMPORTANT: sign convention is INVERTED from ENTRY. During
        // ENTRY the primary force is thrust, which comes out opposite
        // to the ship's engine direction - so commanding lean toward
        // (corrN, corrE) means thrust goes that way, and setting
        // corr = -navVel gives retrograde thrust. That works for
        // ENTRY because thrust overwhelms any aero lift.
        //
        // During AERO there is no thrust. The booster falls engines-
        // first with grid fins at the top. When we command a body
        // tilt, the grid fins generate a reaction force pushing the
        // ship in the OPPOSITE direction from the tilt (classic tail-
        // first fin stabilizer behavior: to rotate the nose one way,
        // the fins push the top the other way). So aero force is
        // -tilt direction.
        //
        // To BRAKE velocity with aero: tilt in the SAME direction as
        // velocity, so the aero force opposes velocity (= brakes).
        // To MOVE toward pad with aero: tilt AWAY from the pad, so
        // the aero force pulls toward the pad.
        //
        // Previous build had both signs wrong and was actively adding
        // drift instead of removing it: ~1km of miss growth over the
        // 72-second AERO fall.

        LOCAL corrN_A IS navVelN.
        LOCAL corrE_A IS navVelE.

        // Position pull toward the pad. Use predicted touchdown error when
        // it is clearly large. The 120-degree logs showed a dangerous case:
        // current miss crossed near the pad, but pAct was still kilometers
        // away, so AERO thought it was solved and allowed a huge overshoot.
        // For small predicted miss, fall back to the gentler current-position
        // nudge that produced the accurate 60-degree landings.
        IF dbgPredMiss > AERO_PRED_MIN {
            LOCAL nudgeN IS Clamp(-dbgPredN * AERO_PRED_K, -AERO_PRED_CAP, AERO_PRED_CAP).
            LOCAL nudgeE IS Clamp(-dbgPredE * AERO_PRED_K, -AERO_PRED_CAP, AERO_PRED_CAP).
            SET corrN_A TO corrN_A + nudgeN.
            SET corrE_A TO corrE_A + nudgeE.
        } ELSE IF navMiss > 40 {
            LOCAL nudgeN IS Clamp(-navErrN * AERO_POS_K, -AERO_POS_CAP, AERO_POS_CAP).
            LOCAL nudgeE IS Clamp(-navErrE * AERO_POS_K, -AERO_POS_CAP, AERO_POS_CAP).
            SET corrN_A TO corrN_A + nudgeN.
            SET corrE_A TO corrE_A + nudgeE.
        }

        SET dbgSteerN TO corrN_A.
        SET dbgSteerE TO corrE_A.

        SET rtlsSteeringCmd TO tailDownDir(corrN_A, corrE_A, AERO_LEAN_DEG).
        SET rtlsThrottleCmd TO 0.
        RCS ON.
        IF coastFinsOut { setFinAuthority(40). }

        // Drop legs low so the impact point is well-defined even
        // though we are crashing.
        IF padClearance() < 120 {
            GEAR ON.
        }

        showStatus(
            "AERO",
            "fin-reaction + pad pull  lean:" + ROUND(AERO_LEAN_DEG,1),
            "miss:" + ROUND(navMiss,0) + "  best:" + ROUND(bestMissSeen,0) + " @ " + ROUND(bestMissAlt,0) + "m  hs:" + ROUND(navHs,1)
        ).
        IF DEBUG_LOG { logPeriodic(
            "aero act:" + ROUND(navMiss,0)
          + " hs:" + ROUND(navHs,1)
          + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
          + " clr:" + ROUND(padClearance(),0)
          + " corrN:" + ROUND(corrN_A,1)
          + " corrE:" + ROUND(corrE_A,1)
          + " best:" + ROUND(bestMissSeen,0)
          + " " + nsText(navErrN) + " " + ewText(navErrE)
        ).}

        // Hand off to landing burn at altitude. Impact detection is
        // kept as a fallback in case landing never engages for some
        // reason (fuel starvation, etc.)
        IF padClearance() < LANDING_HANDOFF_CLR {
            SET landingStartTime TO TIME:SECONDS.
            SET phase TO PH_LANDING_BURN.
            IF DEBUG_LOG { logEvent(
                "AERO->LANDING act:" + ROUND(navMiss,0)
              + " hs:" + ROUND(navHs,1)
              + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
              + " clr:" + ROUND(padClearance(),0)
              + " " + nsText(navErrN) + " " + ewText(navErrE)
            ).}
        }
        ELSE IF impactDetected() {
            SET phase TO PH_IMPACT.
            IF DEBUG_LOG { logEvent(
                "AERO->IMPACT act:" + ROUND(navMiss,0)
              + " hs:" + ROUND(navHs,1)
              + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
              + " best:" + ROUND(bestMissSeen,0) + "@" + ROUND(bestMissAlt,0)
              + " " + nsText(navErrN) + " " + ewText(navErrE)
            ).}
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_LANDING_BURN {
        // Hoverslam landing burn, 3 engines at ignition, transitions
        // to 1 engine for final descent.
        //
        // Phase structure:
        //   1. Pre-ignition: remain in 3-engine mode from startup (AG2), fall
        //      engines-first, compute stopping distance live. Ignite
        //      when stop_dist + margin >= clearance.
        //   2. Ignited (3 engines): throttle controls vertical decel,
        //      lean gives horizontal correction from ZEM/ZEV. Switch
        //      to 1 engine (AG3) when 1 engine alone could hold the
        //      required decel at a reasonable throttle setting.
        //   3. Ignited (1 engine): continue through to TOUCHDOWN exit.
        //
        // Math:
        //   tm          = SHIP:AVAILABLETHRUST / mass (max accel magnitude)
        //   vsDown      = -VS (positive when falling)
        //   aVertReq    = vsDown^2 / (2*clr) + g   (kinematic vertical decel
        //                 needed to stop at ground, including gravity)
        //   (reqAN,reqAE) = ZEM/ZEV horizontal acceleration request
        //   aTotal      = sqrt(aVertReq^2 + |reqA_horiz|^2)
        //   throttle    = aTotal / tm
        //   lean        = arctan(|reqA_horiz| / aVertReq)
        //
        // If aTotal > tm we're doomed (ignition was too late). The
        // SAFETY_FRAC margin on ignition planning prevents this in
        // normal conditions.

        LOCAL vsLand   IS SHIP:VERTICALSPEED.
        LOCAL vsDown   IS MAX(0, -vsLand).
        LOCAL clr      IS touchClearance().
        LOCAL elapsedLand IS TIME:SECONDS - landingStartTime.

        // ---- Pre-ignition: wait for trigger ----
        IF NOT landingIgnited {
            // Booster is already in 3-engine mode (AG2 at script start).
            // Use available thrust and a nonzero target downspeed so ignition
            // does not start a fuel-heavy hover high above the pad.
            LOCAL tmMax IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
            IF tmMax < 0.1 { SET tmMax TO SHIP:MAXTHRUST / MAX(0.1, SHIP:MASS). }
            LOCAL aNet  IS MAX(1, tmMax * LANDING_SAFETY_FRAC - padG).
            LOCAL targetDownIgn IS landingTargetDown(clr).

            // Kinematic distance to the current hoverslam target downspeed.
            LOCAL stopDist IS MAX(0, (vsDown * vsDown - targetDownIgn * targetDownIgn) / (2 * aNet)).
            LOCAL ignAlt   IS stopDist + LANDING_IGNITE_MARGIN.

            // Pre-ignition steering: keep AERO-style retrograde attitude
            // so the engines are pointed opposite to velocity (nose up-ish),
            // but keep the AERO pad nudge alive. The log showed AERO had the
            // booster within ~50 m, then LANDING pre-ignition stopped correcting
            // that residual error for the next couple kilometers.
            LOCAL corrN_pre IS navVelN.
            LOCAL corrE_pre IS navVelE.
            IF navMiss > 10 {
                SET corrN_pre TO corrN_pre + Clamp(-navErrN * AERO_POS_K, -AERO_POS_CAP, AERO_POS_CAP).
                SET corrE_pre TO corrE_pre + Clamp(-navErrE * AERO_POS_K, -AERO_POS_CAP, AERO_POS_CAP).
            }
            SET rtlsSteeringCmd TO tailDownDir(corrN_pre, corrE_pre, AERO_LEAN_DEG).
            SET rtlsThrottleCmd TO 0.

            // Ignite when the stopping distance catches up to clearance
            IF clr <= ignAlt {
                SET landingIgnited TO TRUE.
                IF DEBUG_LOG { logEvent(
                    "LANDING IGNITE clr:" + ROUND(clr,0)
                  + " stopDist:" + ROUND(stopDist,0)
                  + " tmMax:" + ROUND(tmMax,1)
                  + " vs:" + ROUND(vsLand,1)
                  + " miss:" + ROUND(navMiss,0)
                ).}
            }

            showStatus(
                "LANDING",
                "pre-ignition  tmMax:" + ROUND(tmMax,1) + "  stopDist:" + ROUND(stopDist,0) + "m  ignAlt:" + ROUND(ignAlt,0) + "m",
                "clr:" + ROUND(clr,0) + "  vs:" + ROUND(vsLand,1) + "  hs:" + ROUND(navHs,1) + "  miss:" + ROUND(navMiss,0)
            ).
            IF DEBUG_LOG { logPeriodic(
                "land-pre clr:" + ROUND(clr,0)
              + " vs:" + ROUND(vsLand,1)
              + " hs:" + ROUND(navHs,1)
              + " act:" + ROUND(navMiss,0)
              + " tmMax:" + ROUND(tmMax,1)
              + " stopDist:" + ROUND(stopDist,0)
              + " ignAlt:" + ROUND(ignAlt,0)
              + " " + nsText(navErrN) + " " + ewText(navErrE)
            ).}
        }
        // ---- Ignited: active burn with ZEM/ZEV horizontal guidance ----
        ELSE {
            LOCAL tm IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
            IF tm < 0.1 { SET tm TO 0.1. }

            // Exit to TOUCHDOWN before issuing another landing-burn steering
            // command. The old order allowed one final high-lean frame at
            // single-digit clearance, which is exactly what kicked the booster
            // sideways in the latest log.
            IF clr <= LANDING_EXIT_CLR AND vsLand < -0.5 AND vsDown <= LANDING_EXIT_VS {
                LOCAL targetVsSettle IS TOUCH_TARGET_VS.
                IF clr < TOUCH_LOW_CLR { SET targetVsSettle TO TOUCH_TARGET_VS_LOW. }
                LOCAL aSettle IS padG + (targetVsSettle - vsLand) * TOUCH_VS_GAIN.
                IF aSettle < 0 { SET aSettle TO 0. }
                LOCAL thrSettle IS Clamp(aSettle / tm, 0, 1).

                SET dbgSteerN TO 0.
                SET dbgSteerE TO 0.
                SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
                SET rtlsThrottleCmd TO thrSettle.
                RCS ON.

                SET touchStartTime TO TIME:SECONDS.
                SET touchCommitMode TO FALSE.
                SET phase TO PH_TOUCHDOWN.
                IF DEBUG_LOG { logEvent(
                    "LANDING->TOUCHDOWN settle clr:" + ROUND(clr,0)
                  + " vs:" + ROUND(vsLand,1)
                  + " hs:" + ROUND(navHs,1)
                  + " miss:" + ROUND(navMiss,0)
                  + " thr:" + ROUND(thrSettle*100,0)
                ).}
            }
            ELSE {
                // Required vertical acceleration to follow a hoverslam descent
                // profile, not to stop/hover high above the pad.
                LOCAL clrFloor IS MAX(8, clr).
                LOCAL targetDown IS landingTargetDown(clrFloor).
                LOCAL profileAccel IS (vsDown * vsDown - targetDown * targetDown) / (2 * clrFloor).
                LOCAL aVertReq IS padG + profileAccel.
                IF aVertReq < 0 { SET aVertReq TO 0. }

                // Terminal gate: below LANDING_GATE_CLR, stop planning to be slow
                // at the ground. Be slow by the TOUCHDOWN handoff altitude. This
                // catches the case where we pass 40m still doing ~-25 m/s and
                // bounce before TOUCHDOWN has room to settle.
                IF clr < LANDING_GATE_CLR AND vsDown > LANDING_EXIT_VS {
                    LOCAL gateDist IS MAX(LANDING_GATE_MARGIN, clr - LANDING_EXIT_CLR).
                    LOCAL gateAccel IS (vsDown * vsDown - LANDING_EXIT_VS * LANDING_EXIT_VS) / (2 * gateDist).
                    LOCAL aGateReq IS padG + gateAccel.
                    IF aGateReq > aVertReq { SET aVertReq TO aGateReq. }
                }

                // Vertical tgo estimate: time to ground at current/profile average downspeed.
                LOCAL tgoLand IS Clamp(
                    2 * clrFloor / MAX(10, vsDown + targetDown),
                    LANDING_TGO_MIN,
                    LANDING_TGO_MAX
                ).

                // Horizontal guidance split:
                //   * Far miss: use the ZEM/ZEV controller to recover.
                //   * Captured miss: AERO has the pad nearly solved. Use an altitude-
                //     tapered precision pull: stronger high, velocity-damped low.
                LOCAL tgoHoriz IS tgoLand.
                LOCAL reqAN IS 0.
                LOCAL reqAE IS 0.
                LOCAL captureLanding IS FALSE.
                LOCAL captureLeanCap IS LANDING_CAPTURE_LEAN_CAP_DEG.

                IF navMiss <= LANDING_CAPTURE_MISS AND dbgPredMiss <= LANDING_CAPTURE_MISS * 1.75 {
                    SET captureLanding TO TRUE.
                    SET tgoHoriz TO Clamp(tgoLand, 3, 10).

                    // Precision capture: the v8 log showed LANDING entering at
                    // about 88m miss and then only bleeding that down to about
                    // 48m because the capture controller had almost zero lean
                    // for the last kilometer. Use stronger position pull while
                    // high, then taper it out before touchdown so we do not
                    // build lateral speed on the legs.
                    LOCAL capAccelCap IS LANDING_CAPTURE_POS_CAP.
                    LOCAL capVelK IS LANDING_CAPTURE_VEL_K.
                    LOCAL capVelCap IS LANDING_CAPTURE_VEL_CAP.
                    IF clr > 600 {
                        SET capAccelCap TO 3.0.
                        SET capVelK TO 0.75.
                        SET capVelCap TO 2.2.
                        SET captureLeanCap TO 12.
                    } ELSE IF clr > 200 {
                        SET capAccelCap TO 2.4.
                        SET capVelK TO 0.90.
                        SET capVelCap TO 2.2.
                        SET captureLeanCap TO 10.
                    } ELSE IF clr > 100 {
                        SET capAccelCap TO 1.4.
                        SET capVelK TO 1.15.
                        SET capVelCap TO 2.4.
                        SET captureLeanCap TO 5.
                    } ELSE {
                        SET capAccelCap TO 0.7.
                        SET capVelK TO 1.45.
                        SET capVelCap TO 2.8.
                        SET captureLeanCap TO 3.
                    }

                    // Use lateral ZEM/ZEV while there is still room to move the
                    // touchdown point. The v10 logs showed current miss shrinking
                    // but predicted touchdown miss staying around 15-20m west;
                    // pure position/velocity capture was damping away the last
                    // useful correction. Below ~100m, stop chasing prediction and
                    // mostly damp lateral velocity so the legs do not skid.
                    LOCAL tZem IS Clamp(tgoLand, LANDING_CAPTURE_ZEM_TGO_MIN, LANDING_CAPTURE_ZEM_TGO_MAX).
                    IF clr > 100 {
                        LOCAL tZem2 IS tZem * tZem.
                        SET reqAN TO (6 / tZem2) * navErrN - (LANDING_CAPTURE_ZEM_VEL_K / tZem) * navVelN.
                        SET reqAE TO (6 / tZem2) * navErrE - (LANDING_CAPTURE_ZEM_VEL_K / tZem) * navVelE.
                    } ELSE {
                        SET reqAN TO Clamp(navErrN * 0.010, -0.4, 0.4)
                                  + Clamp(-navVelN * capVelK, -capVelCap, capVelCap).
                        SET reqAE TO Clamp(navErrE * 0.010, -0.4, 0.4)
                                  + Clamp(-navVelE * capVelK, -capVelCap, capVelCap).
                    }

                    LOCAL reqCapMag IS SQRT(reqAN * reqAN + reqAE * reqAE).
                    IF reqCapMag > capAccelCap AND reqCapMag > 0.01 {
                        LOCAL capScale IS capAccelCap / reqCapMag.
                        SET reqAN TO reqAN * capScale.
                        SET reqAE TO reqAE * capScale.
                    }
                } ELSE {
                    // ZEM/ZEV should not wait until the last 2 km. Use a slightly
                    // longer horizon than the vertical flare while high, then tighten
                    // it near the pad. This brakes overshoot earlier instead of
                    // chasing back over the pad at low altitude.
                    IF clr > 1800 {
                        SET tgoHoriz TO Clamp(dbgPredMiss / MAX(35, navHs), 10, LANDING_TGO_MAX).
                    } ELSE IF clr > 600 {
                        SET tgoHoriz TO Clamp(dbgPredMiss / MAX(25, navHs), 7, 12).
                    } ELSE {
                        SET tgoHoriz TO Clamp(tgoLand, 4, 9).
                    }

                    // Far miss recovery uses predicted touchdown miss, not the
                    // instantaneous miss. This prevents the 120-degree case where
                    // the vehicle crossed near the pad high up, then tried to fight
                    // back aggressively during the landing burn and touched down
                    // sideways. The factor of 2 is a constant-acceleration ZEM
                    // solution to remove the predicted miss over tgoHoriz.
                    LOCAL tgo2 IS tgoHoriz * tgoHoriz.
                    SET reqAN TO (2 / tgo2) * dbgPredN.
                    SET reqAE TO (2 / tgo2) * dbgPredE.
                }

                LOCAL reqAHmag IS SQRT(reqAN * reqAN + reqAE * reqAE).

                // Once we are close enough in the final meters, stop chasing
                // sub-pad error. Touchdown accuracy is already solved here;
                // extra lateral authority mostly creates horizontal speed.
                IF clr < LANDING_FINAL_FREEZE_CLR AND navMiss < LANDING_FINAL_FREEZE_MISS {
                    SET reqAN TO 0.
                    SET reqAE TO 0.
                    SET reqAHmag TO 0.
                }

                // Cap horizontal request so we can still satisfy vertical.
                // Reserve enough thrust budget for vertical + a small margin.
                LOCAL thrBudget IS tm * 0.98.
                LOCAL aHmax IS 0.
                IF thrBudget > aVertReq {
                    SET aHmax TO SQRT(thrBudget * thrBudget - aVertReq * aVertReq).
                }
                IF reqAHmag > aHmax AND reqAHmag > 0.01 {
                    LOCAL scaleH IS aHmax / reqAHmag.
                    SET reqAN TO reqAN * scaleH.
                    SET reqAE TO reqAE * scaleH.
                    SET reqAHmag TO aHmax.
                }

                // Taper lean as clearance runs out. This is applied to the
                // acceleration request, not just the attitude, so clipping lean
                // does not accidentally increase vertical thrust and bounce.
                LOCAL landingLeanCap IS LANDING_LEAN_CAP_DEG.
                IF captureLanding {
                    SET landingLeanCap TO MIN(landingLeanCap, captureLeanCap).
                } ELSE {
                    // If the pad is not captured by powered landing, do not let
                    // the controller spend the last kilometer trying to side-slip
                    // back to the target. That is exactly what caused the 120-degree
                    // sideways landing. Land safely and let AERO/ENTRY solve earlier.
                    SET landingLeanCap TO MIN(landingLeanCap, LANDING_FAR_LEAN_CAP_DEG).
                    IF clr < 800 { SET landingLeanCap TO MIN(landingLeanCap, LANDING_FAR_LOW_LEAN_CAP_DEG). }
                    IF clr < 140 { SET landingLeanCap TO MIN(landingLeanCap, LANDING_FAR_TERMINAL_LEAN_CAP_DEG). }
                }
                IF clr < LANDING_FINAL_LEAN_CLR {
                    SET landingLeanCap TO MIN(landingLeanCap, LANDING_FINAL_LEAN_CAP_DEG).
                }
                IF aVertReq > 0.1 AND landingLeanCap < 89 {
                    LOCAL aHLeanCap IS aVertReq * TAN(landingLeanCap).
                    IF reqAHmag > aHLeanCap AND reqAHmag > 0.01 {
                        LOCAL scaleLeanH IS aHLeanCap / reqAHmag.
                        SET reqAN TO reqAN * scaleLeanH.
                        SET reqAE TO reqAE * scaleLeanH.
                        SET reqAHmag TO aHLeanCap.
                    }
                }

                // Total commanded acceleration magnitude and direction
                LOCAL aTotal IS SQRT(aVertReq * aVertReq + reqAHmag * reqAHmag).
                LOCAL thrLand IS Clamp(aTotal / tm, 0, 1).

                // Lean angle from vertical (ARCCOS of vertical / total)
                LOCAL leanLand IS 0.
                IF aTotal > 0.1 {
                    SET leanLand TO ARCCOS(Clamp(aVertReq / aTotal, -1, 1)).
                }
                IF leanLand > landingLeanCap { SET leanLand TO landingLeanCap. }

                // Steering direction: toward required horizontal accel
                LOCAL corrN IS reqAN.
                LOCAL corrE IS reqAE.
                IF reqAHmag < 0.01 {
                    // No meaningful horizontal component - keep pointing up
                    SET corrN TO 0.
                    SET corrE TO 0.
                    SET leanLand TO 0.
                }
                SET dbgSteerN TO corrN.
                SET dbgSteerE TO corrE.

                SET rtlsSteeringCmd TO tailDownDir(corrN, corrE, leanLand).
                SET rtlsThrottleCmd TO thrLand.
                RCS ON.

                // 3-engine -> 1-engine transition. If one engine alone could
                // hold the required vertical decel at a reasonable throttle,
                // drop to one. We estimate 1-engine capability by scaling
                // the current measured capability down by the engine count
                // ratio. The current mode is three engines; AG3 switches to one engine.
                IF NOT landingSoloMode AND elapsedLand > 1.0 AND vsDown < LANDING_SOLO_VS_MAX {
                    LOCAL tmSolo IS tm / 3.   // estimate solo capability from current 3-engine thrust
                    LOCAL thrSoloProj IS 1.0.
                    IF tmSolo > 0.1 {
                        SET thrSoloProj TO aTotal / tmSolo.
                    }
                    IF thrSoloProj <= LANDING_SOLO_THR_OK {
                        activateAG(3).
                        SET landingSoloMode TO TRUE.
                        IF DEBUG_LOG { logEvent(
                            "LANDING solo-engine clr:" + ROUND(clr,0)
                          + " vs:" + ROUND(vsLand,1)
                          + " thrProj:" + ROUND(thrSoloProj*100,0) + "%"
                        ).}
                    }
                }

                // Deploy gear below a threshold
                IF NOT landingGearOut AND clr < LANDING_GEAR_CLR {
                    GEAR ON.
                    SET landingGearOut TO TRUE.
                    IF DEBUG_LOG { logEvent("Gear deployed clr:" + ROUND(clr,0)).}
                }

                showStatus(
                    "LANDING",
                    "thr:" + ROUND(thrLand*100,0) + "%  lean:" + ROUND(leanLand,1) + "  tgoV/H:" + ROUND(tgoLand,1) + "/" + ROUND(tgoHoriz,1) + "  solo:" + landingSoloMode,
                    "clr:" + ROUND(clr,0) + "  vs:" + ROUND(vsLand,1) + "  hs:" + ROUND(navHs,1) + "  miss:" + ROUND(navMiss,0)
                ).
                IF DEBUG_LOG { logPeriodic(
                    "land clr:" + ROUND(clr,0)
                  + " vs:" + ROUND(vsLand,1)
                  + " hs:" + ROUND(navHs,1)
                  + " act:" + ROUND(navMiss,0)
                  + " thr:" + ROUND(thrLand*100,0)
                  + " lean:" + ROUND(leanLand,1)
                  + " aV:" + ROUND(aVertReq,1)
                  + " aH:" + ROUND(reqAHmag,1)
                  + " tgoH:" + ROUND(tgoHoriz,1)
                  + " tm:" + ROUND(tm,1)
                  + " cap:" + captureLanding
                  + " solo:" + landingSoloMode
                  + " " + nsText(navErrN) + " " + ewText(navErrE)
                ).}

                // Safety: if we somehow got on the ground in landing burn
                IF impactDetected() {
                    SET phase TO PH_IMPACT.
                    IF DEBUG_LOG { logEvent(
                        "LANDING->IMPACT (unexpected) clr:" + ROUND(clr,0)
                      + " vs:" + ROUND(vsLand,1)
                      + " miss:" + ROUND(navMiss,0)
                    ).}
                }
                // Fuel-out fallback
                ELSE IF SHIP:AVAILABLETHRUST <= 0.01 {
                    SET phase TO PH_IMPACT.
                    IF DEBUG_LOG { logEvent(
                        "LANDING->IMPACT FUEL-OUT clr:" + ROUND(clr,0)
                      + " vs:" + ROUND(vsLand,1)
                      + " miss:" + ROUND(navMiss,0)
                    ).}
                }
            }
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_TOUCHDOWN {
        // Hover-and-settle. Hold target VS while high enough to control it,
        // then commit to contact. The no-hop rule is: once we are in the
        // last few meters and slow/rising, do not hover. Cut thrust and let
        // the legs settle instead of lifting off again.

        LOCAL vsTouch IS SHIP:VERTICALSPEED.
        LOCAL clr     IS touchClearance().
        LOCAL tm      IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
        IF tm < 0.1 { SET tm TO 0.1. }

        LOCAL touchdownDone IS FALSE.

        // Landed detection first, before any new throttle command. This avoids
        // leaving one more nonzero-throttle frame after contact.
        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
            SET rtlsThrottleCmd TO 0.
            SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
            RCS OFF.
            SAS OFF.
            BRAKES ON.
            SET phase TO PH_IMPACT.
            SET touchdownDone TO TRUE.
            IF DEBUG_LOG { logEvent(
                "LANDED status:" + SHIP:STATUS
              + " miss:" + ROUND(navMiss,0)
              + " hs:" + ROUND(navHs,1)
              + " vs:" + ROUND(vsTouch,2)
            ).}
        }
        // Non-status fallback: much tighter than the old clr<3m check. The
        // previous fallback could shut down while the booster was still in a
        // small post-contact hop. Wait until bottom clearance is essentially
        // gone, then shut down immediately.
        ELSE IF clr < TOUCH_SOFT_CLR AND ABS(vsTouch) < TOUCH_SOFT_VS AND navHs < TOUCH_SOFT_HS {
            SET rtlsThrottleCmd TO 0.
            SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
            RCS OFF.
            SAS OFF.
            BRAKES ON.
            SET phase TO PH_IMPACT.
            SET touchdownDone TO TRUE.
            IF DEBUG_LOG { logEvent(
                "LANDED (soft-nohop) miss:" + ROUND(navMiss,0)
              + " hs:" + ROUND(navHs,1)
              + " vs:" + ROUND(vsTouch,2)
              + " clr:" + ROUND(clr,1)
            ).}
        }

        IF NOT touchdownDone {
            // Latch commit mode once we are close enough and slow enough. Also
            // latch if we ever see upward vertical speed close to the ground;
            // that is the signature of the little hop in the latest log.
            IF clr < TOUCH_COMMIT_CLR AND vsTouch > TOUCH_COMMIT_VS {
                SET touchCommitMode TO TRUE.
            }
            IF clr < TOUCH_UPWARD_CUT_CLR AND vsTouch > 0 {
                SET touchCommitMode TO TRUE.
            }

            // Target descent rate - slower when very close. In commit mode this
            // is diagnostic only because throttle is forced to zero.
            LOCAL targetVs IS TOUCH_TARGET_VS.
            IF clr < TOUCH_LOW_CLR { SET targetVs TO TOUCH_TARGET_VS_LOW. }

            // Required vertical accel = gravity + correction to reach target VS
            LOCAL vsErr    IS targetVs - vsTouch.   // +ve means need more thrust (rising VS)
            LOCAL aVertReq IS padG + vsErr * TOUCH_VS_GAIN.
            IF aVertReq < 0 { SET aVertReq TO 0. }

            LOCAL thrTouch IS Clamp(aVertReq / tm, 0, 1).
            IF touchCommitMode { SET thrTouch TO 0. }

            // Horizontal correction: velocity damp + position pull. Once we are
            // close to the pad and close to the ground, freeze lateral chase; in
            // commit mode freeze it unconditionally.
            LOCAL corrN IS 0.
            LOCAL corrE IS 0.
            LOCAL freezeTouchHoriz IS FALSE.
            IF clr < TOUCH_FREEZE_CLR AND navMiss < TOUCH_FREEZE_MISS {
                SET freezeTouchHoriz TO TRUE.
            }
            IF touchCommitMode { SET freezeTouchHoriz TO TRUE. }
            IF NOT freezeTouchHoriz {
                SET corrN TO Clamp(-navVelN * TOUCH_VEL_K, -TOUCH_VEL_CAP, TOUCH_VEL_CAP)
                          + Clamp( navErrN * TOUCH_POS_K, -TOUCH_POS_CAP, TOUCH_POS_CAP).
                SET corrE TO Clamp(-navVelE * TOUCH_VEL_K, -TOUCH_VEL_CAP, TOUCH_VEL_CAP)
                          + Clamp( navErrE * TOUCH_POS_K, -TOUCH_POS_CAP, TOUCH_POS_CAP).
            }

            // Lean cap very tight near ground. Lean is proportional to request,
            // not a full-cap on/off step.
            LOCAL leanCap IS TOUCH_MAX_LEAN.
            IF clr < TOUCH_LOW_CLR { SET leanCap TO TOUCH_MAX_LEAN_LOW. }

            LOCAL corrMag IS SQRT(corrN * corrN + corrE * corrE).
            LOCAL leanTouch IS 0.
            IF corrMag > 0.1 { SET leanTouch TO Clamp(corrMag, 0, leanCap). }
            IF touchCommitMode { SET leanTouch TO 0. }

            SET dbgSteerN TO corrN.
            SET dbgSteerE TO corrE.

            SET rtlsSteeringCmd TO tailDownDir(corrN, corrE, leanTouch).
            SET rtlsThrottleCmd TO thrTouch.
            IF touchCommitMode {
                RCS OFF.
            } ELSE {
                RCS ON.
            }

            showStatus(
                "TOUCHDOWN",
                "thr:" + ROUND(thrTouch*100,0) + "%  tgtVs:" + ROUND(targetVs,1) + "  lean:" + ROUND(leanTouch,1) + "  commit:" + touchCommitMode,
                "clr:" + ROUND(clr,1) + "  vs:" + ROUND(vsTouch,2) + "  hs:" + ROUND(navHs,1) + "  miss:" + ROUND(navMiss,0)
            ).
            IF DEBUG_LOG { logPeriodic(
                "touch clr:" + ROUND(clr,1)
              + " vs:" + ROUND(vsTouch,2)
              + " hs:" + ROUND(navHs,1)
              + " act:" + ROUND(navMiss,0)
              + " thr:" + ROUND(thrTouch*100,0)
              + " lean:" + ROUND(leanTouch,1)
              + " tgtVs:" + ROUND(targetVs,1)
              + " commit:" + touchCommitMode
              + " " + nsText(navErrN) + " " + ewText(navErrE)
            ).}

            // Fuel-out fallback
            IF SHIP:AVAILABLETHRUST <= 0.01 {
                SET rtlsThrottleCmd TO 0.
                RCS OFF.
                SET phase TO PH_IMPACT.
                IF DEBUG_LOG { logEvent(
                    "TOUCHDOWN->IMPACT FUEL-OUT clr:" + ROUND(clr,1)
                  + " vs:" + ROUND(vsTouch,2)
                  + " miss:" + ROUND(navMiss,0)
                ).}
            }
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_IMPACT {
        // Full shutdown: engines, RCS, SAS, steering, throttle.
        SET rtlsThrottleCmd TO 0.
        SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
        RCS OFF.
        SAS OFF.
        BRAKES ON.
        showStatus(
            "IMPACT",
            "shutdown complete",
            "status:" + SHIP:STATUS + "  miss:" + ROUND(navMiss,0) + "  best:" + ROUND(bestMissSeen,0) + "  hs:" + ROUND(navHs,1) + "  vs:" + ROUND(SHIP:VERTICALSPEED,1)
        ).
        BREAK.
    }

    WAIT 0.01.
}

SET rtlsThrottleCmd TO 0.
SET rtlsSteeringCmd TO tailDownDir(0, 0, 0).
WAIT 0.01.
UNLOCK STEERING.
UNLOCK THROTTLE.
RCS OFF.
IF DEBUG_LOG { logEvent("SCRIPT END final miss:" + ROUND(navMiss,0) + " best miss seen:" + ROUND(bestMissSeen,0) + " @ " + ROUND(bestMissAlt,0) + "m").}