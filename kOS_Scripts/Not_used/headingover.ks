// GROUND_TRACK_HEADING_PERFECT.ks
// No variable name ever shadows any built-in suffix

FUNCTION CalcGroundTrack {
    PARAMETER groundVessel, spaceVessel.

    IF groundVessel:BODY <> spaceVessel:BODY { RETURN -999. }

    LOCAL planet      IS groundVessel:BODY.

    LOCAL siteRadiusVec  IS groundVessel:POSITION - planet:POSITION.
    LOCAL satRadiusVec   IS spaceVessel:POSITION - planet:POSITION.

    LOCAL radialUnit     IS siteRadiusVec:NORMALIZED.

    LOCAL planetSpinVec  IS planet:ANGULARVEL.                  // full correct vector

    // ENU frame – only cross product order that works in KSP
    LOCAL eastUnitVec    IS VCRS(radialUnit, planetSpinVec):NORMALIZED.
    IF eastUnitVec:MAG < 0.01 {
        LOCAL fallback IS VCRS(radialUnit, V(1,0,0)):NORMALIZED.
        IF fallback:MAG < 0.01 SET fallback TO VCRS(radialUnit, V(0,1,0)):NORMALIZED.
        SET eastUnitVec TO fallback.
    }
    LOCAL northUnitVec   IS VCRS(eastUnitVec, radialUnit):NORMALIZED.

    LOCAL inertialVel    IS spaceVessel:VELOCITY:ORBIT.
    LOCAL rotationVel    IS VCRS(planetSpinVec, satRadiusVec).
    LOCAL surfaceVel     IS inertialVel - rotationVel.

    LOCAL horizontalVel  IS surfaceVel - VDOT(surfaceVel, radialUnit) * radialUnit.

    IF horizontalVel:MAG < 5 { RETURN -1. }

    // ATAN2(east, north) → clockwise from north
    LOCAL angleDeg IS ARCTAN2( VDOT(horizontalVel, eastUnitVec), VDOT(horizontalVel, northUnitVec) ) 
                      * 180 / CONSTANT:PI.

    IF angleDeg < 0 { SET angleDeg TO angleDeg + 360. }

    RETURN angleDeg.
}

// ────────────────────── RUN THIS AFTER A CLEAN REBOOT ──────────────────────
CLEARSCREEN.

SET groundSite TO SHIP.                    // or VESSEL("MEM 12")
SET satellite  TO VESSEL("Kpollo 12 CSM").

LOCAL trackHeading IS CalcGroundTrack(groundSite, satellite).

IF trackHeading = -999 {
    PRINT "Error: different planets".
} ELSE IF trackHeading = -1 {
    PRINT "Satellite almost directly overhead".
} ELSE {
    PRINT "Ground-track heading over " + groundSite:NAME + ": " + ROUND(trackHeading, 2) + " degrees".
}