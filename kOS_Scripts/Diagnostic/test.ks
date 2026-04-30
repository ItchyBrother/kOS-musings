// Test script to align impact marker with target marker (Green X) for deorbit
// Programmatically selects Green X or creates waypoint

// === Configuration ===
LOCAL spacecraftConfig IS LEXICON(
  "dragFactor", 1.001374,  // Initial drag factor
  "massRatio", 0.7998,     // Wet mass / dry mass
  "propGain", 20.0,        // For latitude correction
  "maxNormalDV", 30.0,     // Max NormalDV
  "maxProgradeDVCorrection", 10.0,  // For faster convergence
  "pidKp", 0.5,            // PID proportional gain
  "pidKi", 0.02,           // PID integral gain
  "pidKd", 0.05,           // PID derivative gain
  "targetRp", 615000,      // Target periapsis radius (m)
  "reentryAngles", LIST(88, 89),  // Test angles
  "maxIterations", 10,     // For convergence
  "defaultTargetLat", -0.0972,  // Fallback Green X latitude
  "defaultTargetLng", -74.5575  // Fallback Green X longitude
).

// === Global Variables ===
LOCAL bestNode IS LEXICON("totalError", 1e9, "progradeDV", 0, "normalDV", 0, "time", 0, "angle", 88).
LOCAL pidState IS LEXICON("integral", 0, "prevError", 0).
LOCAL logFilePath IS "0:/deorbit_test_log.txt".

// Delete existing log file
IF EXISTS(logFilePath) DELETEPATH(logFilePath).

// === Functions ===
// Adjust dragFactor based on LngError
FUNCTION adjustDragFactor {
  PARAMETER lngError.
  LOCAL adjustment IS lngError * 0.00002.
  SET spacecraftConfig["dragFactor"] TO spacecraftConfig["dragFactor"] + adjustment.
  SET spacecraftConfig["dragFactor"] TO MAX(1.0, MIN(1.01, spacecraftConfig["dragFactor"])).
  LOG "Adjusted dragFactor to " + spacecraftConfig["dragFactor"] + " for LngError=" + lngError TO logFilePath.
}

// Calculate burn longitude
FUNCTION calcBurnLongitude {
  PARAMETER targetLng, reentryAngle.
  LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
  LOCAL lan IS SHIP:ORBIT:LAN.
  LOCAL lanDiff IS lan - targetLng.
  LOCAL massRatio IS spacecraftConfig["massRatio"].
  LOCAL dragAdjustment IS spacecraftConfig["dragFactor"] * massRatio.
  LOCAL period IS 2 * CONSTANT:PI * SQRT(sma^3 / BODY:MU).
  LOCAL reentryTime IS period * 0.25 * dragAdjustment.
  LOCAL rotOffset IS reentryTime * (360 / BODY:ROTATIONPERIOD).
  LOCAL lanAdjustment IS lanDiff * 0.5.
  LOCAL burnLng IS targetLng - rotOffset - lanAdjustment.
  SET burnLng TO MOD(burnLng + 360, 360) - 180.
  
  LOG "calcBurnLongitude: targetLng=" + targetLng + ", burnLng=" + burnLng + ", reentryAngle=" + reentryAngle + ", rotOffset=" + rotOffset + ", lanAdjustment=" + lanAdjustment + ", reentryTime=" + reentryTime TO logFilePath.
  RETURN burnLng.
}

// Calculate true anomaly
FUNCTION calcBurnTrueAnomaly {
  PARAMETER targetLat.
  LOCAL inc IS SHIP:ORBIT:INCLINATION.
  LOCAL sinInc IS SIN(inc).
  LOCAL ratio IS 0.
  IF ABS(sinInc) > 0.0001 {
    SET ratio TO targetLat / sinInc.
    SET ratio TO MAX(-1, MIN(1, ratio)).
  } ELSE {
    LOG "Warning: Near-zero inclination (" + inc + "), setting ratio to 0" TO logFilePath.
    SET ratio TO 0.
  }
  LOCAL trueAnomaly IS ARCSIN(ratio).
  IF trueAnomaly < 0 SET trueAnomaly TO 180 - trueAnomaly.
  LOG "calcBurnTrueAnomaly: targetLat=" + targetLat + ", inc=" + inc + ", ratio=" + ratio + ", TrueAnomaly=" + trueAnomaly TO logFilePath.
  RETURN trueAnomaly.
}

// Calculate NormalDV
FUNCTION calcNormalDV {
  PARAMETER latError.
  LOCAL propGain IS spacecraftConfig["propGain"].
  LOCAL normalDV IS -latError * propGain.
  SET normalDV TO MAX(-spacecraftConfig["maxNormalDV"], MIN(spacecraftConfig["maxNormalDV"], normalDV)).
  LOG "calcNormalDV: LatError=" + latError + ", NormalDV=" + normalDV + ", PropGain=" + propGain TO logFilePath.
  RETURN normalDV.
}

// PID controller for prograde DV
FUNCTION calcProgradeDVCorrection {
  PARAMETER lngError.
  LOCAL Kp IS spacecraftConfig["pidKp"].
  LOCAL Ki IS spacecraftConfig["pidKi"].
  LOCAL Kd IS spacecraftConfig["pidKd"].
  SET pidState["integral"] TO pidState["integral"] + lngError.
  LOCAL derivative IS (lngError - pidState["prevError"]).
  SET pidState["prevError"] TO lngError.
  LOCAL correction IS Kp * lngError + Ki * pidState["integral"] + Kd * derivative.
  SET correction TO MAX(-spacecraftConfig["maxProgradeDVCorrection"], MIN(spacecraftConfig["maxProgradeDVCorrection"], -correction)).
  LOG "calcProgradeDVCorrection: LngError=" + lngError + ", Correction=" + correction + ", Integral=" + pidState["integral"] TO logFilePath.
  RETURN correction.
}

// Calculate required DV
FUNCTION calcRequiredDV {
  PARAMETER burnRadius.
  LOCAL mu IS BODY:MU.
  LOCAL v1 IS SQRT(mu * (2 / burnRadius - 1 / SHIP:ORBIT:SEMIMAJORAXIS)).
  LOCAL v2 IS SQRT(mu * (2 / burnRadius - 1 / (burnRadius + spacecraftConfig["targetRp"])/2)).
  LOCAL dv IS v2 - v1.
  LOG "calcRequiredDV: BurnRadius=" + burnRadius + ", DV=" + dv TO logFilePath.
  RETURN dv.
}

// Select Green X target or create waypoint
FUNCTION selectGreenXTarget {
  LOCAL targetLat IS spacecraftConfig["defaultTargetLat"].
  LOCAL targetLng IS spacecraftConfig["defaultTargetLng"].
  LOCAL targetSet IS FALSE.
  
  // Try Trajectories mod target position
  IF ADDONS:TR:AVAILABLE {
    // Check if Trajectories has a target position (not directly supported, but attempt)
    IF ADDONS:TR:HASIMPACT {
      // Trajectories may not expose target directly; try to infer
      SET targetLat TO ADDONS:TR:IMPACTPOS:LAT.
      SET targetLng TO ADDONS:TR:IMPACTPOS:LNG.
      LOG "Trajectories target attempt: Lat=" + targetLat + ", Lng=" + targetLng TO logFilePath.
    }
  }
  
  // Create waypoint at target coordinates
  LOCAL waypointName IS "GreenX_Target".
  LOCAL waypointAlt IS 0.  // Surface level
  LOCAL geopos IS LATLNG(targetLat, targetLng).
  // Remove existing waypoint if present
  FOR wp IN ALLWAYPOINTS() {
    IF wp:NAME = waypointName {
      wp:REMOVE().
      LOG "Removed existing waypoint: " + waypointName TO logFilePath.
    }
  }
  // Create new waypoint
  LOCAL newWaypoint IS CREATEWAYPOINT(geopos, waypointAlt, waypointName).
  IF newWaypoint:ISSELECTED {
    SET TARGET TO newWaypoint.
    SET targetSet TO TRUE.
    LOG "Waypoint created and set as target: " + waypointName + ", Lat=" + targetLat + ", Lng=" + targetLng TO logFilePath.
  } ELSE {
    LOG "Warning: Failed to create waypoint at Lat=" + targetLat + ", Lng=" + targetLng TO logFilePath.
  }
  
  // Fallback to hardcoded coordinates if waypoint fails
  IF NOT targetSet {
    LOG "Warning: Using fallback coordinates Lat=" + targetLat + ", Lng=" + targetLng TO logFilePath.
  }
  
  RETURN LEXICON("lat", targetLat, "lng", targetLng).
}

// Main deorbit logic
FUNCTION testDeorbit {
  CLEARSCREEN.
  PRINT "Starting deorbit test...".
  LOG "=== Deorbit Test ===" TO logFilePath.
  
  // Check for Trajectories mod
  IF NOT ADDONS:TR:AVAILABLE {
    PRINT "Error: Trajectories mod not available!".
    LOG "Error: Trajectories mod not available!" TO logFilePath.
    RETURN.
  }
  
  // Select Green X target
  LOCAL targetCoords IS selectGreenXTarget().
  LOCAL targetLat IS targetCoords["lat"].
  LOCAL targetLng IS targetCoords["lng"].
  LOG "Using target coordinates: Lat=" + targetLat + ", Lng=" + targetLng TO logFilePath.
  
  // Orbital parameters
  LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
  LOCAL lan IS SHIP:ORBIT:LAN.
  LOCAL inc IS SHIP:ORBIT:INCLINATION.
  LOCAL burnRadius IS sma - 5000.
  LOCAL requiredDV IS calcRequiredDV(burnRadius).
  LOG "Orbital parameters: SMA=" + sma + ", LAN=" + lan + ", INC=" + inc TO logFilePath.
  
  // Test each reentry angle
  FOR reentryAngle IN spacecraftConfig["reentryAngles"] {
    PRINT "Testing reentry angle: " + reentryAngle.
    LOG "Testing reentry angle: " + reentryAngle TO logFilePath.
    
    // Calculate initial burn parameters
    LOCAL burnLng IS calcBurnLongitude(targetLng, reentryAngle).
    LOCAL trueAnomaly IS calcBurnTrueAnomaly(targetLat).
    LOCAL burnTime IS TIME:SECONDS + 300.
    LOCAL progradeDV IS -requiredDV.
    LOCAL normalDV IS 0.
    
    // Reset PID state
    SET pidState["integral"] TO 0.
    SET pidState["prevError"] TO 0.
    
    // Iterative refinement
    LOCAL iter IS 0.
    UNTIL iter >= spacecraftConfig["maxIterations"] {
      // Create maneuver node
      LOCAL maneuverNode IS NODE(burnTime, 0, normalDV, progradeDV).
      ADD maneuverNode.
      WAIT 0.1.
      
      // Wait for trajectory prediction
      LOCAL impactLat IS 0.
      LOCAL impactLng IS 0.
      LOCAL latError IS 0.
      LOCAL lngError IS 0.
      LOCAL totalError IS 1e9.
      IF ADDONS:TR:HASIMPACT {
        UNTIL ADDONS:TR:IMPACTPOS:LAT <> 0 {
          WAIT 0.1.
          IF TIME:SECONDS > burnTime + 10 BREAK.
        }
        SET impactLat TO ADDONS:TR:IMPACTPOS:LAT.
        SET impactLng TO ADDONS:TR:IMPACTPOS:LNG.
        SET latError TO impactLat - targetLat.
        SET lngError TO impactLng - targetLng.
        SET totalError TO SQRT(latError^2 + lngError^2) * 111.
      } ELSE {
        LOG "Warning: No impact predicted for iter " + iter TO logFilePath.
      }
      
      // Log iteration
      LOG "Iter " + iter + ": ImpactLat=" + impactLat + ", ImpactLng=" + impactLng + ", LatError=" + latError + ", LngError=" + lngError + ", TotalError=" + totalError + ", ProgradeDV=" + progradeDV + ", NormalDV=" + normalDV TO logFilePath.
      
      // Check if best node
      IF totalError < bestNode["totalError"] {
        SET bestNode["totalError"] TO totalError.
        SET bestNode["progradeDV"] TO progradeDV.
        SET bestNode["normalDV"] TO normalDV.
        SET bestNode["time"] TO burnTime.
        SET bestNode["angle"] TO reentryAngle.
        LOG "New best node: TotalError=" + totalError + ", LngError=" + lngError + ", ProgradeDV=" + progradeDV + ", NormalDV=" + normalDV TO logFilePath.
      }
      
      // Update corrections
      SET normalDV TO calcNormalDV(latError).
      LOCAL progradeCorrection IS calcProgradeDVCorrection(lngError).
      SET progradeDV TO progradeDV + progradeCorrection.
      adjustDragFactor(lngError).
      
      // Check convergence
      IF totalError < 100 AND ABS(lngError) < 1 {
        LOG "Converged early: TotalError=" + totalError + ", LngError=" + lngError TO logFilePath.
        BREAK.
      }
      
      REMOVE maneuverNode.
      WAIT 0.1.
      SET iter TO iter + 1.
    }
  }
  
  // Apply best node
  IF bestNode["totalError"] < 1e9 {
    PRINT "Best node: Angle=" + bestNode["angle"] + ", TotalError=" + bestNode["totalError"] + " km".
    LOCAL finalNode IS NODE(bestNode["time"], 0, bestNode["normalDV"], bestNode["progradeDV"]).
    ADD finalNode.
    LOG "Final node: Angle=" + bestNode["angle"] + ", ProgradeDV=" + bestNode["progradeDV"] + ", NormalDV=" + bestNode["normalDV"] + ", TotalError=" + bestNode["totalError"] TO logFilePath.
  } ELSE {
    PRINT "Error: No valid node found!".
    LOG "Error: No valid node found!" TO logFilePath.
  }
}

// === Execution ===
testDeorbit().