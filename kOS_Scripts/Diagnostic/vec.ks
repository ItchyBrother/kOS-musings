// === VECTOR DEBUG: MANUAL LANDING ===
CLEARSCREEN.
CLEARVECDRAWS().

PRINT "MANUAL LANDING DEBUG VECTORS".
PRINT "Blue  = Surface Velocity".
PRINT "Red   = Target Vector".
PRINT "Green = Thrust Direction".
PRINT " ".
PRINT "Press any key to exit.".

// === CONFIGURATION ===
GLOBAL MEM_CONFIG IS LEXICON(
    // Mission Parameters
    "TARGET_LAT", 0.6936,              // Neil Armstrong Memorial - Landing coordinates.
    "TARGET_LNG", 22.7608

).

// === VECDRAWS ===
GLOBAL vec_vel IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Surface Vel", 1.0, TRUE, 0.2).
GLOBAL vec_target IS VECDRAW(V(0,0,0), V(0,0,0), RED, "Target", 1.0, TRUE, 0.2).
GLOBAL vec_thrust IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Thrust", 1.0, TRUE, 0.2).


SET TARGET_POSITION TO BODY:GEOPOSITIONLATLNG(MEM_CONFIG["TARGET_LAT"], MEM_CONFIG["TARGET_LNG"]).

// === MAIN LOOP ===
UNTIL FALSE {
    LOCAL ship_pos IS SHIP:POSITION.
    LOCAL start_pos IS ship_pos.  // At ship center

    // Blue: Surface Velocity
    SET vec_vel:START TO start_pos.
    SET vec_vel:VECTOR TO SHIP:VELOCITY:SURFACE * 5.

    // Red: Target Vector
    SET vec_target:START TO start_pos.
    SET vec_target:VECTOR TO (TARGET_POSITION:POSITION - ship_pos).

    // Green: Thrust Direction
    SET vec_thrust:START TO start_pos.
    SET vec_thrust:VECTOR TO SHIP:FACING:VECTOR * 15.

    // Exit on key press
    IF TERMINAL:INPUT:HASCHAR {
        BREAK.
    }

    WAIT 0.01.
}

CLEARVECDRAWS().
PRINT "DEBUG VECTORS CLEARED.".