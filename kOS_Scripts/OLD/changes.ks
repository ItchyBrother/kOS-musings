// === Configuration ===
FUNCTION loadConfig {
    RETURN LEXICON(
        "targetPe", 8000,
        "maxNormalDV", 5,
        "maxRadialDV", 2,
        "dragFactor", 1.0,
        "dragMode", "distance",
        "dragTimeOffset", 10,
        "baseReentryAngle", 90,
        "latitudeLimit", 5,
        "trajTimeout", 60, // Increased to 60s
        "maxAttempts", 3,
        "posChangeThreshold", 0.005,
        "inputTimeout", 20,
        "maxGlobalAttempts", 5,
        "bisectionThreshold", 0.01
    ).
}

// Calculate available delta-v
FUNCTION calculateDeltaV {
    LOCAL totalDeltaV IS 0.
    LOCAL g0 IS 9.81.
    LOCAL stageEngines IS LIST().
    LIST ENGINES IN stageEngines.
    LOCAL activeEngines IS LIST().
    FOR eng IN stageEngines {
        IF eng:IGNITION AND NOT eng:FLAMEOUT {
            activeEngines:ADD(eng).
        }
    }
    IF activeEngines:LENGTH = 0 {
        debugLog("WARN", "calculateDeltaV", "No active engines found").
        RETURN 0.
    }
    LOCAL totalIsp IS 0.
    LOCAL totalThrust IS 0.
    FOR eng IN activeEngines {
        SET totalThrust TO totalThrust + eng:AVAILABLETHRUST.
        SET totalIsp TO totalIsp + (eng:ISP * eng:AVAILABLETHRUST).
    }
    IF totalThrust > 0 {
        SET totalIsp TO totalIsp / totalThrust.
    } ELSE {
        debugLog("WARN", "calculateDeltaV", "No thrust available").
        RETURN 0.
    }
    LOCAL initialMass IS SHIP:MASS.
    LOCAL dryMass IS initialMass - (SHIP:LIQUIDFUEL * 0.005 + SHIP:OXIDIZER * 0.005).
    IF dryMass <= 0 OR initialMass <= dryMass {
        debugLog("WARN", "calculateDeltaV", "Invalid mass values: initial=" + initialMass + ", dry=" + dryMass).
        RETURN 0.
    }
    SET totalDeltaV TO totalIsp * g0 * LN(initialMass / dryMass).
    debugLog("INFO", "calculateDeltaV", "Calculated delta-v=" + ROUND(totalDeltaV, 2) + " m/s, Isp=" + ROUND(totalIsp, 2) + " s").
    RETURN totalDeltaV.
}

// Estimate time to 90 degrees from target
FUNCTION estimateTimeToNode {
    LOCAL shipOrbit IS SHIP:ORBIT.
    LOCAL orbitalPeriod IS shipOrbit:PERIOD.
    LOCAL meanMotion IS 360 / orbitalPeriod.
    debugLog("INFO", "estimateTimeToNode", "Mean motion=" + ROUND(meanMotion, 4) + " deg/s, period=" + ROUND(orbitalPeriod, 2) + " s").

    LOCAL targetVec IS targetPos:POSITION - BODY:POSITION.
    LOCAL orbitNormal IS VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - BODY:POSITION):NORMALIZED.
    LOCAL targetProj IS targetVec - (VDOT(targetVec, orbitNormal) * orbitNormal).
    LOCAL shipPos IS SHIP:POSITION - BODY:POSITION.
    LOCAL shipProj IS shipPos - (VDOT(shipPos, orbitNormal) * orbitNormal).

    LOCAL angleToTarget IS VANG(shipProj, targetProj).
    LOCAL crossProd IS VCRS(shipProj, targetProj):NORMALIZED. // Normalize crossProd
    LOCAL directionSign IS VDOT(crossProd, orbitNormal).
    IF directionSign < 0 {
        SET angleToTarget TO 360 - angleToTarget.
        SET directionSign TO -1.
    } ELSE {
        SET directionSign TO 1.
    }
    debugLog("INFO", "estimateTimeToNode", "Initial angleToTarget=" + ROUND(angleToTarget, 2) + " deg, directionSign=" + ROUND(directionSign, 2)).

    // Place node ~90° before target
    LOCAL desiredAngle IS MOD(angleToTarget - settings["baseReentryAngle"] * directionSign, 360).
    IF desiredAngle < 0 { SET desiredAngle TO desiredAngle + 360. }
    LOCAL shipTrueAnomalyDeg IS shipOrbit:TRUEANOMALY.
    LOCAL angleToNode IS MOD(desiredAngle - shipTrueAnomalyDeg + 360, 360).
    LOCAL timeToNode IS angleToNode / meanMotion.
    IF timeToNode < 30 { SET timeToNode TO timeToNode + orbitalPeriod. }
    LOCAL nodeTime IS TIME:SECONDS + timeToNode.

    LOCAL futurePos IS POSITIONAT(SHIP, nodeTime) - BODY:POSITION.
    LOCAL futureProj IS futurePos - (VDOT(futurePos, orbitNormal) * orbitNormal).
    LOCAL checkAngle IS VANG(futureProj, targetProj).
    IF directionSign < 0 { SET checkAngle TO 360 - checkAngle. }
    debugLog("INFO", "estimateTimeToNode", "Initial checkAngle=" + ROUND(checkAngle, 2) + " deg, desiredAngle=" + ROUND(desiredAngle, 2)).

    LOCAL maxAdjustments IS 25. // Increased further
    LOCAL adjustmentCount IS 0.
    LOCAL angleError IS 1e9.
    LOCAL dampingFactor IS 0.2. // Further reduced
    UNTIL angleError <= 5 OR adjustmentCount >= maxAdjustments {
            SET futurePos TO POSITIONAT(SHIP, nodeTime) - BODY:POSITION.
            SET futureProj TO futurePos - (VDOT(futurePos, orbitNormal) * orbitNormal).
            SET checkAngle TO VANG(futureProj, targetProj).
            IF directionSign < 0 { SET checkAngle TO 360 - checkAngle. }
            SET angleError TO MIN(ABS(checkAngle - desiredAngle), ABS(360 - ABS(checkAngle - desiredAngle))).
            IF angleError > 5 {
                LOCAL timeAdjust IS (angleError / meanMotion) * dampingFactor.
                IF checkAngle > desiredAngle {
                    SET timeAdjust TO timeAdjust * -1.
                }
                IF ABS(timeAdjust) > timeToNode / 12 {
                    SET timeAdjust TO (timeToNode / 12).
                    IF timeAdjust > 0 {
                        SET timeAdjust TO timeAdjust * 1.
                    } ELSE {
                        SET timeAdjust TO timeAdjust * -1.
                    }
                }
                SET timeToNode TO timeToNode + timeAdjust.
                SET nodeTime TO TIME:SECONDS + timeToNode.
                debugLog("INFO", "estimateTimeToNode", "Adjusting node: error=" + ROUND(angleError, 2) + " deg, timeAdjust=" + ROUND(timeAdjust, 2) + " s").
            }
            SET adjustmentCount TO adjustmentCount + 1.
        }
    // Validate node position
    IF ABS(checkAngle - desiredAngle) > 180 {
        SET nodeTime TO nodeTime + orbitalPeriod / 2.
        SET timeToNode TO timeToNode + orbitalPeriod / 2.
        debugLog("INFO", "estimateTimeToNode", "Corrected node to opposite side of orbit").
    }

    debugLog("INFO", "estimateTimeToNode", "Final node: timeOffset=" + ROUND(timeToNode, 2) + " s, angleError=" + ROUND(angleError, 2) + " deg").
    RETURN LEXICON("nodeTime", nodeTime, "angleToNode", checkAngle, "angleToTarget", angleToTarget, "desiredAngle", desiredAngle).
}

// Create initial maneuver node
FUNCTION createInitialNode {
    LOCAL nodeData IS estimateTimeToNode().
    LOCAL nodeTime IS nodeData["nodeTime"].
    LOCAL checkAngle IS nodeData["angleToNode"].
    LOCAL angleToTarget IS nodeData["angleToTarget"].
    LOCAL burnMag IS 20. // Smaller initial burn
    LOCAL prevDist IS 1e10.
    LOCAL bestBurn IS burnMag.
    LOCAL bestDist IS prevDist.
    SET maneuverNode TO NODE(nodeTime, 0, 0, -burnMag).
    ADD maneuverNode.
    alignLAN().
    CLEARSCREEN.
    PRINT "Searching for initial burn..." AT (0, 0).
    PRINT "Node angle: ~" + ROUND(checkAngle, 2) + " deg (target: " + ROUND(angleToTarget, 2) + " deg)" AT (0, 1).

    // Check Trajectories readiness
    IF NOT ADDONS:TR:AVAILABLE {
        debugLog("ERROR", "createInitialNode", "Trajectories mod not available").
        PRINT "Error: Trajectories mod not available.".
        RETURN.
    }
    LOCAL dragParts IS 0.
    FOR part IN SHIP:PARTS {
        IF part:NAME:CONTAINS("parachute") { SET dragParts TO dragParts + 1. }
    }
    debugLog("INFO", "createInitialNode", "Vessel mass=" + ROUND(SHIP:MASS, 2) + " t, parts=" + SHIP:PARTS:LENGTH + ", liquidFuel=" + SHIP:LIQUIDFUEL + ", oxidizer=" + SHIP:OXIDIZER + ", parachutes=" + dragParts).

    UNTIL burnMag > 150 OR globalAttempts >= settings["maxGlobalAttempts"] {
        SET maneuverNode TO NODE(nodeTime, maneuverNode:NORMAL, maneuverNode:RADIALOUT, -burnMag).
        IF HASNODE { REMOVE NEXTNODE. }
        ADD maneuverNode.
        LOCAL nodeKey IS ROUND(nodeTime, 2) + ":" + ROUND(burnMag, 2).
        LOCAL cachedDist IS getCachedImpact(nodeKey).
        IF cachedDist <> FALSE {
            SET minDistance TO cachedDist.
        } ELSE {
            SET minDistance TO calculateImpactDistance(nodeTime).
            cacheImpact(nodeKey, minDistance).
        }
        PRINT "Burn: " + burnMag + " m/s" AT (0, 2).
        PRINT "Periapsis: " + ROUND(maneuverNode:ORBIT:PERIAPSIS/1000, 2) + " km" AT (0, 3).
        IF minDistance < 1e9 {
            LOCAL impactPos IS ADDONS:TR:IMPACTPOS.
            LOCAL longitudeError IS impactPos:LNG - targetPos:LNG.
            IF longitudeError > 180 { SET longitudeError TO longitudeError - 360. }
            IF longitudeError < -180 { SET longitudeError TO longitudeError + 360. }
            PRINT "Impact Distance: " + ROUND(minDistance, 2) + " km" AT (0, 4).
            PRINT "Longitude Error: " + ROUND(longitudeError, 2) + " deg" AT (0, 5).
            debugLog("INFO", "createInitialNode", "Burn: " + burnMag + " m/s", minDistance, longitudeError).
            IF minDistance > prevDist AND prevDist < 1e9 {
                SET burnMag TO bestBurn.
                SET minDistance TO bestDist.
                IF HASNODE { REMOVE NEXTNODE. }
                SET maneuverNode TO NODE(nodeTime, maneuverNode:NORMAL, maneuverNode:RADIALOUT, -burnMag).
                ADD maneuverNode.
                debugLog("INFO", "createInitialNode", "Reverted to burnMag=" + burnMag + " m/s", minDistance).
                BREAK.
            }
            SET prevDist TO minDistance.
            SET bestBurn TO burnMag.
            SET bestDist TO minDistance.
        } ELSE {
            PRINT "Impact Distance: No impact" AT (0, 4).
        }
        SET burnMag TO burnMag + 2. // Finer increments
        SET globalAttempts TO globalAttempts + 1.
        PRINT "Status: Trying " + burnMag + " m/s" AT (0, 6).
    }
    IF minDistance >= 1e9 OR globalAttempts >= settings["maxGlobalAttempts"] {
        debugLog("WARN", "createInitialNode", "No impact found, using fallback DV=83 m/s").
        IF HASNODE { REMOVE NEXTNODE. }
        SET maneuverNode TO NODE(nodeTime, maneuverNode:NORMAL, maneuverNode:RADIALOUT, -83).
        ADD maneuverNode.
        SET minDistance TO calculateImpactDistance(nodeTime).
        PRINT "Impact Distance: " + ROUND(minDistance, 2) + " km (fallback)" AT (0, 4).
    }
}

// Calculate impact distance with dragFactor
FUNCTION calculateImpactDistance {
    PARAMETER nodeTime.
    LOCAL attempts IS 0.
    UNTIL attempts >= settings["maxAttempts"] {
        IF waitForTrajectories(nodeTime) {
            LOCAL impactPos IS ADDONS:TR:IMPACTPOS.
            LOCAL impactLatitudeError IS ABS(impactPos:LAT - targetPos:LAT).
            IF impactLatitudeError > 0.5 {
                debugLog("WARN", "calculateImpactDistance", "Latitude error too large: " + ROUND(impactLatitudeError, 4) + " deg").
                RETURN 1e10.
            }
            LOCAL longitudeError IS impactPos:LNG - targetPos:LNG.
            IF longitudeError > 180 { SET longitudeError TO longitudeError - 360. }
            IF longitudeError < -180 { SET longitudeError TO longitudeError + 360. }
            IF ABS(longitudeError) > 0.01 {
                SET settings["dragFactor"] TO settings["dragFactor"] + (longitudeError / 100) * 0.1.
                debugLog("INFO", "calculateImpactDistance", "Adjusted dragFactor to " + ROUND(settings["dragFactor"], 3) + " for longitudeError=" + ROUND(longitudeError, 3)).
            }
            LOCAL adjustedNodeTime IS nodeTime.
            IF settings["dragMode"] = "time" {
                LOCAL timeOffset IS (settings["dragFactor"] - 1) * settings["dragTimeOffset"].
                SET adjustedNodeTime TO nodeTime + timeOffset.
                debugLog("INFO", "calculateImpactDistance", "Drag time offset: " + ROUND(timeOffset, 2) + " s").
            }
            LOCAL orbitalPath IS VELOCITYAT(SHIP, adjustedNodeTime):ORBIT:NORMALIZED.
            LOCAL offset IS 0.
            IF settings["dragMode"] = "distance" {
                SET offset TO (settings["dragFactor"] - 1) * 500.
            }
            LOCAL adjustedImpactPos IS impactPos:POSITION + (offset * orbitalPath).
            LOCAL longitudeDistance IS ABS(longitudeError) * COS(impactPos:LAT * CONSTANT:DegToRad) * 111.
            LOCAL latitudeError IS impactPos:LAT - targetPos:LAT.
            LOCAL spatialDistance IS (adjustedImpactPos - targetPos:POSITION):MAG / 1000.
            LOCAL adjustedDistance IS longitudeDistance + 0.1 * spatialDistance.
            debugLog("INFO", "calculateImpactDistance", "Impact: lngErr=" + ROUND(longitudeError, 4) + " deg, latErr=" + ROUND(latitudeError, 4) + " deg", adjustedDistance, longitudeError, latitudeError).
            SET prevLongitudeError TO longitudeError.
            RETURN adjustedDistance.
        }
        SET attempts TO attempts + 1.
        SET globalAttempts TO globalAttempts + 1.
        debugLog("WARN", "calculateImpactDistance", "Retrying impact prediction, attempt " + attempts).
        PRINT "Warning: Trajectories timeout, attempt " + attempts AT (0, 7).
        IF attempts >= settings["maxAttempts"] {
            PRINT "Trajectories timeout. Check mod settings (disable parachutes, match drag model). Retry? (y/n)" AT (0, 8).
            LOCAL input IS readInput().
            debugLog("INFO", "calculateImpactDistance", "User input: " + input).
            IF input = "Y" {
                SET settings["trajTimeout"] TO settings["trajTimeout"] + 10.
                SET attempts TO 0.
                debugLog("INFO", "calculateImpactDistance", "Retrying with trajTimeout=" + settings["trajTimeout"]).
                CLEARSCREEN.
                PRINT "Retrying with timeout " + settings["trajTimeout"] + "s..." AT (0, 8).
            } ELSE {
                debugLog("INFO", "calculateImpactDistance", "User aborted, falling back to estimate").
                IF NOT HASNODE { ADD maneuverNode. }
                RETURN estimateImpactDistance(nodeTime).
            }
        }
    }
    IF NOT HASNODE { ADD maneuverNode. }
    RETURN estimateImpactDistance(nodeTime).
}

// Estimate impact distance without Trajectories
FUNCTION estimateImpactDistance {
    PARAMETER nodeTime.
    IF NOT HASNODE { ADD maneuverNode. }
    LOCAL shipOrbit IS maneuverNode:ORBIT.
    LOCAL periapsisAlt IS shipOrbit:PERIAPSIS.
    IF periapsisAlt < 0 {
        debugLog("WARN", "estimateImpactDistance", "No impact: periapsis=" + ROUND(periapsisAlt/1000, 2) + " km").
        RETURN 1e10.
    }
    LOCAL impactLatitude IS ARCSIN(SIN(shipOrbit:INCLINATION * CONSTANT:DegToRad) * SIN(shipOrbit:ARGUMENTOFPERIAPSIS * CONSTANT:DegToRad + shipOrbit:LONGITUDEOFASCENDINGNODE * CONSTANT:DegToRad)).
    LOCAL impactLongitude IS shipOrbit:LONGITUDEOFASCENDINGNODE + shipOrbit:ARGUMENTOFPERIAPSIS.
    SET impactLongitude TO MOD(impactLongitude + 360, 360).
    LOCAL impactPos IS LATLNG(impactLatitude, impactLongitude).
    LOCAL longitudeError IS impactPos:LNG - targetPos:LNG.
    IF longitudeError > 180 { SET longitudeError TO longitudeError - 360. }
    IF longitudeError < -180 { SET longitudeError TO longitudeError + 360. }
    LOCAL latitudeError IS impactPos:LAT - targetPos:LAT.
    LOCAL longitudeDistance IS ABS(longitudeError) * COS(impactPos:LAT * CONSTANT:DegToRad) * 111.
    LOCAL latitudeDistance IS ABS(latitudeError) * 111.
    LOCAL estDistance IS SQRT(longitudeDistance^2 + latitudeDistance^2).
    // Dynamic drag correction based on mass and orbit
    LOCAL dragCorrection IS 1.0 + (settings["dragFactor"] - 1) * 0.3 * (SHIP:MASS / 2). // Scale with mass
    SET estDistance TO estDistance * dragCorrection.
    debugLog("INFO", "estimateImpactDistance", "Estimated impact: lat=" + ROUND(impactLatitude, 4) + ", lng=" + ROUND(impactLongitude, 4) + ", dragCorrection=" + ROUND(dragCorrection, 3), estDistance, longitudeError, latitudeError).
    RETURN estDistance.
}

// Main Function
FUNCTION main {
    cleanup().
    IF NOT ADDONS:TR:AVAILABLE {
        debugLog("ERROR", "main", "Trajectories mod required").
        PRINT "Trajectories mod required. Rebooting in 10s.".
        WAIT 10.
        REBOOT.
    }

    // Validate vessel state
    IF SHIP:ORBIT:APOAPSIS < 70000 OR SHIP:ORBIT:PERIAPSIS < 70000 {
        debugLog("ERROR", "main", "Orbit too low: AP=" + ROUND(SHIP:ORBIT:APOAPSIS/1000, 2) + ", PE=" + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 2)).
        PRINT "Error: Orbit too low. Circularize above 70 km.".
        RETURN.
    }
    LOCAL availDV IS calculateDeltaV().
    IF availDV = 0 {
        debugLog("ERROR", "main", "No delta-v available. Check staging, engines, or fuel.").
        PRINT "Error: No delta-v available. Check staging, engines, or fuel.".
        WAIT 10.
        RETURN.
    }
    IF availDV < 100 {
        debugLog("ERROR", "main", "Delta-v too low: " + ROUND(availDV, 2) + " m/s. Minimum 100 m/s required.").
        PRINT "Error: Delta-v too low (" + ROUND(availDV, 2) + " m/s). Minimum 100 m/s required.".
        WAIT 10.
        RETURN.
    }

    editConfig().
    SET targetPos TO selectTarget().
    ADDONS:TR:SETTARGET(targetPos).

    IF NOT isTargetValid() {
        debugLog("ERROR", "main", "Target outside 5-degree orbital path").
        PRINT "Target outside 5-degree orbital path.".
        WAIT 5.
        RETURN.
    }

    debugLog("INFO", "main", "Vessel mass=" + ROUND(SHIP:MASS, 2) + " t, orbit AP=" + ROUND(SHIP:ORBIT:APOAPSIS/1000, 2) + " km, PE=" + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 2) + " km, deltaV=" + ROUND(availDV, 2) + " m/s").
    createInitialNode().
    optimizeManeuver().
    finalizeNode().
}