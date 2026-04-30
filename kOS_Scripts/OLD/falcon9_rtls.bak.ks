// ============================================================
// falcon9_rtls_phase3_flattened_v2.ks
//
// Flattened / cached phase-3 RTLS script.
// Goal: reduce hot-path function churn in kOS and keep guidance
// math in one cached pad-line frame.
//
// Phases:
//   INIT -> FLIP -> BOOSTBACK -> COAST -> ENTRY -> AERO -> LANDING -> TOUCH -> DONE
//
// Notes:
//   - Boostback is intentionally simple:
//       1) kill cross-track velocity
//       2) build only MODEST padward speed
//   - Predictor is debug only.
//   - Navigation state is cached ONCE per loop.
// ============================================================

@LAZYGLOBAL OFF.

PARAMETER PAD_LAT IS -0.0972.
PARAMETER PAD_LNG IS -74.5577.

// ------------------------------------------------------------
// Constants
// ------------------------------------------------------------
LOCAL LOG_FILE           IS "0:/rtls_phase3_flat_log.txt".
LOCAL LOG_DT             IS 1.5.
LOCAL PRED_DT            IS 0.75.

LOCAL FLIP_PITCH         IS 6.
LOCAL FLIP_TOL           IS 4.
LOCAL BOOST_MIN_TIME     IS 4.
LOCAL BOOST_MAX_TIME     IS 58.
LOCAL BOOST_ALIGN_CROSS  IS 18.
LOCAL BOOST_TOWARD_BAND  IS 8.
LOCAL BOOST_TARGET_MIN   IS 85.
LOCAL BOOST_TARGET_MAX   IS 135.
LOCAL BOOST_HEADING_MAX  IS 18.
LOCAL BOOST_HEADING_K    IS 0.16.
LOCAL BOOST_BIAS_K       IS 0.035.
LOCAL BOOST_ALIGN_VEL    IS 8.
LOCAL BOOST_ALIGN_DOT    IS 0.985.
LOCAL BOOST_REVERSE_FLOOR IS 12.
LOCAL COAST_FIN_ALT      IS 45000.
LOCAL ENTRY_TRIGGER_ALT  IS 28000.
LOCAL ENTRY_END_SPEED    IS 430.
LOCAL ENTRY_MAX_TIME     IS 18.
LOCAL ENTRY_MIN_TIME     IS 2.
LOCAL AERO_DONE_MIN_AGL  IS 2600.
LOCAL AERO_DONE_MAX_AGL  IS 5200.
LOCAL COAST_LEAN_DEG     IS 8.
LOCAL ENTRY_LEAN_DEG     IS 16.
LOCAL AERO_LEAN_DEG      IS 26.
LOCAL LAND_LEAN_DEG      IS 18.
LOCAL TOUCH_LEAN_DEG     IS 10.
LOCAL TOUCHDOWN_AGL      IS 35.
LOCAL LAND_WANT_MIN      IS 8.
LOCAL LAND_WANT_MAX      IS 36.
LOCAL LAND_SHORT_TMIN    IS 1.0.
LOCAL LAND_SHORT_TMAX    IS 3.2.
LOCAL LAND_SHORT_GAIN    IS 1.15.
LOCAL NS_WEIGHT_COAST    IS 1.10.
LOCAL NS_WEIGHT_ENTRY    IS 1.35.
LOCAL NS_WEIGHT_AERO     IS 1.55.

LOCAL PH_INIT      IS 0.
LOCAL PH_FLIP      IS 1.
LOCAL PH_BOOSTBACK IS 2.
LOCAL PH_COAST     IS 3.
LOCAL PH_ENTRY     IS 4.
LOCAL PH_AERO      IS 5.
LOCAL PH_LANDING   IS 6.
LOCAL PH_TOUCH     IS 7.
LOCAL PH_DONE      IS 8.
LOCAL PHASE_NAMES IS LIST("INIT", "FLIP", "BOOSTBACK", "COAST", "ENTRY", "AERO", "LANDING", "TOUCH", "DONE").

// ------------------------------------------------------------
// State
// ------------------------------------------------------------
LOCAL phase            IS PH_INIT.
LOCAL padGeo           IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL padAlt           IS padGeo:TERRAINHEIGHT.
LOCAL predGeo          IS padGeo.
LOCAL predErrN         IS 0.
LOCAL predErrE         IS 0.
LOCAL lastPredTime     IS -999.
LOCAL lastLogTime      IS -999.

LOCAL bbStartTime      IS 0.
LOCAL bbExitReason     IS "".
LOCAL bbTargetToward   IS 0.
LOCAL bbBestActMiss    IS 999999.
LOCAL bbBestHs         IS 999999.
LOCAL bbBestToward     IS -999999.
LOCAL bbMode           IS 0.
LOCAL coastFinsOut     IS FALSE.
LOCAL coastApoSeen     IS FALSE.
LOCAL entryStartTime   IS 0.
LOCAL aeroRcsOn        IS FALSE.
LOCAL landingStartTime  IS 0.
LOCAL touchStartTime    IS 0.
LOCAL legsOut           IS FALSE.
LOCAL landingHoldLatched IS FALSE.

// Cached nav state, updated ONCE per loop
LOCAL navErrN          IS 0.
LOCAL navErrE          IS 0.
LOCAL navMiss          IS 0.
LOCAL navVelN          IS 0.
LOCAL navVelE          IS 0.
LOCAL navHs            IS 0.
LOCAL navToward        IS 0.
LOCAL navCross         IS 0.
LOCAL navPadBrg        IS 0.
LOCAL navAgl           IS 0.
LOCAL navSrfSpd        IS 0.
LOCAL navAlign         IS 0.

// ------------------------------------------------------------
// Small helpers only
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
    RETURN LATLNG(SHIP:LATITUDE, SHIP:LONGITUDE).
}

FUNCTION terrainAGLCalc {
    LOCAL aglCalc IS SHIP:ALTITUDE - shipGeo():TERRAINHEIGHT.
    IF aglCalc < 0 { RETURN 0. }
    RETURN aglCalc.
}

FUNCTION northAxis { RETURN HEADING(0,0):FOREVECTOR. }
FUNCTION eastAxis  { RETURN HEADING(90,0):FOREVECTOR. }
FUNCTION upAxis    { RETURN UP:FOREVECTOR. }

FUNCTION rotVec {
    PARAMETER vecIn, axisIn, degIn.
    LOCAL cosA IS COS(degIn).
    LOCAL sinA IS SIN(degIn).
    RETURN vecIn*cosA + VCRS(axisIn, vecIn)*sinA + axisIn*VDOT(axisIn, vecIn)*(1-cosA).
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

// ------------------------------------------------------------
// Cached nav update
// ------------------------------------------------------------
FUNCTION updateNav {
    LOCAL padPos IS padGeo:ALTITUDEPOSITION(padAlt).
    SET navErrN   TO VDOT(padPos, northAxis()).
    SET navErrE   TO VDOT(padPos, eastAxis()).
    SET navMiss   TO SQRT(navErrN^2 + navErrE^2).
    SET navVelN   TO VDOT(SHIP:VELOCITY:SURFACE, northAxis()).
    SET navVelE   TO VDOT(SHIP:VELOCITY:SURFACE, eastAxis()).
    SET navHs     TO SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2 - SHIP:VERTICALSPEED^2)).
    SET navPadBrg TO padGeo:HEADING.
    SET navAgl    TO terrainAGLCalc().
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
FUNCTION logOpen {
    IF EXISTS(LOG_FILE) { DELETEPATH(LOG_FILE). }
    LOG "RTLS phase3 flat - Pad: " + PAD_LAT + " / " + PAD_LNG + " TerrainAlt:" + ROUND(padAlt,2) TO LOG_FILE.
    LOG "T+sec | Phase | Alt km | VS | HS | Pred m | Act m | Thr% | Msg" TO LOG_FILE.
    LOG "----------------------------------------------------------------" TO LOG_FILE.
}

FUNCTION logLine {
    PARAMETER msg.
    LOG "T+" + ROUND(TIME:SECONDS,1)
      + " | " + PHASE_NAMES[phase]
      + " | " + ROUND(SHIP:ALTITUDE/1000,2) + "km"
      + " | VS:" + ROUND(SHIP:VERTICALSPEED,1)
      + " | HS:" + ROUND(navHs,1)
      + " | Pred:" + ROUND(SQRT(predErrN^2 + predErrE^2),0)
      + " | Act:" + ROUND(navMiss,0)
      + " | Thr:" + ROUND(THROTTLE*100,0)
      + " | " + msg TO LOG_FILE.
}

FUNCTION logEvent {
    PARAMETER msg.
    logLine("*** " + msg + " ***").
}

FUNCTION logPeriodic {
    PARAMETER msg IS "".
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
// Predictor (debug only)
// ------------------------------------------------------------
FUNCTION predictImpactVac {
    LOCAL muVal    IS SHIP:BODY:MU.
    LOCAL bodyRad  IS SHIP:BODY:RADIUS.
    LOCAL bodyPos  IS SHIP:BODY:POSITION.
    LOCAL posVec   IS -bodyPos.
    LOCAL velVec   IS SHIP:VELOCITY:ORBIT.
    LOCAL rotPer   IS SHIP:BODY:ROTATIONPERIOD.
    LOCAL rotAxis  IS V(0,1,0).
    LOCAL stepDt   IS 4.0.
    LOCAL tofVal   IS 0.

    IF SHIP:BODY:ANGULARVEL:MAG > 0.000001 {
        SET rotAxis TO SHIP:BODY:ANGULARVEL:NORMALIZED.
    }

    UNTIL tofVal > 1800 {
        LOCAL posMag IS posVec:MAG.
        LOCAL acc0   IS -(muVal/(posMag^3)) * posVec.
        LOCAL posMid IS posVec + velVec*(stepDt/2).
        LOCAL velMid IS velVec + acc0*(stepDt/2).
        LOCAL accMid IS -(muVal/(posMid:MAG^3)) * posMid.
        SET posVec TO posVec + velMid*stepDt.
        SET velVec TO velVec + accMid*stepDt.
        SET tofVal TO tofVal + stepDt.
        IF posVec:MAG - bodyRad <= padAlt {
            LOCAL rotDeg IS 360 * tofVal / rotPer.
            RETURN SHIP:BODY:GEOPOSITIONOF(rotVec(posVec, rotAxis, -rotDeg) + bodyPos).
        }
    }

    RETURN SHIP:GEOPOSITION.
}

FUNCTION updatePrediction {
    IF TIME:SECONDS - lastPredTime < PRED_DT { RETURN. }
    SET predGeo TO predictImpactVac().
    LOCAL predVec IS padGeo:ALTITUDEPOSITION(padAlt) - predGeo:ALTITUDEPOSITION(predGeo:TERRAINHEIGHT).
    SET predErrN TO VDOT(predVec, northAxis()).
    SET predErrE TO VDOT(predVec, eastAxis()).
    SET lastPredTime TO TIME:SECONDS.
}

// ------------------------------------------------------------
// Simple direction helpers
// ------------------------------------------------------------
FUNCTION rollRefVec {
    PARAMETER lookVec.
    IF ABS(VDOT(lookVec:NORMALIZED, northAxis())) < 0.92 { RETURN northAxis(). }
    RETURN eastAxis().
}

FUNCTION tailDownDir {
    PARAMETER corrNorth, corrEast, leanDeg.
    LOCAL horizMag IS SQRT(corrNorth^2 + corrEast^2).
    LOCAL noseVec IS upAxis().

    IF horizMag > 0.01 AND leanDeg > 0 {
        LOCAL horizVec IS northAxis()*corrNorth + eastAxis()*corrEast.
        // nose opposite desired correction for this tail-first aero config
        SET noseVec TO upAxis()*COS(leanDeg) - horizVec:NORMALIZED*SIN(leanDeg).
    }

    RETURN LOOKDIRUP(noseVec:NORMALIZED, rollRefVec(noseVec)).
}

FUNCTION landingIgnitionAGL {
    LOCAL gravAcc   IS SHIP:BODY:MU / ((SHIP:BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL thrustAcc IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
    LOCAL netAcc    IS MAX(1.2, thrustAcc - gravAcc).
    LOCAL stopV     IS MAX(0, -SHIP:VERTICALSPEED).
    LOCAL stopDist  IS stopV*stopV / (2*netAcc).
    LOCAL margin    IS 1200 + navHs*6.0 + MIN(2600, navMiss*0.70).
    RETURN Clamp(stopDist * 1.58 + margin, AERO_DONE_MIN_AGL, AERO_DONE_MAX_AGL).
}


FUNCTION desiredLandToward {
    LOCAL tgoLand IS Clamp(navAgl / MAX(55, ABS(SHIP:VERTICALSPEED)), 3.0, 12).
    LOCAL wantVal IS navMiss / tgoLand + MAX(0, -navToward) * 0.18 + navHs*0.04.
    RETURN Clamp(wantVal, LAND_WANT_MIN, LAND_WANT_MAX).
}

FUNCTION landShortTime {
    LOCAL tShort IS navAgl / MAX(135, ABS(SHIP:VERTICALSPEED)).
    SET tShort TO tShort + navHs / 75.
    RETURN Clamp(tShort * LAND_SHORT_GAIN, LAND_SHORT_TMIN, LAND_SHORT_TMAX).
}

FUNCTION timeToTouchdown {
    LOCAL downVs IS MAX(1, -SHIP:VERTICALSPEED).
    RETURN navAgl / downVs.
}

FUNCTION hoverThrottle {
    LOCAL gravAccVal   IS SHIP:BODY:MU / ((SHIP:BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL thrustAccVal IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
    RETURN Clamp(gravAccVal / MAX(0.1, thrustAccVal), 0.05, 0.98).
}

FUNCTION landingThrottleCmd {
    PARAMETER desiredVs.
    LOCAL gravAccVal   IS SHIP:BODY:MU / ((SHIP:BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL thrustAccVal IS SHIP:AVAILABLETHRUST / MAX(0.1, SHIP:MASS).
    LOCAL accelCmd     IS Clamp((desiredVs - SHIP:VERTICALSPEED) * 1.10, -6, 30).
    RETURN Clamp((gravAccVal + accelCmd) / MAX(0.1, thrustAccVal), 0.0, 1.0).
}

// ------------------------------------------------------------
// Debug vectors
// ------------------------------------------------------------
CLEARVECDRAWS().
LOCAL vdPad IS VECDRAW(
    { RETURN padGeo:ALTITUDEPOSITION(padAlt + 1500). },
    { RETURN padGeo:ALTITUDEPOSITION(padAlt) - padGeo:ALTITUDEPOSITION(padAlt + 1500). },
    GREEN, "LZ", 1.0, TRUE, 0.45, TRUE, FALSE).

LOCAL vdPred IS VECDRAW(
    { RETURN predGeo:ALTITUDEPOSITION(predGeo:TERRAINHEIGHT + 1300). },
    { RETURN predGeo:ALTITUDEPOSITION(predGeo:TERRAINHEIGHT) - predGeo:ALTITUDEPOSITION(predGeo:TERRAINHEIGHT + 1300). },
    YELLOW, "PRED", 1.0, TRUE, 0.45, TRUE, FALSE).

LOCAL vdVel IS VECDRAW(
    { RETURN SHIP:POSITION. },
    { RETURN (northAxis()*navVelN + eastAxis()*navVelE) * 18. },
    RED, "VEL", 1.0, TRUE, 0.40, TRUE, FALSE).

LOCAL vdPadErr IS VECDRAW(
    { RETURN SHIP:POSITION. },
    { RETURN (northAxis()*navErrN + eastAxis()*navErrE). },
    CYAN, "PAD", 1.0, TRUE, 0.38, TRUE, FALSE).

LOCAL vdTgtVel IS VECDRAW(
    { RETURN SHIP:POSITION. },
    { RETURN (northAxis()*(navErrN/MAX(1,navMiss)*bbTargetToward) + eastAxis()*(navErrE/MAX(1,navMiss)*bbTargetToward)) * 20. },
    WHITE, "TGT", 1.0, TRUE, 0.40, TRUE, FALSE).

// ------------------------------------------------------------
// Main setup
// ------------------------------------------------------------
RCS ON.
activateAG(2).
GEAR OFF.
logOpen().
updateNav().
updatePrediction().
logEvent("SCRIPT START terrainAlt:" + ROUND(padAlt,2)).

UNTIL FALSE {
    updateNav().
    updatePrediction().

    IF phase = PH_INIT {
        LOCAL tgoNow IS Clamp((navAgl + 3500) / MAX(120, ABS(SHIP:VERTICALSPEED)), 16, 42).
        LOCAL awayNow IS MAX(0, -navToward).
        LOCAL crossNow IS ABS(navCross).
        LOCAL planToward IS navMiss / tgoNow * 0.62 + awayNow*0.08 + crossNow*0.02.
        IF navMiss > 12000 { SET planToward TO planToward + 4. }
        ELSE IF navMiss > 8000 { SET planToward TO planToward + 2. }
        SET bbTargetToward TO Clamp(planToward, BOOST_TARGET_MIN, BOOST_TARGET_MAX).
        SET phase TO PH_FLIP.
        logEvent("INIT->FLIP miss:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0) + " tgtToward:" + ROUND(bbTargetToward,0) + " away:" + ROUND(awayNow,0)).
    }

    ELSE IF phase = PH_FLIP {
        LOCK STEERING TO HEADING(navPadBrg, FLIP_PITCH).
        LOCK THROTTLE TO 0.
        LOCAL flipErr IS VANG(SHIP:FACING:FOREVECTOR, HEADING(navPadBrg, FLIP_PITCH):FOREVECTOR).
        PRINT "[FLIP] err:" + ROUND(flipErr,1) + " brg:" + ROUND(navPadBrg,1) + " tgtTow:" + ROUND(bbTargetToward,0) + "      " AT (0,0).
        logPeriodic("flip err:" + ROUND(flipErr,1) + " brg:" + ROUND(navPadBrg,1)).

        IF flipErr < FLIP_TOL {
            SET bbStartTime   TO TIME:SECONDS.
            SET bbBestHs      TO navHs.
            SET bbBestToward  TO navToward.
            SET bbBestActMiss TO navMiss.
            SET bbMode        TO 0.
            SET phase TO PH_BOOSTBACK.
            logEvent("FLIP->BOOSTBACK brg:" + ROUND(navPadBrg,1) + " tgtToward:" + ROUND(bbTargetToward,0)).
        }
    }

    ELSE IF phase = PH_BOOSTBACK {
        // 3-state line-frame boostback:
        //   0 = REVERSE bad away-from-pad motion
        //   1 = ALIGN velocity onto the pad line (kill cross-track)
        //   2 = SET modest along-track speed, then cut
        LOCAL crossAbs IS ABS(navCross).
        LOCAL missNow  IS navMiss.
        LOCAL elapsed  IS TIME:SECONDS - bbStartTime.
        LOCAL headBias IS 0.
        LOCAL aimBrg   IS navPadBrg.
        LOCAL thrCmd   IS 0.0.
        LOCAL modeName IS "REV".

        IF navMiss < bbBestActMiss { SET bbBestActMiss TO navMiss. }
        IF navHs < bbBestHs { SET bbBestHs TO navHs. }
        IF navToward > bbBestToward { SET bbBestToward TO navToward. }

        // state transitions
        IF bbMode = 0 AND navToward >= BOOST_REVERSE_FLOOR {
            SET bbMode TO 1.
        }
        IF bbMode = 1 AND crossAbs <= BOOST_ALIGN_VEL AND navAlign > 0.96 {
            SET bbMode TO 2.
        }

        IF bbMode = 0 {
            SET modeName TO "REV".
            SET headBias TO Clamp((-navCross * 0.30) + SignNum(navCross) * crossAbs * 0.040, -BOOST_HEADING_MAX, BOOST_HEADING_MAX).
            SET aimBrg TO navPadBrg + headBias.

            IF navToward < -140 OR crossAbs > 80 {
                SET thrCmd TO 1.0.
            } ELSE IF navToward < -60 OR crossAbs > 35 {
                SET thrCmd TO 0.65.
            } ELSE {
                SET thrCmd TO 0.36.
            }
        }
        ELSE IF bbMode = 1 {
            SET modeName TO "ALIGN".
            SET headBias TO Clamp((-navCross * 0.28) + SignNum(navCross) * crossAbs * 0.030, -14, 14).
            SET aimBrg TO navPadBrg + headBias.

            IF crossAbs > 35 {
                SET thrCmd TO 0.42.
            } ELSE IF crossAbs > 16 {
                SET thrCmd TO 0.24.
            } ELSE IF navToward < bbTargetToward - 18 {
                SET thrCmd TO 0.10.
            } ELSE {
                SET thrCmd TO 0.0.
            }
        }
        ELSE {
            SET modeName TO "SET".
            SET headBias TO Clamp(-navCross * 0.16, -7, 7).
            SET aimBrg TO navPadBrg + headBias.

            IF navToward < bbTargetToward - 22 {
                SET thrCmd TO 0.20.
            } ELSE IF navToward < bbTargetToward - 12 {
                SET thrCmd TO 0.10.
            } ELSE IF navToward < bbTargetToward - BOOST_TOWARD_BAND {
                SET thrCmd TO 0.04.
            } ELSE {
                SET thrCmd TO 0.0.
            }

            IF crossAbs > BOOST_ALIGN_VEL {
                SET bbMode TO 1.
            }
        }

        LOCK STEERING TO HEADING(aimBrg, FLIP_PITCH).
        LOCK THROTTLE TO thrCmd.

        PRINT "[BOOST:" + modeName + "] act:" + ROUND(navMiss,0)
            + " hs:" + ROUND(navHs,0)
            + " toward:" + ROUND(navToward,0)
            + " tgt:" + ROUND(bbTargetToward,0)
            + " cross:" + ROUND(navCross,0)
            + " aln:" + ROUND(navAlign,2)
            + " aim:" + ROUND(aimBrg,1) + "      " AT (0,1).

        logPeriodic(
            "boost " + modeName
          + " act:" + ROUND(navMiss,0)
          + " hs:" + ROUND(navHs,0)
          + " toward:" + ROUND(navToward,0)
          + " tgt:" + ROUND(bbTargetToward,0)
          + " cross:" + ROUND(navCross,0)
          + " aln:" + ROUND(navAlign,2)
          + " aim:" + ROUND(aimBrg,1)
          + " " + nsText(navErrN)
          + " " + ewText(navErrE)
        ).

        SET bbExitReason TO "".
        // success: velocity lies on pad line and carries only modest padward speed
        IF bbMode = 2
           AND elapsed > BOOST_MIN_TIME
           AND crossAbs <= BOOST_ALIGN_VEL
           AND navAlign > BOOST_ALIGN_DOT
           AND navToward >= bbTargetToward - BOOST_TOWARD_BAND
           AND navToward <= bbTargetToward + 4 {
            SET bbExitReason TO "line+speed solved toward:" + ROUND(navToward,0) + " tgt:" + ROUND(bbTargetToward,0) + " cross:" + ROUND(navCross,0).
        }
        // safety: aligned but already too fast, cut rather than chase through
        ELSE IF bbMode = 2
           AND elapsed > BOOST_MIN_TIME
           AND crossAbs <= BOOST_ALIGN_VEL
           AND navAlign > 0.97
           AND navToward > bbTargetToward + 4 {
            SET bbExitReason TO "aligned overspeed cut toward:" + ROUND(navToward,0) + " tgt:" + ROUND(bbTargetToward,0) + " cross:" + ROUND(navCross,0).
        }
        ELSE IF elapsed > BOOST_MAX_TIME
           AND bbMode = 2
           AND (navToward >= bbTargetToward - 18 OR crossAbs > 40) {
            SET bbExitReason TO "max boost time mode:" + modeName + " hs:" + ROUND(navHs,0) + " toward:" + ROUND(navToward,0) + " cross:" + ROUND(navCross,0) + " tgt:" + ROUND(bbTargetToward,0).
        }
        ELSE IF elapsed > 70 {
            SET bbExitReason TO "hard safety timeout mode:" + modeName + " hs:" + ROUND(navHs,0) + " toward:" + ROUND(navToward,0) + " cross:" + ROUND(navCross,0) + " tgt:" + ROUND(bbTargetToward,0).
        }

        IF bbExitReason <> "" {
            UNLOCK THROTTLE.
            LOCK THROTTLE TO 0.
            UNLOCK STEERING.
            SET phase TO PH_COAST.
            logEvent("BOOSTBACK->COAST " + bbExitReason).
        }
    }

    ELSE IF phase = PH_COAST {
        LOCK THROTTLE TO 0.
        // modest tail-down trim: mostly damp velocity, slight pad pull
        LOCAL corrN IS (-navVelN * 0.65) + (navErrN * NS_WEIGHT_COAST / MAX(1, navMiss) * 0.35 * navHs).
        LOCAL corrE IS (-navVelE * 0.65) + (navErrE / MAX(1, navMiss) * 0.35 * navHs).
        LOCK STEERING TO tailDownDir(corrN, corrE, COAST_LEAN_DEG).

        IF NOT coastFinsOut AND (SHIP:ALTITUDE < COAST_FIN_ALT OR SHIP:VERTICALSPEED <= 0) {
            activateAG(1).
            setFinAuthority(18).
            SET coastFinsOut TO TRUE.
            logEvent("Fins deployed auth:18").
        }

        IF SHIP:VERTICALSPEED <= 0 { SET coastApoSeen TO TRUE. }

        PRINT "[COAST] act:" + ROUND(navMiss,0)
            + " pred:" + ROUND(SQRT(predErrN^2 + predErrE^2),0)
            + " hs:" + ROUND(navHs,0)
            + " " + nsText(navErrN)
            + " " + ewText(navErrE) + "     " AT (0,2).

        logPeriodic("coast act:" + ROUND(navMiss,0) + " pred:" + ROUND(SQRT(predErrN^2 + predErrE^2),0) + " hs:" + ROUND(navHs,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).

        IF coastApoSeen AND SHIP:ALTITUDE < ENTRY_TRIGGER_ALT AND SHIP:VERTICALSPEED < -250 {
            SET entryStartTime TO TIME:SECONDS.
            SET phase TO PH_ENTRY.
            logEvent("COAST->ENTRY alt:" + ROUND(SHIP:ALTITUDE,0) + " spd:" + ROUND(navSrfSpd,0) + " act:" + ROUND(navMiss,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).
        }
    }

    ELSE IF phase = PH_ENTRY {
        // modest desired padward velocity, stronger than pure damping
        LOCAL tgoEntry IS Clamp(navAgl / MAX(120, ABS(SHIP:VERTICALSPEED)), 8, 26).
        LOCAL wantTow  IS Clamp(navMiss / tgoEntry + MAX(0, -navToward)*0.30, 70, 220).
        LOCAL tgtVN    IS navErrN / MAX(1,navMiss) * wantTow.
        LOCAL tgtVE    IS navErrE / MAX(1,navMiss) * wantTow.
        LOCAL dvN      IS tgtVN - navVelN.
        LOCAL dvE      IS tgtVE - navVelE.
        LOCAL corrN    IS dvN * 0.72 + navErrN * NS_WEIGHT_ENTRY / MAX(1,navMiss) * 0.28 * navHs.
        LOCAL corrE    IS dvE * 0.72 + navErrE / MAX(1,navMiss) * 0.28 * navHs.
        LOCAL thrEntry IS 0.0.

        LOCK STEERING TO tailDownDir(corrN, corrE, ENTRY_LEAN_DEG).
        RCS ON.
        IF coastFinsOut { setFinAuthority(22). }

        IF navSrfSpd > ENTRY_END_SPEED + 220 { SET thrEntry TO 1.0. }
        ELSE IF navSrfSpd > ENTRY_END_SPEED + 120 { SET thrEntry TO 0.85. }
        ELSE IF navSrfSpd > ENTRY_END_SPEED + 50 { SET thrEntry TO 0.60. }
        ELSE IF navMiss > 4500 AND navHs > 35 { SET thrEntry TO 0.35. }
        ELSE IF navMiss > 3000 AND navHs > 25 { SET thrEntry TO 0.18. }
        LOCK THROTTLE TO thrEntry.

        PRINT "[ENTRY] spd:" + ROUND(navSrfSpd,0)
            + " act:" + ROUND(navMiss,0)
            + " hs:" + ROUND(navHs,0)
            + " agl:" + ROUND(navAgl,0) + "      " AT (0,3).

        logPeriodic("entry spd:" + ROUND(navSrfSpd,0) + " act:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).

        IF (TIME:SECONDS - entryStartTime > ENTRY_MIN_TIME AND navSrfSpd <= ENTRY_END_SPEED + 8)
           OR (TIME:SECONDS - entryStartTime > ENTRY_MAX_TIME)
           OR (SHIP:ALTITUDE < 15000 AND navSrfSpd < ENTRY_END_SPEED + 40) {
            LOCK THROTTLE TO 0.
            SET phase TO PH_AERO.
            logEvent("ENTRY->AERO spd:" + ROUND(navSrfSpd,0) + " act:" + ROUND(navMiss,0) + " agl:" + ROUND(navAgl,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).
        }
    }

    ELSE IF phase = PH_AERO {
        LOCAL tgoAero IS Clamp(navAgl / MAX(90, ABS(SHIP:VERTICALSPEED)), 5, 18).
        LOCAL wantTowA IS Clamp(navMiss / tgoAero + MAX(0, -navToward)*0.28, 28, 150).
        LOCAL tgtVNA   IS navErrN / MAX(1,navMiss) * wantTowA.
        LOCAL tgtVEA   IS navErrE / MAX(1,navMiss) * wantTowA.
        LOCAL dvNA     IS tgtVNA - navVelN.
        LOCAL dvEA     IS tgtVEA - navVelE.
        LOCAL aeroScale IS Clamp(navAgl / 6500, 0.45, 1.0).
        LOCAL termHoldA IS (navMiss < 1200 OR navAgl < 7000).
        LOCAL corrNA   IS 0.
        LOCAL corrEA   IS 0.
        LOCAL aeroLean IS AERO_LEAN_DEG * aeroScale.
        LOCAL ignNow   IS landingIgnitionAGL().

        IF termHoldA {
            SET corrNA TO (-navVelN * 2.55) + navErrN * 0.30.
            SET corrEA TO (-navVelE * 2.55) + navErrE * 0.30.
            SET aeroLean TO MAX(18, aeroLean).
        } ELSE {
            SET corrNA TO (dvNA * 0.50 + navErrN * NS_WEIGHT_AERO / MAX(1,navMiss) * 0.50 * navHs) * aeroScale.
            SET corrEA TO (dvEA * 0.50 + navErrE / MAX(1,navMiss) * 0.50 * navHs) * aeroScale.
        }

        LOCK THROTTLE TO 0.
        LOCK STEERING TO tailDownDir(corrNA, corrEA, aeroLean).

        IF NOT aeroRcsOn AND navMiss > 2500 {
            RCS ON.
            SET aeroRcsOn TO TRUE.
        }
        IF aeroRcsOn AND navMiss < 1800 AND navHs < 80 {
            RCS OFF.
            SET aeroRcsOn TO FALSE.
        }
        IF coastFinsOut {
            IF navAgl > 7000 { setFinAuthority(30). }
            ELSE IF navAgl > 2500 { setFinAuthority(20). }
            ELSE { setFinAuthority(10). }
        }

        PRINT "[AERO] act:" + ROUND(navMiss,0)
            + " pred:" + ROUND(SQRT(predErrN^2 + predErrE^2),0)
            + " hs:" + ROUND(navHs,0)
            + " ign:" + ROUND(ignNow,0)
            + " agl:" + ROUND(navAgl,0) + "      " AT (0,4).

        logPeriodic("aero act:" + ROUND(navMiss,0) + " pred:" + ROUND(SQRT(predErrN^2 + predErrE^2),0) + " hs:" + ROUND(navHs,0) + " ign:" + ROUND(ignNow,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).

        IF NOT legsOut {
            LOCAL ttdGearA IS navAgl / MAX(25, ABS(SHIP:VERTICALSPEED)).
            IF ((ttdGearA <= 3.2 AND navAgl < 1200) OR navAgl <= 350) {
                GEAR ON.
                SET legsOut TO TRUE.
                logEvent("GEAR ON agl:" + ROUND(navAgl,0) + " ttd:" + ROUND(ttdGearA,1) + " act:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0)).
            }
        }

        IF navAgl <= ignNow + 1400 {
            UNLOCK STEERING.
            SET landingStartTime TO TIME:SECONDS.
            SET landingHoldLatched TO FALSE.
            SET phase TO PH_LANDING.
            logEvent("AERO->LANDING agl:" + ROUND(navAgl,0) + " ign:" + ROUND(ignNow,0) + " act:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0)).
        }
    }

    ELSE IF phase = PH_LANDING {
        LOCAL holdPad    IS landingHoldLatched.
        LOCAL shortT     IS 0.
        LOCAL aimErrN    IS navErrN.
        LOCAL aimErrE    IS navErrE.
        LOCAL aimMiss    IS navMiss.
        LOCAL tgtVNL     IS 0.
        LOCAL tgtVEL     IS 0.
        LOCAL corrNL     IS 0.
        LOCAL corrEL     IS 0.
        LOCAL desiredVsL IS 0.
        LOCAL thrLand    IS 0.
        LOCAL landLean   IS 34.
        LOCAL ttdNow     IS navAgl / MAX(18, ABS(SHIP:VERTICALSPEED)).
        LOCAL posTau     IS 0.
        LOCAL cpaT       IS 0.
        LOCAL cpaN       IS 0.
        LOCAL cpaE       IS 0.
        LOCAL cpaMiss    IS navMiss.
        LOCAL radialVel  IS 0.
        LOCAL lockRad    IS 0.

        IF navMiss > 0.1 {
            SET radialVel TO (navErrN*navVelN + navErrE*navVelE) / navMiss.
        }
        IF navHs > 1 {
            SET cpaT TO Clamp(-(navErrN*navVelN + navErrE*navVelE) / MAX(1, navHs^2), 0, 2.0).
            SET cpaN TO navErrN + navVelN * cpaT.
            SET cpaE TO navErrE + navVelE * cpaT.
            SET cpaMiss TO SQRT(cpaN^2 + cpaE^2).
        }

        // Real-time over-pad lock using actual pad error, not the laggy predictor.
        SET lockRad TO Clamp(140 + navHs * 1.8, 140, 260).
        IF NOT landingHoldLatched AND (navMiss < lockRad OR (cpaMiss < 70 AND cpaT < 1.6) OR (navMiss < 220 AND radialVel > -6)) {
            SET landingHoldLatched TO TRUE.
            SET holdPad TO TRUE.
        }

        IF holdPad {
            SET aimErrN TO navErrN.
            SET aimErrE TO navErrE.
            SET aimMiss TO navMiss.

            // Once we're over the pad enough, stop chasing and kill lateral velocity.
            IF navAgl > 1200 { SET desiredVsL TO -110. }
            ELSE IF navAgl > 600 { SET desiredVsL TO -70. }
            ELSE IF navAgl > 250 { SET desiredVsL TO -32. }
            ELSE IF navAgl > 100 { SET desiredVsL TO -10. }
            ELSE { SET desiredVsL TO -4.0. }

            IF navMiss < 120 {
                SET tgtVNL TO 0.
                SET tgtVEL TO 0.
                SET corrNL TO (-navVelN) * 34.0 + Clamp(-navErrN * 0.05, -2.0, 2.0).
                SET corrEL TO (-navVelE) * 34.0 + Clamp(-navErrE * 0.05, -2.0, 2.0).
                IF navAgl > 600 { SET landLean TO 8. }
                ELSE IF navAgl > 200 { SET landLean TO 5. }
                ELSE { SET landLean TO 3. }
            } ELSE {
                SET tgtVNL TO Clamp(-navErrN * 0.02, -1.5, 1.5).
                SET tgtVEL TO Clamp(-navErrE * 0.02, -1.5, 1.5).
                SET corrNL TO (tgtVNL - navVelN) * 28.0 + Clamp(-navErrN * 0.08, -3, 3).
                SET corrEL TO (tgtVEL - navVelE) * 28.0 + Clamp(-navErrE * 0.08, -3, 3).
                IF navAgl > 600 { SET landLean TO 12. }
                ELSE IF navAgl > 250 { SET landLean TO 8. }
                ELSE { SET landLean TO 5. }
            }
        } ELSE {
            // Before lock, keep a short lead and come in hard.
            SET shortT TO Clamp(0.9 + navHs * 0.015, 0.8, 1.6).
            SET aimErrN TO navErrN - navVelN * shortT.
            SET aimErrE TO navErrE - navVelE * shortT.
            SET aimMiss TO SQRT(aimErrN^2 + aimErrE^2).

            IF navAgl > 2200 {
                SET posTau TO 2.2.
                SET desiredVsL TO -140.
                SET landLean TO 28.
                SET tgtVNL TO Clamp(-aimErrN / posTau, -24, 24).
                SET tgtVEL TO Clamp(-aimErrE / posTau, -24, 24).
                SET corrNL TO (tgtVNL - navVelN) * 19.0.
                SET corrEL TO (tgtVEL - navVelE) * 19.0.
            } ELSE IF navAgl > 1200 {
                SET posTau TO 1.8.
                SET desiredVsL TO -110.
                SET landLean TO 22.
                SET tgtVNL TO Clamp(-aimErrN / posTau, -18, 18).
                SET tgtVEL TO Clamp(-aimErrE / posTau, -18, 18).
                SET corrNL TO (tgtVNL - navVelN) * 20.0.
                SET corrEL TO (tgtVEL - navVelE) * 20.0.
            } ELSE {
                SET posTau TO 1.3.
                SET desiredVsL TO -78.
                SET landLean TO 18.
                SET tgtVNL TO Clamp(-aimErrN / posTau, -12, 12).
                SET tgtVEL TO Clamp(-aimErrE / posTau, -12, 12).
                SET corrNL TO (tgtVNL - navVelN) * 22.0.
                SET corrEL TO (tgtVEL - navVelE) * 22.0.
            }
        }

        SET thrLand TO landingThrottleCmd(desiredVsL).
        IF SHIP:VERTICALSPEED < desiredVsL - 20 { SET thrLand TO MAX(thrLand, 0.95). }
        ELSE IF SHIP:VERTICALSPEED < desiredVsL - 8 { SET thrLand TO MAX(thrLand, 0.70). }

        // Never hover or climb in LANDING.
        IF SHIP:VERTICALSPEED > 2 AND navAgl > 60 {
            SET thrLand TO 0.
        } ELSE IF SHIP:VERTICALSPEED > desiredVsL + 6 AND navAgl > 100 {
            SET thrLand TO MIN(thrLand, 0.05).
        }

        // Keep some throttle for steering while any lateral cleanup remains.
        IF navAgl > 120 AND (navHs > 2 OR navMiss > 12) {
            SET thrLand TO MAX(thrLand, 0.18).
        }

        RCS ON.
        IF NOT legsOut AND (navAgl < 260 OR ttdNow <= 4.0) {
            GEAR ON.
            SET legsOut TO TRUE.
            logEvent("GEAR ON agl:" + ROUND(navAgl,0) + " ttd:" + ROUND(ttdNow,1) + " act:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0)).
        }
        LOCK STEERING TO tailDownDir(corrNL, corrEL, landLean).
        LOCK THROTTLE TO thrLand.
        IF coastFinsOut { setFinAuthority(0). }

        PRINT "[LAND] act:" + ROUND(navMiss,0)
            + " cpa:" + ROUND(cpaMiss,0)
            + " hs:" + ROUND(navHs,0)
            + " vs:" + ROUND(SHIP:VERTICALSPEED,0)
            + " tvs:" + ROUND(desiredVsL,0)
            + " thr:" + ROUND(thrLand*100,0)
            + " agl:" + ROUND(navAgl,0) + "      " AT (0,5).

        logPeriodic("land act:" + ROUND(navMiss,0) + " aim:" + ROUND(aimMiss,0) + " cpa:" + ROUND(cpaMiss,0) + " rv:" + ROUND(radialVel,0) + " hs:" + ROUND(navHs,0) + " vs:" + ROUND(SHIP:VERTICALSPEED,0) + " tvs:" + ROUND(desiredVsL,0) + " thr:" + ROUND(thrLand*100,0) + " st:" + ROUND(shortT,1) + " hold:" + holdPad + " " + nsText(navErrN) + " " + ewText(navErrE)).

        IF navAgl <= TOUCHDOWN_AGL {
            SET touchStartTime TO TIME:SECONDS.
            SET phase TO PH_TOUCH.
            logEvent("LANDING->TOUCH agl:" + ROUND(navAgl,0) + " act:" + ROUND(navMiss,0) + " hs:" + ROUND(navHs,0)).
        }
    }

    ELSE IF phase = PH_TOUCH {
        LOCAL aimErrNT   IS navErrN.
        LOCAL aimErrET   IS navErrE.
        LOCAL aimMissT   IS SQRT(aimErrNT^2 + aimErrET^2).
        LOCAL tgtVNT     IS Clamp(-aimErrNT * 0.08, -1.5, 1.5).
        LOCAL tgtVET     IS Clamp(-aimErrET * 0.08, -1.5, 1.5).
        LOCAL corrNT     IS (tgtVNT - navVelN) * 26.0 + Clamp(-aimErrNT * 0.20, -4, 4).
        LOCAL corrET     IS (tgtVET - navVelE) * 26.0 + Clamp(-aimErrET * 0.20, -4, 4).
        LOCAL desiredVsT IS -Clamp(0.9 + navHs * 0.03, 0.8, 2.0).
        LOCAL thrTouch   IS landingThrottleCmd(desiredVsT).

        IF SHIP:VERTICALSPEED < desiredVsT - 1.0 { SET thrTouch TO MAX(thrTouch, 0.26). }
        IF SHIP:VERTICALSPEED > 0.10 AND navAgl > 2 { SET thrTouch TO 0. }

        RCS ON.
        GEAR ON.
        SET legsOut TO TRUE.
        LOCK STEERING TO tailDownDir(corrNT, corrET, 8).
        LOCK THROTTLE TO thrTouch.
        IF coastFinsOut { setFinAuthority(0). }

        PRINT "[TOUCH] act:" + ROUND(navMiss,0)
            + " aim:" + ROUND(aimMissT,0)
            + " hs:" + ROUND(navHs,0)
            + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
            + " thr:" + ROUND(thrTouch*100,0)
            + " agl:" + ROUND(navAgl,0) + "      " AT (0,6).

        logPeriodic("touch act:" + ROUND(navMiss,0) + " aim:" + ROUND(aimMissT,0) + " hs:" + ROUND(navHs,0) + " vs:" + ROUND(SHIP:VERTICALSPEED,1) + " thr:" + ROUND(thrTouch*100,0) + " " + nsText(navErrN) + " " + ewText(navErrE)).

        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" OR (navAgl < 8 AND ABS(SHIP:VERTICALSPEED) < 2 AND navHs < 1.0) {
            SET phase TO PH_DONE.
            logEvent("TOUCH->DONE agl:" + ROUND(navAgl,1) + " hs:" + ROUND(navHs,1) + " vs:" + ROUND(SHIP:VERTICALSPEED,1)).
        }
    }

    ELSE IF phase = PH_DONE {
        RCS OFF.
        LOCK THROTTLE TO 0.
        PRINT "Phase-3 flattened complete." AT (0,7).
        BREAK.
    }

    WAIT 0.05.
}

UNLOCK STEERING.
UNLOCK THROTTLE.
LOCK THROTTLE TO 0.
RCS OFF.
logEvent("SCRIPT END").
