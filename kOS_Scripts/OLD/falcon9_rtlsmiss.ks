// ============================================================
//  falcon9_rtls_simplified.ks
//  Simplified RTLS guidance for Kerbal-scale Falcon-style booster
//
//  Design goals:
//    * keep launch-script pad handoff exactly as-is
//    * one phase, one job
//    * no terminal RCS chase logic
//    * no 3-engine -> 1-engine switch
//    * no dynamic boostback aimpoint chasing
//
//  Usage:
//    RUN falcon9_rtls_simplified(PAD_LAT, PAD_LNG, PAD_ALT).
//
//  Action Groups:
//    AG1  Grid fins deploy
//    AG2  Enable 3 center engines
//    AG3  Optional / unused in this script
//    GEAR Landing legs
// ============================================================

@LAZYGLOBAL OFF.

// ============================================================
//  PAD PARAMETERS
//  These are defaults only. Your launch script can pass real values.
// ============================================================
PARAMETER PAD_LAT IS -0.0972.
PARAMETER PAD_LNG IS -74.5577.
PARAMETER PAD_ALT IS 67.

// ============================================================
//  TUNING
//  Keep this list short on purpose.
// ============================================================
LOCAL KERBIN_M_PER_DEG IS 10471.
LOCAL LOG_FILE         IS "0:/rtls_log.txt".
LOCAL LOG_INTERVAL     IS 2.0.

// Boostback
LOCAL BB_PRED_INTERVAL IS 0.5.
LOCAL BB_NORTH_BIAS_M  IS 670.
LOCAL BB_WEST_BIAS_M   IS 1600.
LOCAL BB_STOP_EAST_M   IS 300.
LOCAL BB_FULL_EAST_M   IS -12000.
LOCAL BB_MID_EAST_M    IS -4000.
LOCAL BB_LOW_EAST_M    IS -1000.
LOCAL BB_MAX_TIME      IS 90.
LOCAL PAD_TRIM_NORTH_M IS 109.
LOCAL PAD_TRIM_EAST_M  IS -60.

// Entry and fins
LOCAL ENTRY_ALT        IS 40000.
LOCAL ENTRY_END_SPEED  IS 320.
LOCAL FIN_AUTH_COAST   IS 15.
LOCAL FIN_AUTH_AERO    IS 35.
LOCAL FIN_AUTH_LAND    IS 8.
LOCAL LEAN_MAX_DEG     IS 4.
LOCAL LEAN_FULL_KM     IS 2.5.
LOCAL LEAN_FADE_KM     IS 0.5.

// Landing
LOCAL LEG_DEPLOY_ALT   IS 500.
LOCAL LAND_GUIDE_ALT   IS 250.
LOCAL LAND_UP_BIAS_ACC IS 21.0.
LOCAL LAND_POS_KP      IS 0.020.
LOCAL LAND_POS_KP_LOW  IS 0.008.
LOCAL LAND_MAX_VEL     IS 8.0.
LOCAL LAND_MAX_VEL_LOW IS 3.0.
LOCAL LAND_VEL_KP      IS 0.18.
LOCAL LAND_VEL_KP_LOW  IS 0.24.
LOCAL LAND_MAX_ACC     IS 7.0.
LOCAL LAND_MAX_ACC_LOW IS 3.0.
LOCAL LAND_MAX_TILT    IS 14.0.
LOCAL LAND_MAX_TILT_LOW IS 6.0.
LOCAL LAND_THR_KP      IS 0.60.
LOCAL LAND_THR_KP_LOW  IS 0.90.
LOCAL TOUCHDOWN_VS     IS -3.5.
LOCAL TOUCHDOWN_HS     IS 2.5.
LOCAL vesselBounds     IS SHIP:BOUNDS.

// ============================================================
//  PHASE IDS
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
//  STATE
// ============================================================
LOCAL phase        IS PH_FLIP.
LOCAL padGeo       IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL activePadGeo IS padGeo.
LOCAL lastPredTime IS -999.
LOCAL cachedImpact IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL lastLogTime  IS -999.
LOCAL bbStartTime  IS 0.
LOCAL finsOut      IS FALSE.
LOCAL finsAeroSet  IS FALSE.
LOCAL finsLandSet  IS FALSE.
LOCAL legsOut      IS FALSE.
LOCAL touchdownSeen IS FALSE.

// ============================================================
//  UTILITY
// ============================================================
FUNCTION Clamp {
    PARAMETER valueIn, lowIn, highIn.
    IF valueIn < lowIn { RETURN lowIn. }
    IF valueIn > highIn { RETURN highIn. }
    RETURN valueIn.
}

FUNCTION distKm {
    PARAMETER geoA, geoB.
    RETURN (geoA:POSITION - geoB:POSITION):MAG / 1000.
}

FUNCTION bearingTo {
    PARAMETER targetGeo.
    LOCAL latNow IS SHIP:GEOPOSITION:LAT.
    LOCAL brngDeg IS ARCTAN2(
        (targetGeo:LNG - SHIP:GEOPOSITION:LNG) * COS(latNow),
        targetGeo:LAT - latNow
    ).
    IF brngDeg < 0 { SET brngDeg TO brngDeg + 360. }
    RETURN brngDeg.
}

FUNCTION hSpeed {
    RETURN SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2 - SHIP:VERTICALSPEED^2)).
}

FUNCTION terrainAGL {
    LOCAL altRadar IS vesselBounds:BOTTOMALTRADAR.
    IF altRadar < 0 { RETURN 0. }
    RETURN altRadar.
}

FUNCTION rotVec {
    PARAMETER vecIn, axisIn, angleDeg.
    LOCAL cosA IS COS(angleDeg).
    LOCAL sinA IS SIN(angleDeg).
    RETURN vecIn * cosA + VCRS(axisIn, vecIn) * sinA
           + axisIn * VDOT(axisIn, vecIn) * (1 - cosA).
}

FUNCTION northErrM {
    PARAMETER targetGeo.
    RETURN (targetGeo:LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
}

FUNCTION eastErrM {
    PARAMETER targetGeo.
    RETURN (targetGeo:LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG * COS(SHIP:LATITUDE).
}

FUNCTION nsText {
    PARAMETER northMeters.
    IF northMeters >= 0 { RETURN "N:" + ROUND(northMeters,0). }
    RETURN "S:" + ROUND(ABS(northMeters),0).
}

FUNCTION ewText {
    PARAMETER eastMeters.
    IF eastMeters >= 0 { RETURN "E:" + ROUND(eastMeters,0). }
    RETURN "W:" + ROUND(ABS(eastMeters),0).
}

// ============================================================
//  LOGGING
// ============================================================
FUNCTION logOpen {
    IF EXISTS(LOG_FILE) { DELETEPATH(LOG_FILE). }
    LOG "RTLS Log - Pad: " + PAD_LAT + " / " + PAD_LNG + " / " + PAD_ALT TO LOG_FILE.
    LOG "T+sec | Phase | Alt km | VS m/s | Hspd m/s | Pad km | Thr% | Message" TO LOG_FILE.
    LOG "----------------------------------------------------------------------" TO LOG_FILE.
}

FUNCTION logLine {
    PARAMETER msgText.
    LOCAL tsVal  IS ROUND(TIME:SECONDS, 1).
    LOCAL altKm  IS ROUND(SHIP:ALTITUDE / 1000, 2).
    LOCAL vsVal  IS ROUND(SHIP:VERTICALSPEED, 1).
    LOCAL hsVal  IS ROUND(hSpeed(), 1).
    LOCAL padVal IS ROUND(distKm(SHIP:GEOPOSITION, padGeo), 2).
    LOCAL thrVal IS ROUND(THROTTLE * 100, 0).
    LOCAL phName IS PHASE_NAMES[phase].

    LOG "T+" + tsVal + " | " + phName + " | " + altKm + "km | VS:" + vsVal
        + " | H:" + hsVal + " | Pad:" + padVal + "km | Thr:" + thrVal
        + "% | " + msgText TO LOG_FILE.
}

FUNCTION logEvent {
    PARAMETER msgText.
    logLine("*** " + msgText + " ***").
}

FUNCTION logPeriodic {
    PARAMETER msgText IS "".
    IF (TIME:SECONDS - lastLogTime) >= LOG_INTERVAL {
        logLine(msgText).
        SET lastLogTime TO TIME:SECONDS.
    }
}

// ============================================================
//  ACTION GROUPS AND PART HELPERS
// ============================================================
FUNCTION activateAG {
    PARAMETER agNum.
    IF agNum = 1 { AG1 ON. }
    ELSE IF agNum = 2 { AG2 ON. }
    ELSE IF agNum = 3 { AG3 ON. }
    ELSE IF agNum = 4 { AG4 ON. }
    ELSE IF agNum = 5 { AG5 ON. }
}

FUNCTION setFinAuthority {
    PARAMETER authPct.
    FOR partItem IN SHIP:PARTS {
        IF partItem:HASMODULE("ModuleControlSurface") {
            LOCAL finMod IS partItem:GETMODULE("ModuleControlSurface").
            IF finMod:HASFIELD("authority limiter") {
                finMod:SETFIELD("authority limiter", authPct).
            }
        }
    }
}

// ============================================================
//  BALLISTIC PREDICTOR
//  Vacuum only. Use for boostback cutoff only.
// ============================================================
FUNCTION predictImpact {
    LOCAL muVal    IS BODY:MU.
    LOCAL bodyRad  IS BODY:RADIUS.
    LOCAL bodyPos0 IS BODY:POSITION.
    LOCAL posVec   IS -bodyPos0.
    LOCAL velOrb   IS SHIP:VELOCITY:ORBIT.
    LOCAL rotPer   IS BODY:ROTATIONPERIOD.
    LOCAL rotAxis  IS V(0, 1, 0).

    IF BODY:ANGULARVEL:MAG > 0.000001 {
        SET rotAxis TO BODY:ANGULARVEL:NORMALIZED.
    }

    LOCAL dtVal IS 5.
    LOCAL tofVal IS 0.

    UNTIL tofVal > 1500 {
        LOCAL posMag IS posVec:MAG.
        LOCAL accVec IS -(muVal / (posMag^3)) * posVec.
        LOCAL posMid IS posVec + velOrb * (dtVal / 2).
        LOCAL velMid IS velOrb + accVec * (dtVal / 2).
        LOCAL accMid IS -(muVal / (posMid:MAG^3)) * posMid.

        SET posVec TO posVec + velMid * dtVal.
        SET velOrb TO velOrb + accMid * dtVal.
        SET tofVal TO tofVal + dtVal.

        IF posVec:MAG - bodyRad <= PAD_ALT {
            LOCAL rotDeg IS 360 * tofVal / rotPer.
            LOCAL posAdj IS rotVec(posVec, rotAxis, -rotDeg).
            RETURN BODY:GEOPOSITIONOF(posAdj + bodyPos0).
        }
    }

    RETURN SHIP:GEOPOSITION.
}

FUNCTION getImpact {
    IF (TIME:SECONDS - lastPredTime) >= BB_PRED_INTERVAL {
        SET cachedImpact TO predictImpact().
        SET lastPredTime TO TIME:SECONDS.
    }
    RETURN cachedImpact.
}

// ============================================================
//  TARGETS
// ============================================================
FUNCTION boostbackAimGeo {
    LOCAL lngScale IS KERBIN_M_PER_DEG * MAX(0.20, COS(PAD_LAT)).
    LOCAL aimLat   IS PAD_LAT + BB_NORTH_BIAS_M / KERBIN_M_PER_DEG.
    LOCAL aimLng   IS PAD_LNG - BB_WEST_BIAS_M / lngScale.
    RETURN LATLNG(aimLat, aimLng).
}

FUNCTION finalPadGeo {
    LOCAL lngScale IS KERBIN_M_PER_DEG * MAX(0.20, COS(PAD_LAT)).
    RETURN LATLNG(
        PAD_LAT + PAD_TRIM_NORTH_M / KERBIN_M_PER_DEG,
        PAD_LNG + PAD_TRIM_EAST_M  / lngScale
    ).
}

FUNCTION finSteerDir {
    PARAMETER padDistKmIn.

    LOCAL srfRetroVec IS SHIP:SRFRETROGRADE:FOREVECTOR.
    IF padDistKmIn < LEAN_FADE_KM OR terrainAGL() < 1500 {
        RETURN LOOKDIRUP(srfRetroVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL leanFrac IS Clamp(
        (padDistKmIn - LEAN_FADE_KM) / (LEAN_FULL_KM - LEAN_FADE_KM),
        0, 1
    ).
    LOCAL leanDeg IS LEAN_MAX_DEG * leanFrac.
    IF leanDeg < 0.1 {
        RETURN LOOKDIRUP(srfRetroVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL padBrng IS bearingTo(activePadGeo).
    LOCAL toPadVec IS HEADING(padBrng, 0):FOREVECTOR.
    LOCAL leanVec IS toPadVec - VDOT(toPadVec, srfRetroVec) * srfRetroVec.

    IF leanVec:MAG < 0.001 {
        RETURN LOOKDIRUP(srfRetroVec, SHIP:FACING:TOPVECTOR).
    }

    SET leanVec TO leanVec:NORMALIZED * SIN(leanDeg).
    LOCAL aimVec IS (srfRetroVec + leanVec):NORMALIZED.
    RETURN LOOKDIRUP(aimVec, SHIP:FACING:TOPVECTOR).
}

// ============================================================
//  LANDING GUIDANCE
// ============================================================
FUNCTION ignitionAlt {
    LOCAL vertSpd   IS MAX(0, -SHIP:VERTICALSPEED).
    LOCAL gravAccel IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL aMax      IS (MAXTHRUST / SHIP:MASS) - gravAccel.

    IF aMax < 0.5 { RETURN 5000. }

    // Later start than before, but still continuous and stable
    RETURN (vertSpd * vertSpd) / (2 * aMax) * 0.88 + 30.
}

FUNCTION landingGuideDir {
    LOCAL altAGL IS terrainAGL().
    LOCAL upVec  IS UP:FOREVECTOR.
    LOCAL hsVal  IS hSpeed().
    LOCAL padMeters IS distKm(SHIP:GEOPOSITION, activePadGeo) * 1000.

    IF altAGL < LAND_GUIDE_ALT OR (padMeters < 25 AND hsVal < 1.0) {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL posKpVal   IS LAND_POS_KP.
    LOCAL maxVelVal  IS LAND_MAX_VEL.
    LOCAL velKpVal   IS LAND_VEL_KP.
    LOCAL maxAccVal  IS LAND_MAX_ACC.
    LOCAL maxTiltVal IS LAND_MAX_TILT.

    IF altAGL < 600 {
        SET posKpVal   TO LAND_POS_KP_LOW.
        SET maxVelVal  TO LAND_MAX_VEL_LOW.
        SET velKpVal   TO LAND_VEL_KP_LOW.
        SET maxAccVal  TO LAND_MAX_ACC_LOW.
        SET maxTiltVal TO LAND_MAX_TILT_LOW.
    }

    LOCAL northAxis IS HEADING(0, 0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90, 0):FOREVECTOR.

    LOCAL northPosErr IS northErrM(activePadGeo).
    LOCAL eastPosErr  IS eastErrM(activePadGeo).
    LOCAL northVelVal IS VDOT(SHIP:VELOCITY:SURFACE, northAxis).
    LOCAL eastVelVal  IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    LOCAL desNorthVel IS Clamp(northPosErr * posKpVal, -maxVelVal, maxVelVal).
    LOCAL desEastVel  IS Clamp(eastPosErr  * posKpVal, -maxVelVal, maxVelVal).

    IF ABS(northPosErr) < 12 { SET desNorthVel TO 0. }
    IF ABS(eastPosErr)  < 12 { SET desEastVel  TO 0. }

    LOCAL northAccCmd IS Clamp((desNorthVel - northVelVal) * velKpVal, -maxAccVal, maxAccVal).
    LOCAL eastAccCmd  IS Clamp((desEastVel  - eastVelVal)  * velKpVal, -maxAccVal, maxAccVal).

    LOCAL latAccVec IS northAxis * northAccCmd + eastAxis * eastAccCmd.
    IF latAccVec:MAG < 0.03 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL maxLatMag IS LAND_UP_BIAS_ACC * TAN(maxTiltVal).
    IF latAccVec:MAG > maxLatMag {
        SET latAccVec TO latAccVec:NORMALIZED * maxLatMag.
    }

    LOCAL steerVec IS (upVec * LAND_UP_BIAS_ACC + latAccVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

FUNCTION landingThrottle {
    LOCAL altAGL IS MAX(0, terrainAGL()).
    LOCAL gravAccel IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL kpVal IS LAND_THR_KP.

    // More aggressive than before:
    // stay fast higher up, but still flare progressively
    LOCAL tgtVSpd IS -MAX(25, MIN(220, altAGL * 0.09)).

    IF altAGL < 400 {
        SET kpVal TO LAND_THR_KP_LOW.

        IF altAGL > 200 {
            SET tgtVSpd TO -25.
        } ELSE IF altAGL > 100 {
            SET tgtVSpd TO -14.
        } ELSE IF altAGL > 40 {
            SET tgtVSpd TO -7.
        } ELSE IF altAGL > 15 {
            SET tgtVSpd TO -3.
        } ELSE {
            SET tgtVSpd TO -1.5.
        }
    }

    LOCAL accCmd IS gravAccel + (tgtVSpd - SHIP:VERTICALSPEED) * kpVal.
    LOCAL thrCmd IS Clamp((SHIP:MASS * accCmd) / MAXTHRUST, 0, 1).
    RETURN thrCmd.
}

// ============================================================
//  INITIALIZATION
// ============================================================
CLEARSCREEN.
logOpen().
logEvent("SCRIPT START - Pad:" + PAD_LAT + "/" + PAD_LNG + "/" + PAD_ALT).

PRINT "+----------------------------------+" AT (0, 0).
PRINT "| F9 RTLS SIMPLIFIED              |" AT (0, 1).
PRINT "+----------------------------------+" AT (0, 2).
PRINT "Pad lat:" + ROUND(PAD_LAT,6)      AT (0, 3).
PRINT "Pad lng:" + ROUND(PAD_LNG,6)      AT (0, 4).
PRINT "Pad alt:" + ROUND(PAD_ALT,0) + "m" AT (0, 5).
PRINT "NORTH: " + PAD_TRIM_NORTH_M + " EAST: "+ PAD_TRIM_EAST_M AT (0, 6).

LOCK THROTTLE TO 0.
LOCK STEERING TO UP.
SAS OFF.
RCS ON.
activateAG(2).
logEvent("AG2 fired - 3 engines enabled").

// ============================================================
//  MAIN LOOP
// ============================================================
UNTIL phase = PH_TOUCHDOWN {

    LOCAL altAGLVal IS terrainAGL().

    IF phase = PH_AERO OR phase = PH_LANDING {
        SET activePadGeo TO finalPadGeo().
    } ELSE {
        SET activePadGeo TO padGeo.
    }

    LOCAL padDistKmVal IS distKm(SHIP:GEOPOSITION, activePadGeo).
    LOCAL hsVal IS hSpeed().

    IF phase = PH_FLIP {
        LOCAL aimGeo IS boostbackAimGeo().
        LOCAL aimBrng IS bearingTo(aimGeo).
        LOCK STEERING TO HEADING(aimBrng, 0).

        LOCAL flipErr IS VANG(SHIP:FACING:FOREVECTOR, HEADING(aimBrng, 0):FOREVECTOR).

        PRINT "[FLIP] err:" + ROUND(flipErr,1) + "   " AT (0, 8).
        PRINT "brg:" + ROUND(aimBrng,1) + " alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "k" AT (0, 9).
        logPeriodic("flip err:" + ROUND(flipErr,1) + " brg:" + ROUND(aimBrng,1)).

        IF flipErr < 10 {
            SET bbStartTime TO TIME:SECONDS.
            SET phase TO PH_BOOSTBACK.
            SET lastPredTime TO -999.
            logEvent("FLIP complete - BOOSTBACK brg:" + ROUND(aimBrng,1)).
        }
    }

    ELSE IF phase = PH_BOOSTBACK {
        LOCAL aimGeo IS boostbackAimGeo().
        LOCAL aimBrng IS bearingTo(aimGeo).
        LOCAL impactGeo IS getImpact().
        LOCAL predNorthErr IS (PAD_LAT - impactGeo:LAT) * KERBIN_M_PER_DEG.
        LOCAL predEastErr  IS (PAD_LNG - impactGeo:LNG) * KERBIN_M_PER_DEG * COS(PAD_LAT).
        LOCAL bbElapsedVal IS TIME:SECONDS - bbStartTime.
        LOCAL bbThrCmd IS 0.12.

        LOCK STEERING TO HEADING(aimBrng, 0).

        IF predEastErr < BB_FULL_EAST_M {
            SET bbThrCmd TO 1.0.
        } ELSE IF predEastErr < BB_MID_EAST_M {
            SET bbThrCmd TO 0.60.
        } ELSE IF predEastErr < BB_LOW_EAST_M {
            SET bbThrCmd TO 0.30.
        }

        LOCK THROTTLE TO bbThrCmd.

        PRINT "[BB] " + ewText(predEastErr) + " " + nsText(predNorthErr) + "   " AT (0, 8).
        PRINT "thr:" + ROUND(bbThrCmd*100,0) + " h:" + ROUND(hsVal,1) + "  " AT (0, 9).
        logPeriodic("pred " + nsText(predNorthErr) + " " + ewText(predEastErr)
                    + " thr:" + ROUND(bbThrCmd*100,0)
                    + " hspd:" + ROUND(hsVal,1)
                    + " brg:" + ROUND(aimBrng,1)).

        IF predEastErr >= BB_STOP_EAST_M OR bbElapsedVal > BB_MAX_TIME {
            LOCK THROTTLE TO 0.
            SET phase TO PH_COAST.
            SET lastPredTime TO -999.
            logEvent("BOOSTBACK end " + nsText(predNorthErr) + " " + ewText(predEastErr)
                     + " hspd:" + ROUND(hsVal,1)
                     + " t:" + ROUND(bbElapsedVal,0)).
        }
    }

    ELSE IF phase = PH_COAST {
        LOCK THROTTLE TO 0.

        IF SHIP:ALTITUDE < 45000 AND SHIP:VERTICALSPEED < -50 AND NOT finsOut {
            activateAG(1).
            setFinAuthority(FIN_AUTH_COAST).
            SET finsOut TO TRUE.
            RCS OFF.
            logEvent("Fins deployed auth:" + FIN_AUTH_COAST + "%").
        }

        IF SHIP:VERTICALSPEED < -1 {
            LOCK STEERING TO SHIP:SRFRETROGRADE.
        } ELSE {
            LOCK STEERING TO UP.
        }

        LOCAL coastImpactGeo IS getImpact().
        LOCAL coastPredKm IS distKm(coastImpactGeo, padGeo).

        PRINT "[COAST] alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "k   " AT (0, 8).
        PRINT "pred:" + ROUND(coastPredKm,1) + " pad:" + ROUND(padDistKmVal,1) + " " AT (0, 9).
        logPeriodic("coast pred:" + ROUND(coastPredKm,1)
                    + " pad:" + ROUND(padDistKmVal,1)
                    + " hspd:" + ROUND(hsVal,1)).

        IF SHIP:VERTICALSPEED < -1 AND SHIP:ALTITUDE < ENTRY_ALT {
            SET phase TO PH_ENTRY.
            logEvent("COAST->ENTRY spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                     + " pad:" + ROUND(padDistKmVal,2)).
        }
    }

    ELSE IF phase = PH_ENTRY {
        LOCK STEERING TO SHIP:SRFRETROGRADE.
        LOCK THROTTLE TO 1.0.

        IF finsOut AND NOT finsAeroSet {
            setFinAuthority(FIN_AUTH_AERO).
            SET finsAeroSet TO TRUE.
        }

        PRINT "[ENTRY] spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0) + "   " AT (0, 8).
        PRINT "pad:" + ROUND(padDistKmVal,2) + " h:" + ROUND(hsVal,1) + "   " AT (0, 9).
        logPeriodic("entry spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                    + " pad:" + ROUND(padDistKmVal,2)
                    + " hspd:" + ROUND(hsVal,1)).

        IF SHIP:VELOCITY:SURFACE:MAG <= ENTRY_END_SPEED {
            LOCK THROTTLE TO 0.
            SET phase TO PH_AERO.
            logEvent("ENTRY->AERO spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                     + " pad:" + ROUND(padDistKmVal,2)).
        }
    }

    ELSE IF phase = PH_AERO {
        LOCK THROTTLE TO 0.
        LOCK STEERING TO finSteerDir(padDistKmVal).

        LOCAL ignAltVal IS ignitionAlt().
        LOCAL northNow  IS northErrM(activePadGeo).
        LOCAL eastNow   IS eastErrM(activePadGeo).

        PRINT "[AERO] pad:" + ROUND(padDistKmVal,2) + "   " AT (0, 8).
        PRINT nsText(northNow) + " " + ewText(eastNow) + " h:" + ROUND(hsVal,1) + " " AT (0, 9).
        logPeriodic("aero pad:" + ROUND(padDistKmVal,2)
                    + " " + nsText(northNow) + " " + ewText(eastNow)
                    + " hspd:" + ROUND(hsVal,1)
                    + " ign:" + ROUND(ignAltVal,0)).

        IF altAGLVal <= ignAltVal {
            LOCK THROTTLE TO 0.
            SET phase TO PH_LANDING.
            logEvent("AERO->LANDING agl:" + ROUND(altAGLVal,0)
                     + " vs:" + ROUND(SHIP:VERTICALSPEED,0)
                     + " hspd:" + ROUND(hsVal,1)
                     + " pad:" + ROUND(padDistKmVal,2)).
        }
    }

    ELSE IF phase = PH_LANDING {
        SET vesselBounds TO SHIP:BOUNDS.
        LOCAL altAGL IS terrainAGL().

        IF finsOut AND NOT finsLandSet {
            setFinAuthority(FIN_AUTH_LAND).
            SET finsLandSet TO TRUE.
            RCS OFF.
            logEvent("Landing fin auth:" + FIN_AUTH_LAND + "%").
        }

        IF NOT legsOut AND altAGL < LEG_DEPLOY_ALT {
            GEAR ON.
            SET legsOut TO TRUE.
            SET vesselBounds TO SHIP:BOUNDS.
            SET altAGL TO terrainAGL().
            logEvent("LEGS deployed at " + ROUND(altAGL,0) + "m").
        }

        LOCK STEERING TO landingGuideDir().
        LOCAL thrCmdVal IS landingThrottle().
        LOCK THROTTLE TO thrCmdVal.

        LOCAL northNow  IS northErrM(activePadGeo).
        LOCAL eastNow   IS eastErrM(activePadGeo).

        PRINT "[LAND] agl:" + ROUND(altAGLVal,0) + " vs:" + ROUND(SHIP:VERTICALSPEED,1) + "  " AT (0, 8).
        PRINT "thr:" + ROUND(thrCmdVal*100,0) + " " + nsText(northNow) + " " + ewText(eastNow) + " " AT (0, 9).
        logPeriodic("land thr:" + ROUND(thrCmdVal*100,0)
                    + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
                    + " hspd:" + ROUND(hsVal,1)
                    + " " + nsText(northNow) + " " + ewText(eastNow)).

        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
            SET touchdownSeen TO TRUE.
        }

        IF touchdownSeen
        OR (altAGLVal < 2
            AND SHIP:VERTICALSPEED > TOUCHDOWN_VS
            AND SHIP:VERTICALSPEED < 1
            AND hsVal < TOUCHDOWN_HS) {
            SET phase TO PH_TOUCHDOWN.
            logEvent("TOUCHDOWN vs:" + ROUND(SHIP:VERTICALSPEED,1)
                     + " hs:" + ROUND(hsVal,1)
                     + " pad:" + ROUND(padDistKmVal,2)
                     + " lat:" + ROUND(SHIP:LATITUDE,4)
                     + " lng:" + ROUND(SHIP:LONGITUDE,4)).
        }
    }

    WAIT 0.
}

// ============================================================
//  TOUCHDOWN CLEANUP
// ============================================================
LOCK THROTTLE TO 0.
WAIT 1.
UNLOCK STEERING.
WAIT 1.
UNLOCK THROTTLE.
WAIT 1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
RCS OFF.
SAS OFF.
setFinAuthority(0).

LOCAL finalPadKm IS distKm(SHIP:GEOPOSITION, padGeo).
logEvent("SCRIPT END - lat:" + ROUND(SHIP:LATITUDE,4)
         + " lng:" + ROUND(SHIP:LONGITUDE,4)
         + " pad:" + ROUND(finalPadKm,2) + "km").

PRINT "                                " AT (0, 8).
PRINT "                                " AT (0, 9).
PRINT "+----------------------------+" AT (0, 8).
PRINT "| TOUCHDOWN / SCRIPT END    |" AT (0, 9).
PRINT "+----------------------------+" AT (0, 8).
PRINT "Pad miss: " + ROUND(finalPadKm,2) + " km" AT (0, 9).
SAS OFF. 
WAIT 1.
UNLOCK ALL.
WAIT 1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.  // Resets all control inputs (including RCS translation)
WAIT 1.
PRINT "Booster disabled." AT (0, 10).
PRINT "END PROGRAM." AT (0, 11).