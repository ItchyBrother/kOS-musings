// === LOGGING SETUP ===
DELETEPATH("1:mission_log.txt").          // start fresh each run (remove if you want to append across runs)
LOG "=== MISSION LOG START - " + TIME:CALENDAR + " " + TIME:CLOCK + " ===" TO "1:mission_log.txt".

// Helper to print + log at once
FUNCTION plog {
    PARAMETER txt.
    PRINT txt.
    LOG txt TO "1:mission_log.txt".
}

// === CAPTURE CURRENT ORBIT ===
plog("=== CURRENT ORBIT ===").
plog("Apoapsis: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km").
plog("Periapsis: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km").
plog("Period: " + ROUND(SHIP:ORBIT:PERIOD, 1) + " s").
plog("Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " deg").
plog("Eccentricity: " + ROUND(SHIP:ORBIT:ECCENTRICITY, 4)).
plog("Time to Ap: " + ROUND(SHIP:ORBIT:ETA:APOAPSIS, 1) + " s").
plog("Time to Pe: " + ROUND(SHIP:ORBIT:ETA:PERIAPSIS, 1) + " s").

plog("").

// === CAPTURE MANEUVER NODE ===
IF NOT HASNODE {
    plog("No maneuver node found!").
    plog("Create a node and run script again.").
} ELSE {
    SET nd TO NEXTNODE.
    plog("").
    plog("=== MANEUVER NODE ===").
    plog("Node ETA: " + ROUND(nd:ETA, 1) + " s").
    plog("Delta-V: " + ROUND(nd:DELTAV:MAG, 1) + " m/s").
    plog("  Prograde: " + ROUND(nd:PROGRADE, 1) + " m/s").
    plog("  Normal:   " + ROUND(nd:NORMAL, 1) + " m/s").
    plog("  Radial:   " + ROUND(nd:RADIALOUT, 1) + " m/s").
    
    // === POST-BURN ORBIT ===
    SET postOrbit TO nd:ORBIT.
    plog("").
    plog("=== POST-BURN ORBIT ===").
    plog("Body: " + postOrbit:BODY:NAME).
    plog("Apoapsis: " + ROUND(postOrbit:APOAPSIS/1000, 1) + " km").
    plog("Periapsis: " + ROUND(postOrbit:PERIAPSIS/1000, 1) + " km").
    
    // === FIND TARGET BODY ENCOUNTER ===
    SET encounterOrbit TO postOrbit.
    UNTIL NOT encounterOrbit:HASNEXTPATCH {
        SET encounterOrbit TO encounterOrbit:NEXTPATCH.
        IF encounterOrbit:BODY <> SHIP:BODY {
            BREAK.
        }
    }
    
    // === CALCULATE TRANSIT TIME & PE LOCATION ===
    SET nodeTime TO TIME:SECONDS + nd:ETA.
    SET peTime TO TIME:SECONDS + encounterOrbit:ETA:PERIAPSIS.
    SET transitTime TO peTime - nodeTime.
    
    SET pePos TO POSITIONAT(SHIP, peTime) - encounterOrbit:BODY:POSITION.
    SET peLat TO encounterOrbit:BODY:GEOPOSITIONOF(pePos):LAT.
    SET peLong TO encounterOrbit:BODY:GEOPOSITIONOF(pePos):LNG.
    
    plog("Transit time to PE: " + ROUND(transitTime/3600, 2) + " h  (" + ROUND(transitTime, 1) + " s)").
    plog("").
    plog("=== PERIAPSIS LOCATION on " + encounterOrbit:BODY:NAME + " ===").
    plog("Latitude:  " + ROUND(peLat, 4) + " deg").
    plog("Longitude: " + ROUND(peLong, 4) + " deg").
    
    // === PREDICTED LANDING (WITH ROTATION) ===
    SET bodyRotPeriod TO encounterOrbit:BODY:ROTATIONPERIOD.
    SET rotationDegrees TO (transitTime / bodyRotPeriod) * 360.
    SET landingLong TO peLong + rotationDegrees.
    
    // Normalize to -180 to +180
    UNTIL landingLong <= 180 {
        SET landingLong TO landingLong - 360.
    }
    UNTIL landingLong > -180 {
        SET landingLong TO landingLong + 360.
    }
    
    plog("").
    plog("=== PREDICTED LANDING on " + encounterOrbit:BODY:NAME + " ===").
    plog("Latitude:  " + ROUND(peLat, 4) + " deg").
    plog("Longitude: " + ROUND(landingLong, 4) + " deg").
    plog("(Body rotation: " + ROUND(rotationDegrees, 2) + " deg during transit)").
}

plog("=== END OF LOG ===").
PRINT "→ Full report also saved to 1:mission_log.txt".