// Reset RCS controls
CLEARSCREEN.
UNLOCK STEERING.  
WAIT 0.5.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE. // Resets all control inputs (including RCS translation)
WAIT 5.
RCS OFF. // Disables RCS thrusters
PRINT "RCS OFF and STEERING DISABLED.".
WAIT 0.5.
UNLOCK ALL.
WAIT 5.
SAS ON.
WAIT 1.
PRINT "SAS TURNED ON.  STABILITY SET.".