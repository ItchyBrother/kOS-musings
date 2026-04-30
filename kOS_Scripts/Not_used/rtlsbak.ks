// ============================================================
// falcon9_rtls_bullseye.ks  (no terminal burn variant)
//
// Proof-of-geometry RTLS. There is no hoverslam, no landing burn,
// no flare. The entry burn is the ONLY precision phase and must
// deliver the booster to near-zero horizontal speed over the pad
// before handing off to a pure retrograde AERO drop that terminates
// in ground contact (expected impact velocity ~60-80 m/s vertical).
//
// Phases:
//   INIT -> FLIP -> BOOSTBACK -> CORRECTIVE -> COAST -> ENTRY -> AERO -> IMPACT
//
// What changed vs the previous flat_geometry build:
//   * Boostback target toward velocity is now DYNAMIC: at INIT we
//     solve the quadratic
//         dBB = vCoast * tCoast + vCoast^2 / (2 * aH)
//     for vCoast using current navMiss, a ballistic estimate of
//     coast time to entry trigger altitude, and the entry burn's
//     horizontal decel budget from current thrust/mass. A small
//     over-boost margin is added because entry handles overshoot
//     better than undershoot. Previous fixed value of 117 (and
//     my earlier bad suggestion of 85) are gone.
//   * Entry burn no longer exits on MAX_TIME at altitude. It exits
//     only when (navMiss < ENTRY_MISS_EXIT AND navHs < ENTRY_HS_EXIT)
//     OR the safety altitude floor is reached. MAX_TIME is kept only
//     as a hard runaway guard.
//   * Entry guidance uses err/tgo ZEM-style feedforward without the
//     previous -navVel * k damping term that was fighting the
//     position closure term.
//   * AERO is now pure retrograde on N/S (corr = -navVel) with a
//     small east-only position nudge, matching the earlier build
//     that produced 36-80 m accuracy.
//   * Dead TERM_* / landingThrottle / rawLandingThrottle code path
//     and the undefined aeroKillHS / bestMiss block in AERO have
//     been removed.
//
// ============================================================

@LAZYGLOBAL OFF.

PARAMETER padLatP IS -0.0972.
PARAMETER padLngP IS -74.5577.

// ------------------------------------------------------------
// Constants
// ------------------------------------------------------------
//LOCAL LOG_PATH           IS "0:/rtls_bullseye_log.txt".
//LOCAL LOG_DT             IS 1.5.

// Boostback
LOCAL FLIP_PITCH         IS 6.
LOCAL FLIP_TOL           IS 4.
LOCAL BB_TOWARD_BAND     IS 5.
LOCAL BB_HEADING_MAX     IS 6.
LOCAL BB_MAX_TIME        IS 96.
LOCAL BB_REV_FLOOR       IS 10.
// Dynamic boostback target bounds + over-boost margin
LOCAL BB_TOWARD_MIN      IS 55.      // hard floor (very close pads)
LOCAL BB_TOWARD_MAX      IS 160.     // hard ceiling (very far pads)
LOCAL BB_TOWARD_MARGIN   IS 8.       // over-boost m/s beyond analytic solution
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
                                      // Tighter (e.g. <5) would chase zero-
                                      // velocity-at-pad and oscillate, burning
                                      // fuel and bleeding VS to near-hover.
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
LOCAL AERO_POS_CAP       IS 12.      // clamp on the position term
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
// engines enabled (from the AG2 fire at startup). SHIP:MAXTHRUST
// therefore reflects 3-engine capability, so no further AG fire
// is needed until the 3->1 transition. The script reads live thrust
// values throughout, so it adapts to whatever thrust the AGs
// actually produce.
LOCAL LANDING_HANDOFF_CLR   IS 6000.  // AERO->LANDING trigger (m above pad)
LOCAL LANDING_IGNITE_MARGIN IS 40.    // extra m of margin on ignition alt
LOCAL LANDING_SAFETY_FRAC   IS 0.85.  // plan against 85% of max decel
LOCAL LANDING_SOLO_THR_OK   IS 0.85.  // switch to 1 eng if projected thr<=85%
LOCAL LANDING_SOLO_VS_MAX   IS 120.   // only switch to 1 eng when VS above this in magnitude
LOCAL LANDING_GEAR_CLR      IS 200.   // deploy gear below this clearance
LOCAL LANDING_EXIT_CLR      IS 150.   // exit to TOUCHDOWN at this clearance
LOCAL LANDING_EXIT_VS       IS 14.    // ...and when |VS| <= this
LOCAL LANDING_LEAN_CAP_DEG  IS 25.    // hard cap on lean during landing
LOCAL LANDING_TGO_MIN       IS 2.
LOCAL LANDING_TGO_MAX       IS 15.

// Touchdown (hover-and-settle to pad)
//
// TOUCH_TARGET_VS is the main fuel-efficiency knob. A more negative
// target (faster descent) proportionally reduces time-to-ground,
// which proportionally reduces fuel burn since throttle during
// steady descent is near hover (~40%). -6 m/s is about 3x faster
// than -2 m/s and saves roughly 2/3 of TOUCHDOWN fuel.
LOCAL TOUCH_TARGET_VS     IS -6.    // steady descent during touchdown
LOCAL TOUCH_TARGET_VS_LOW IS -2.    // when very close to ground (soft land)
LOCAL TOUCH_LOW_CLR       IS 15.    // "very low" threshold (m above pad)
LOCAL TOUCH_VS_GAIN       IS 0.8.   // P gain on VS error
LOCAL TOUCH_POS_K         IS 0.30.  // horizontal position pull
LOCAL TOUCH_POS_CAP       IS 8.     // cap on position term
LOCAL TOUCH_VEL_K         IS 1.50.  // horizontal velocity damping
LOCAL TOUCH_VEL_CAP       IS 10.    // cap on velocity term
LOCAL TOUCH_MAX_LEAN      IS 4.     // max lean during touchdown
LOCAL TOUCH_MAX_LEAN_LOW  IS 2.     // tighter lean cap near ground

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
LOCAL bestMissSeen       IS 99999.
LOCAL bestMissAlt        IS 0.

// Boostback target diagnostic values (set by computeBoostTarget)
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

// ------------------------------------------------------------
// Small helpers
// ------------------------------------------------------------
FUNCTION Clamp {
    PARAMETER valueIn, lo, hi.
    IF valueIn < lo { RETURN lo. }
    IF valueIn > hi { RETURN hi. }
    RETURN valueIn.
}

FUNCTION SignNum {
    PARAMETER valueIn.
    IF valueIn > 0 { RETURN 1. }
    IF valueIn < 0 { RETURN -1. }
    RETURN 0.
}

FUNCTION shipGeo {
    RETURN SHIP:GEOPOSITION.
}

FUNCTION surfaceHeightASL {
    LOCAL surfH IS shipGeo():TERRAINHEIGHT.
    IF surfH < 0 { SET surfH TO 0. }
    RETURN surfH.
}

FUNCTION terrainAGLCalc {
    LOCAL aglCalc IS SHIP:ALTITUDE - surfaceHeightASL().
    IF aglCalc < 0 { RETURN 0. }
    RETURN aglCalc.
}

FUNCTION bottomRadarClearance {
    LOCAL clr IS SHIP:BOUNDS:BOTTOMALTRADAR.
    IF clr < 0 { SET clr TO 0. }
    RETURN clr.
}

FUNCTION padClearance {
    LOCAL clr IS SHIP:ALTITUDE - padAlt.
    IF clr < 0 { RETURN 0. }
    RETURN clr.
}

FUNCTION descentClearance {
    RETURN padClearance().
}

FUNCTION touchClearance {
    LOCAL padClr    IS padClearance().
    LOCAL radarClr  IS ALT:RADAR.
    LOCAL bottomClr IS bottomRadarClearance().
    LOCAL outClr    IS padClr.
    IF radarClr > 0 AND radarClr < outClr + 200 {
        SET outClr TO MIN(outClr, radarClr).
    }
    IF bottomClr > 0 AND bottomClr < outClr + 200 {
        SET outClr TO MIN(outClr, bottomClr).
    }
    RETURN outClr.
}

FUNCTION northAxis { RETURN HEADING(0,0):FOREVECTOR. }
FUNCTION eastAxis  { RETURN HEADING(90,0):FOREVECTOR. }
FUNCTION upAxis    { RETURN UP:FOREVECTOR. }

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

// ------------------------------------------------------------
// Dynamic boostback target
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
FUNCTION computeBoostTarget {
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

    RETURN Clamp(vCoastTgt, BB_TOWARD_MIN, BB_TOWARD_MAX).
}

FUNCTION sayAt {
    PARAMETER rowNum, msg.
    PRINT msg + "                                                                                " AT (0, rowNum).
}

FUNCTION showStatus {
    PARAMETER title, detail1 IS "", detail2 IS "".
    sayAt(0, "PHASE  " + title).
    sayAt(1, "PAD DIR  act:" + ROUND(navMiss,0) + "m  " + nsText(navErrN) + "  " + ewText(navErrE)).
    sayAt(2, "FLIGHT HS:" + ROUND(navHs,1) + " m/s  VS:" + ROUND(SHIP:VERTICALSPEED,1) + " m/s  PADCLR:" + ROUND(navClearance,0) + " m  ALT:" + ROUND(SHIP:ALTITUDE,0) + " m").
    sayAt(3, detail1).
    sayAt(4, detail2).
}

// ------------------------------------------------------------
// Cached nav update
// ------------------------------------------------------------
FUNCTION updateNav {
    LOCAL padPos  IS padGeo:ALTITUDEPOSITION(padAlt).
    LOCAL relVec  IS padPos - SHIP:POSITION.
    SET navErrN   TO VDOT(relVec, northAxis()).
    SET navErrE   TO VDOT(relVec, eastAxis()).
    SET navMiss   TO SQRT(navErrN^2 + navErrE^2).
    SET navVelN   TO VDOT(SHIP:VELOCITY:SURFACE, northAxis()).
    SET navVelE   TO VDOT(SHIP:VELOCITY:SURFACE, eastAxis()).
    SET navHs     TO SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2 - SHIP:VERTICALSPEED^2)).
    SET navPadBrg TO padGeo:HEADING.
    SET navAgl    TO terrainAGLCalc().
    SET navClearance TO touchClearance().
    SET navSrfSpd TO SHIP:VELOCITY:SURFACE:MAG.

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
// FUNCTION logOpen {
//     IF EXISTS(LOG_PATH) { DELETEPATH(LOG_PATH). }
//     LOG "RTLS bullseye - Pad: " + padLatP + " / " + padLngP + " TerrainAlt:" + ROUND(padAlt,2) TO LOG_PATH.
//     LOG "T+sec | Phase | Alt km | VS | HS | Act m | Thr% | Msg" TO LOG_PATH.
//     LOG "----------------------------------------------------------------" TO LOG_PATH.
// }

// FUNCTION logLine {
//     PARAMETER msg.
//     LOG "T+" + ROUND(TIME:SECONDS,1)
//       + " | " + PHASE_NAMES[phase]
//       + " | " + ROUND(SHIP:ALTITUDE/1000,2) + "km"
//       + " | VS:" + ROUND(SHIP:VERTICALSPEED,1)
//       + " | HS:" + ROUND(navHs,1)
//       + " | Act:" + ROUND(navMiss,0)
//       + " | Thr:" + ROUND(THROTTLE*100,0)
//       + " | " + msg TO LOG_PATH.
// }

// FUNCTION logEvent {
//     PARAMETER msg.
//     logLine("*** " + msg + " ***").
// }

// FUNCTION logPeriodic {
//     PARAMETER msg IS "".
//     IF TIME:SECONDS - lastLogTime >= LOG_DT {
//         logLine(msg).
//         SET lastLogTime TO TIME:SECONDS.
//     }
// }

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
    IF ABS(VDOT(lookVec:NORMALIZED, northAxis())) < 0.92 { RETURN northAxis(). }
    RETURN eastAxis().
}

// Engine-first descent attitude. On this booster, FOREVECTOR is the
// engine/thrust direction, so facing up -> thrust up (decelerates
// descent). Leaning nose toward (corrN, corrE) puts a horizontal
// component into thrust in that same direction.
FUNCTION tailDownDir {
    PARAMETER corrNorth, corrEast, leanDeg.
    LOCAL horizMag IS SQRT(corrNorth^2 + corrEast^2).
    LOCAL noseVec IS upAxis().

    IF horizMag > 0.01 AND leanDeg > 0 {
        LOCAL horizVec IS northAxis()*corrNorth + eastAxis()*corrEast.
        SET noseVec TO upAxis()*COS(leanDeg) + horizVec:NORMALIZED*SIN(leanDeg).
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
//     { RETURN (northAxis()*navVelN + eastAxis()*navVelE) * 18. },
//     RED, "VEL", 1.0, TRUE, 0.40, TRUE, FALSE).

// LOCAL vdPadErr IS VECDRAW(
//     { RETURN SHIP:POSITION. },
//     { RETURN (northAxis()*navErrN + eastAxis()*navErrE). },
//     CYAN, "PAD", 1.0, TRUE, 0.38, TRUE, FALSE).

// LOCAL vdSteer IS VECDRAW(
//     { RETURN SHIP:POSITION. },
//     { RETURN (northAxis()*dbgSteerN + eastAxis()*dbgSteerE) * 20. },
//     YELLOW, "STEER", 1.0, TRUE, 0.40, TRUE, FALSE).

// ------------------------------------------------------------
// Main setup
// ------------------------------------------------------------
RCS ON.
activateAG(2).
GEAR OFF.
//logOpen().
PRINT "Loaded bullseye v1 - no terminal burn".
updateNav().
//logEvent("SCRIPT START terrainAlt:" + ROUND(padAlt,2) + " miss:" + ROUND(navMiss,0)).

UNTIL FALSE {
    updateNav().
    SET dbgSteerN TO 0.
    SET dbgSteerE TO 0.

    // Track best miss seen so we can see in the log how close we got
    IF navMiss < bestMissSeen {
        SET bestMissSeen TO navMiss.
        SET bestMissAlt TO SHIP:ALTITUDE.
    }

    // --------------------------------------------------------
    IF phase = PH_INIT {
        SET bbTargetToward TO computeBoostTarget().
        SET phase TO PH_FLIP.
        // logEvent(
        //     "INIT->FLIP miss:" + ROUND(navMiss,0)
        //   + " hs:" + ROUND(navHs,0)
        //   + " dBB:" + ROUND(bbDiagDbb,0)
        //   + " tCoast:" + ROUND(bbDiagTcoast,1)
        //   + " aH:" + ROUND(bbDiagAh,2)
        //   + " vCalc:" + ROUND(bbDiagVcalc,1)
        //   + " tgtToward:" + ROUND(bbTargetToward,1)
        // ).
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_FLIP {
        LOCK STEERING TO HEADING(navPadBrg, FLIP_PITCH).
        LOCK THROTTLE TO 0.
        LOCAL flipErr IS VANG(SHIP:FACING:FOREVECTOR, HEADING(navPadBrg, FLIP_PITCH):FOREVECTOR).
        showStatus("FLIP", "Aligning for boostback", "pitch err:" + ROUND(flipErr,1) + " deg  pad brg:" + ROUND(navPadBrg,1) + "  tgt toward:" + ROUND(bbTargetToward,0) + " m/s").
        // logPeriodic("flip err:" + ROUND(flipErr,1) + " brg:" + ROUND(navPadBrg,1)).

        IF flipErr < FLIP_TOL {
            SET bbStartTime   TO TIME:SECONDS.
            SET bbMode        TO 0.
            SET bbRevBias     TO 0.
            IF ABS(navCross) >= 4 {
                SET bbRevBias TO -SignNum(navCross) * MIN(BB_HEADING_MAX, 1.5 + ABS(navCross)*0.08).
            }
            SET bbRevHeading TO wrapBrg(navPadBrg + bbRevBias).
            SET bbAimBrg     TO bbRevHeading.
            SET phase TO PH_BOOSTBACK.
            // logEvent("FLIP->BOOSTBACK brg:" + ROUND(navPadBrg,1) + " tgtToward:" + ROUND(bbTargetToward,0) + " revBias:" + ROUND(bbRevBias,1)).
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

        LOCK STEERING TO HEADING(aimBrg, FLIP_PITCH).
        LOCK THROTTLE TO thrCmd.

        showStatus("BOOSTBACK", "mode:" + modeName + "  aim:" + ROUND(aimBrg,1) + " deg  throttle:" + ROUND(thrCmd*100,0) + "%", "toward:" + ROUND(navToward,0) + "  target:" + ROUND(bbTargetToward,0) + "  cross:" + ROUND(navCross,0) + "  velErr:" + ROUND(velErr,1) + "  " + ewText(navErrE)).

        // logPeriodic(
        //     "boost " + modeName
        //   + " act:" + ROUND(navMiss,0)
        //   + " hs:" + ROUND(navHs,0)
        //   + " toward:" + ROUND(navToward,0)
        //   + " tgt:" + ROUND(bbTargetToward,0)
        //   + " cross:" + ROUND(navCross,0)
        //   + " velErr:" + ROUND(velErr,1)
        //   + " aim:" + ROUND(aimBrg,1)
        //   + " " + nsText(navErrN)
        //   + " " + ewText(navErrE)
        // ).

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
            UNLOCK THROTTLE.
            LOCK THROTTLE TO 0.
            UNLOCK STEERING.
            SET corrStartTime TO TIME:SECONDS.
            SET corrMode TO 0.
            SET bbAimBrg TO navPadBrg.
            SET phase TO PH_CORRECTIVE.
            // logEvent("BOOSTBACK->CORRECTIVE " + bbExitReason).
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

        LOCK STEERING TO HEADING(aimBrgC, FLIP_PITCH).
        LOCK THROTTLE TO thrCorr.

        showStatus("CORRECTIVE", "mode:" + corrName + "  aim:" + ROUND(aimBrgC,1) + " deg  throttle:" + ROUND(thrCorr*100,0) + "%", "toward:" + ROUND(navToward,0) + "  cross:" + ROUND(navCross,0) + "  velErr:" + ROUND(velErrC,1) + "  aimErr:" + ROUND(aimErrC,1) + "  " + ewText(navErrE)).
        // logPeriodic("corrective " + corrName + " act:" + ROUND(navMiss,0) + " cross:" + ROUND(navCross,0) + " velErr:" + ROUND(velErrC,1) + " aimErr:" + ROUND(aimErrC,1)).

        IF corrMode = 1
           AND corrElapsed >= CORR_ALIGN_MIN_T
           AND ABS(velErrC) <= CORR_ALIGN_VELERR
           AND crossAbsC <= CORR_ALIGN_CROSS {
            UNLOCK THROTTLE.
            LOCK THROTTLE TO 0.
            UNLOCK STEERING.
            SET phase TO PH_COAST.
            // logEvent("CORRECTIVE->COAST align solved velErr:" + ROUND(velErrC,1)).
        }
        ELSE IF corrElapsed > CORR_MAX_TIME {
            UNLOCK THROTTLE.
            LOCK THROTTLE TO 0.
            UNLOCK STEERING.
            SET phase TO PH_COAST.
            // logEvent("CORRECTIVE->COAST timeout velErr:" + ROUND(velErrC,1)).
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_COAST {
        LOCK THROTTLE TO 0.
        // Engine-first coast with gentle velocity-damping trim
        LOCAL coastTgo  IS Clamp(navClearance / MAX(170, ABS(SHIP:VERTICALSPEED)), 10, 28).
        LOCAL coastDesVN IS Clamp((navErrN / MAX(14, coastTgo * 2.2)) - navVelN * 1.25, -8, 8).
        LOCAL coastDesVE IS Clamp((navErrE / MAX(14, coastTgo * 2.2)) - navVelE * 1.25, -10, 10).
        SET dbgSteerN TO coastDesVN.
        SET dbgSteerE TO coastDesVE.
        LOCAL coastAimVec IS northAxis()*(navErrN + coastDesVN * 90)
                          + eastAxis()*(navErrE + coastDesVE * 90)
                          + (-upAxis())*MAX(1, navClearance).
        IF coastAimVec:MAG < 0.01 {
            SET coastAimVec TO (-upAxis()).
        }
        LOCK STEERING TO LOOKDIRUP((-coastAimVec):NORMALIZED, rollRefVec((-coastAimVec))).
        RCS ON.

        IF NOT coastFinsOut AND (SHIP:ALTITUDE < COAST_FIN_ALT OR SHIP:VERTICALSPEED <= 0) {
            activateAG(1).
            setFinAuthority(22).
            SET coastFinsOut TO TRUE.
            // logEvent("Fins deployed auth:22").
        }

        IF SHIP:VERTICALSPEED <= 0 { SET coastApoSeen TO TRUE. }

        showStatus("COAST", "Engine-first to LZ + trim", "fins:" + coastFinsOut + "  apo seen:" + coastApoSeen + "  pad brg:" + ROUND(navPadBrg,1)).
        // logPeriodic("coast act:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0) + " desV:" + ROUND(coastDesVN,0) + "/" + ROUND(coastDesVE,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).

        IF coastApoSeen AND SHIP:ALTITUDE < ENTRY_TRIGGER_ALT AND SHIP:VERTICALSPEED < -220 {
            SET entryStartTime TO TIME:SECONDS.
            SET phase TO PH_ENTRY.
            // logEvent("COAST->ENTRY alt:" + ROUND(SHIP:ALTITUDE,0) + " spd:" + ROUND(navSrfSpd,0) + " act:" + ROUND(navMiss,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).
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
        LOCAL clrEntry     IS descentClearance().
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

        LOCK STEERING TO tailDownDir(corrN, corrE, leanEff).
        LOCK THROTTLE TO thrEntry.
        RCS ON.
        IF coastFinsOut { setFinAuthority(26). }

        showStatus(
            "ENTRY",
            "tgo:" + ROUND(tgoEntry,1) + "  reqA N/E:" + ROUND(reqAN,1) + "/" + ROUND(reqAE,1) + "  lean:" + ROUND(leanEff,1) + "  thr:" + ROUND(thrEntry*100,0) + "%",
            "miss:" + ROUND(navMiss,0) + "  hs:" + ROUND(navHs,1) + "  vs:" + ROUND(vsEntryNow,0) + "  best:" + ROUND(bestMissSeen,0) + "  elapsed:" + ROUND(entryElapsed,1)
        ).
        // logPeriodic(
        //     "entry alt:" + ROUND(SHIP:ALTITUDE,0)
        //   + " vs:" + ROUND(vsEntryNow,0)
        //   + " act:" + ROUND(navMiss,0)
        //   + " hs:" + ROUND(navHs,1)
        //   + " thr:" + ROUND(thrEntry*100,0)
        //   + " lean:" + ROUND(leanEff,1)
        //   + " tgo:" + ROUND(tgoEntry,1)
        //   + " reqAN:" + ROUND(reqAN,1)
        //   + " reqAE:" + ROUND(reqAE,1)
        //   + " corrN:" + ROUND(corrN,1)
        //   + " corrE:" + ROUND(corrE,1)
        //   + " " + nsText(navErrN) + " " + ewText(navErrE)
        // ).

        // Exit conditions. Primary exit is HS braked below ENTRY_HS_EXIT;
        // everything else is a safety/fallback.
        LOCAL exitReason IS "".
        IF navHs < ENTRY_HS_EXIT AND entryElapsed > ENTRY_MIN_TIME {
            SET exitReason TO "HS braked miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,1).
        }
        ELSE IF navMiss < ENTRY_MISS_EXIT AND entryElapsed > ENTRY_MIN_TIME {
            SET exitReason TO "centered miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,1).
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
            LOCK THROTTLE TO 0.
            SET aeroStartTime TO TIME:SECONDS.
            SET phase TO PH_AERO.
            // logEvent("ENTRY->AERO " + exitReason + " alt:" + ROUND(SHIP:ALTITUDE,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).
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

        // Position pull toward pad (both axes). The sign is correct
        // now (-navErr gives a tilt away from the pad, so fin force
        // pulls toward the pad).
        IF navMiss > 40 {
            LOCAL nudgeN IS Clamp(-navErrN * AERO_POS_K, -AERO_POS_CAP, AERO_POS_CAP).
            LOCAL nudgeE IS Clamp(-navErrE * AERO_POS_K, -AERO_POS_CAP, AERO_POS_CAP).
            SET corrN_A TO corrN_A + nudgeN.
            SET corrE_A TO corrE_A + nudgeE.
        }

        SET dbgSteerN TO corrN_A.
        SET dbgSteerE TO corrE_A.

        LOCK STEERING TO tailDownDir(corrN_A, corrE_A, AERO_LEAN_DEG).
        LOCK THROTTLE TO 0.
        RCS ON.
        IF coastFinsOut { setFinAuthority(40). }

        // Drop legs low so the impact point is well-defined even
        // though we are crashing.
        IF descentClearance() < 120 {
            GEAR ON.
        }

        showStatus(
            "AERO",
            "fin-reaction + pad pull  lean:" + ROUND(AERO_LEAN_DEG,1),
            "miss:" + ROUND(navMiss,0) + "  best:" + ROUND(bestMissSeen,0) + " @ " + ROUND(bestMissAlt,0) + "m  hs:" + ROUND(navHs,1)
        ).
        // logPeriodic(
        //     "aero act:" + ROUND(navMiss,0)
        //   + " hs:" + ROUND(navHs,1)
        //   + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
        //   + " clr:" + ROUND(descentClearance(),0)
        //   + " corrN:" + ROUND(corrN_A,1)
        //   + " corrE:" + ROUND(corrE_A,1)
        //   + " best:" + ROUND(bestMissSeen,0)
        //   + " " + nsText(navErrN) + " " + ewText(navErrE)
        // ).

        // Hand off to landing burn at altitude. Impact detection is
        // kept as a fallback in case landing never engages for some
        // reason (fuel starvation, etc.)
        IF descentClearance() < LANDING_HANDOFF_CLR {
            SET landingStartTime TO TIME:SECONDS.
            SET phase TO PH_LANDING_BURN.
            // logEvent(
            //     "AERO->LANDING act:" + ROUND(navMiss,0)
            //   + " hs:" + ROUND(navHs,1)
            //   + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
            //   + " clr:" + ROUND(descentClearance(),0)
            //   + " " + nsText(navErrN) + " " + ewText(navErrE)
            // ).
        }
        ELSE IF impactDetected() {
            SET phase TO PH_IMPACT.
            // logEvent(
            //     "AERO->IMPACT act:" + ROUND(navMiss,0)
            //   + " hs:" + ROUND(navHs,1)
            //   + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
            //   + " best:" + ROUND(bestMissSeen,0) + "@" + ROUND(bestMissAlt,0)
            //   + " " + nsText(navErrN) + " " + ewText(navErrE)
            // ).
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_LANDING_BURN {
        // Hoverslam landing burn, 3 engines at ignition, transitions
        // to 1 engine for final descent.
        //
        // Phase structure:
        //   1. Pre-ignition: configure 3-engine mode (AG3), fall
        //      engines-first, compute stopping distance live. Ignite
        //      when stop_dist + margin >= clearance.
        //   2. Ignited (3 engines): throttle controls vertical decel,
        //      lean gives horizontal correction from ZEM/ZEV. Switch
        //      to 1 engine (AG4) when 1 engine alone could hold the
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
            // SHIP:MAXTHRUST reflects 3-engine capability.
            LOCAL tmMax IS SHIP:MAXTHRUST / MAX(0.1, SHIP:MASS).
            LOCAL aNet  IS MAX(1, tmMax * LANDING_SAFETY_FRAC - padG).

            // Kinematic stopping distance from current fall speed
            LOCAL stopDist IS vsDown * vsDown / (2 * aNet).
            LOCAL ignAlt   IS stopDist + LANDING_IGNITE_MARGIN.

            // Pre-ignition steering: keep AERO-style retrograde attitude
            // so the engines are pointed opposite to velocity (nose up-ish).
            LOCAL corrN_pre IS navVelN.
            LOCAL corrE_pre IS navVelE.
            LOCK STEERING TO tailDownDir(corrN_pre, corrE_pre, AERO_LEAN_DEG).
            LOCK THROTTLE TO 0.

            // Ignite when the stopping distance catches up to clearance
            IF clr <= ignAlt {
                SET landingIgnited TO TRUE.
                // logEvent(
                //     "LANDING IGNITE clr:" + ROUND(clr,0)
                //   + " stopDist:" + ROUND(stopDist,0)
                //   + " tmMax:" + ROUND(tmMax,1)
                //   + " vs:" + ROUND(vsLand,1)
                //   + " miss:" + ROUND(navMiss,0)
                // ).
            }

            showStatus(
                "LANDING",
                "pre-ignition  tmMax:" + ROUND(tmMax,1) + "  stopDist:" + ROUND(stopDist,0) + "m  ignAlt:" + ROUND(ignAlt,0) + "m",
                "clr:" + ROUND(clr,0) + "  vs:" + ROUND(vsLand,1) + "  hs:" + ROUND(navHs,1) + "  miss:" + ROUND(navMiss,0)
            ).
            // logPeriodic(
            //     "land-pre clr:" + ROUND(clr,0)
            //   + " vs:" + ROUND(vsLand,1)
            //   + " hs:" + ROUND(navHs,1)
            //   + " act:" + ROUND(navMiss,0)
            //   + " tmMax:" + ROUND(tmMax,1)
            //   + " stopDist:" + ROUND(stopDist,0)
            //   + " ignAlt:" + ROUND(ignAlt,0)
            //   + " " + nsText(navErrN) + " " + ewText(navErrE)
            // ).
        }
        // ---- Ignited: active burn with ZEM/ZEV horizontal guidance ----
        ELSE {
            LOCAL tm IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
            IF tm < 0.1 { SET tm TO 0.1. }

            // Required vertical deceleration to stop at ground
            LOCAL clrFloor IS MAX(20, clr).
            LOCAL aVertReq IS (vsDown * vsDown) / (2 * clrFloor) + padG.

            // tgo estimate: time to ground at current decel rate
            LOCAL tgoLand IS Clamp(
                2 * clrFloor / MAX(5, vsDown + 5),
                LANDING_TGO_MIN,
                LANDING_TGO_MAX
            ).

            // ZEM/ZEV horizontal acceleration request
            LOCAL tgo2 IS tgoLand * tgoLand.
            LOCAL reqAN IS (6 / tgo2) * navErrN - (8 / tgoLand) * navVelN.
            LOCAL reqAE IS (6 / tgo2) * navErrE - (8 / tgoLand) * navVelE.
            LOCAL reqAHmag IS SQRT(reqAN * reqAN + reqAE * reqAE).

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

            // Total commanded acceleration magnitude and direction
            LOCAL aTotal IS SQRT(aVertReq * aVertReq + reqAHmag * reqAHmag).
            LOCAL thrLand IS Clamp(aTotal / tm, 0, 1).

            // Lean angle from vertical (ARCCOS of vertical / total)
            LOCAL leanLand IS 0.
            IF aTotal > 0.1 {
                SET leanLand TO ARCCOS(Clamp(aVertReq / aTotal, -1, 1)).
            }
            IF leanLand > LANDING_LEAN_CAP_DEG { SET leanLand TO LANDING_LEAN_CAP_DEG. }

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

            LOCK STEERING TO tailDownDir(corrN, corrE, leanLand).
            LOCK THROTTLE TO thrLand.
            RCS ON.

            // 3-engine -> 1-engine transition. If one engine alone could
            // hold the required vertical decel at a reasonable throttle,
            // drop to one. We estimate 1-engine capability by scaling
            // the current measured capability down by the engine count
            // ratio.
            IF NOT landingSoloMode AND elapsedLand > 1.0 AND vsDown < LANDING_SOLO_VS_MAX {
                LOCAL tmSolo IS tm / 3.   // assumes AG3 gave us 3x the solo thrust
                LOCAL thrSoloProj IS 1.0.
                IF tmSolo > 0.1 {
                    SET thrSoloProj TO aTotal / tmSolo.
                }
                IF thrSoloProj <= LANDING_SOLO_THR_OK {
                    activateAG(3).
                    SET landingSoloMode TO TRUE.
                    // logEvent(
                    //     "LANDING solo-engine clr:" + ROUND(clr,0)
                    //   + " vs:" + ROUND(vsLand,1)
                    //   + " thrProj:" + ROUND(thrSoloProj*100,0) + "%"
                    // ).
                }
            }

            // Deploy gear below a threshold
            IF NOT landingGearOut AND clr < LANDING_GEAR_CLR {
                GEAR ON.
                SET landingGearOut TO TRUE.
                // logEvent("Gear deployed clr:" + ROUND(clr,0)).
            }

            showStatus(
                "LANDING",
                "thr:" + ROUND(thrLand*100,0) + "%  lean:" + ROUND(leanLand,1) + "  tgo:" + ROUND(tgoLand,1) + "  solo:" + landingSoloMode,
                "clr:" + ROUND(clr,0) + "  vs:" + ROUND(vsLand,1) + "  hs:" + ROUND(navHs,1) + "  miss:" + ROUND(navMiss,0)
            ).
            // logPeriodic(
            //     "land clr:" + ROUND(clr,0)
            //   + " vs:" + ROUND(vsLand,1)
            //   + " hs:" + ROUND(navHs,1)
            //   + " act:" + ROUND(navMiss,0)
            //   + " thr:" + ROUND(thrLand*100,0)
            //   + " lean:" + ROUND(leanLand,1)
            //   + " aV:" + ROUND(aVertReq,1)
            //   + " aH:" + ROUND(reqAHmag,1)
            //   + " tm:" + ROUND(tm,1)
            //   + " solo:" + landingSoloMode
            //   + " " + nsText(navErrN) + " " + ewText(navErrE)
            // ).

            // Exit to TOUCHDOWN when low and slow
            IF clr <= LANDING_EXIT_CLR AND vsDown <= LANDING_EXIT_VS {
                SET touchStartTime TO TIME:SECONDS.
                SET phase TO PH_TOUCHDOWN.
                // logEvent(
                //     "LANDING->TOUCHDOWN clr:" + ROUND(clr,0)
                //   + " vs:" + ROUND(vsLand,1)
                //   + " hs:" + ROUND(navHs,1)
                //   + " miss:" + ROUND(navMiss,0)
                // ).
            }
            // Safety: if we somehow got on the ground in landing burn
            ELSE IF impactDetected() {
                SET phase TO PH_IMPACT.
                // logEvent(
                //     "LANDING->IMPACT (unexpected) clr:" + ROUND(clr,0)
                //   + " vs:" + ROUND(vsLand,1)
                //   + " miss:" + ROUND(navMiss,0)
                // ).
            }
            // Fuel-out fallback
            ELSE IF SHIP:AVAILABLETHRUST <= 0.01 {
                SET phase TO PH_IMPACT.
                // logEvent(
                //     "LANDING->IMPACT FUEL-OUT clr:" + ROUND(clr,0)
                //   + " vs:" + ROUND(vsLand,1)
                //   + " miss:" + ROUND(navMiss,0)
                // ).
            }
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_TOUCHDOWN {
        // Hover-and-settle. Hold target VS, null horizontal velocity,
        // keep lean very small. Exit when SHIP:STATUS indicates landing.

        LOCAL vsTouch IS SHIP:VERTICALSPEED.
        LOCAL clr     IS touchClearance().
        LOCAL tm      IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
        IF tm < 0.1 { SET tm TO 0.1. }

        // Target descent rate - slower when very close
        LOCAL targetVs IS TOUCH_TARGET_VS.
        IF clr < TOUCH_LOW_CLR { SET targetVs TO TOUCH_TARGET_VS_LOW. }

        // Required vertical accel = gravity + correction to reach target VS
        LOCAL vsErr    IS targetVs - vsTouch.   // +ve means need more thrust (rising VS)
        LOCAL aVertReq IS padG + vsErr * TOUCH_VS_GAIN.
        IF aVertReq < 0 { SET aVertReq TO 0. }

        LOCAL thrTouch IS Clamp(aVertReq / tm, 0, 1).

        // Horizontal correction: velocity damp + position pull
        LOCAL corrN IS Clamp(-navVelN * TOUCH_VEL_K, -TOUCH_VEL_CAP, TOUCH_VEL_CAP)
                     + Clamp( navErrN * TOUCH_POS_K, -TOUCH_POS_CAP, TOUCH_POS_CAP).
        LOCAL corrE IS Clamp(-navVelE * TOUCH_VEL_K, -TOUCH_VEL_CAP, TOUCH_VEL_CAP)
                     + Clamp( navErrE * TOUCH_POS_K, -TOUCH_POS_CAP, TOUCH_POS_CAP).

        // Lean cap very tight near ground
        LOCAL leanCap IS TOUCH_MAX_LEAN.
        IF clr < TOUCH_LOW_CLR { SET leanCap TO TOUCH_MAX_LEAN_LOW. }

        LOCAL corrMag IS SQRT(corrN * corrN + corrE * corrE).
        LOCAL leanTouch IS 0.
        IF corrMag > 0.1 { SET leanTouch TO leanCap. }

        SET dbgSteerN TO corrN.
        SET dbgSteerE TO corrE.

        LOCK STEERING TO tailDownDir(corrN, corrE, leanTouch).
        LOCK THROTTLE TO thrTouch.
        RCS ON.

        showStatus(
            "TOUCHDOWN",
            "thr:" + ROUND(thrTouch*100,0) + "%  tgtVs:" + ROUND(targetVs,1) + "  lean:" + ROUND(leanTouch,1),
            "clr:" + ROUND(clr,1) + "  vs:" + ROUND(vsTouch,2) + "  hs:" + ROUND(navHs,1) + "  miss:" + ROUND(navMiss,0)
        ).
        // logPeriodic(
        //     "touch clr:" + ROUND(clr,1)
        //   + " vs:" + ROUND(vsTouch,2)
        //   + " hs:" + ROUND(navHs,1)
        //   + " act:" + ROUND(navMiss,0)
        //   + " thr:" + ROUND(thrTouch*100,0)
        //   + " lean:" + ROUND(leanTouch,1)
        //   + " tgtVs:" + ROUND(targetVs,1)
        //   + " " + nsText(navErrN) + " " + ewText(navErrE)
        // ).

        // Landed detection - trust KSP's ground-contact flag primarily
        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
            SET phase TO PH_IMPACT.
            // logEvent(
            //     "LANDED status:" + SHIP:STATUS
            //   + " miss:" + ROUND(navMiss,0)
            //   + " hs:" + ROUND(navHs,1)
            //   + " vs:" + ROUND(vsTouch,2)
            // ).
        }
        // Secondary check: essentially stopped near ground
        ELSE IF clr < 3 AND ABS(vsTouch) < 1 AND navHs < 3 {
            SET phase TO PH_IMPACT.
            // logEvent(
            //     "LANDED (soft) miss:" + ROUND(navMiss,0)
            //   + " hs:" + ROUND(navHs,1)
            //   + " vs:" + ROUND(vsTouch,2)
            //   + " clr:" + ROUND(clr,1)
            // ).
        }
        // Fuel-out fallback
        ELSE IF SHIP:AVAILABLETHRUST <= 0.01 {
            SET phase TO PH_IMPACT.
            // logEvent(
            //     "TOUCHDOWN->IMPACT FUEL-OUT clr:" + ROUND(clr,1)
            //   + " vs:" + ROUND(vsTouch,2)
            //   + " miss:" + ROUND(navMiss,0)
            // ).
        }
    }

    // --------------------------------------------------------
    ELSE IF phase = PH_IMPACT {
        // Full shutdown: engines, RCS, SAS, steering, throttle.
        LOCK THROTTLE TO 0.
        UNLOCK STEERING.
        RCS OFF.
        SAS OFF.
        showStatus(
            "IMPACT",
            "shutdown complete",
            "status:" + SHIP:STATUS + "  miss:" + ROUND(navMiss,0) + "  best:" + ROUND(bestMissSeen,0) + "  hs:" + ROUND(navHs,1) + "  vs:" + ROUND(SHIP:VERTICALSPEED,1)
        ).
        BREAK.
    }

    WAIT 0.05.
}

UNLOCK STEERING.
UNLOCK THROTTLE.
LOCK THROTTLE TO 0.
RCS OFF.
// logEvent("SCRIPT END final miss:" + ROUND(navMiss,0) + " best miss seen:" + ROUND(bestMissSeen,0) + " @ " + ROUND(bestMissAlt,0) + "m").
