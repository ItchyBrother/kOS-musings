// KerbAtlas post stage clean up script.
// This script will start at seperation
CLEARSCREEN.
SAS OFF.
PRINT "Sustainer Deorbit Active!".
WAIT 30.
    PRINT "Turning retrograde".
    LOCK STEERING TO RETROGRADE.
    WAIT 60.

    PRINT "COUNTDOWN:" AT (0,10).
    FROM {local countdown is 10.} UNTIL countdown <= 0 STEP {SET countdown to countdown - 1.} DO {
        PRINT "T-" + countdown + " " AT (0,11).
        WAIT 1.
    }

PRINT "Ignition!" AT (0,12).
UNTIL SHIP:ORBIT:PERIAPSIS <= 0 {
    PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 13).
    LOCK THROTTLE TO 1.
    WAIT 0.1.
}
LOCK THROTTLE TO 0.
WAIT 10.
PRINT "FINAL Orbital Parameters:" AT (0, 15).
PRINT "Ap:       " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0, 16).
PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 17).
SHUTDOWN.