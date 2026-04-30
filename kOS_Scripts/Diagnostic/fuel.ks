// ---------------------------------------------------------------
//  STAGE_FUEL_DEBUG.ks
//  kOS 1.5 – Shows EXACTLY what kOS sees in EVERY stage
// ---------------------------------------------------------------

CLEARSCREEN.
PRINT "=== kOS STAGE FUEL DEBUG ===".
PRINT "Run this BEFORE and AFTER decoupling".
PRINT " ".

WAIT 10.

UNTIL FALSE {
    LOCAL line IS 3.

    // Find highest stage
    LOCAL max_s IS 0.
    LIST PARTS IN all_parts.
    FOR p IN all_parts { IF p:STAGE > max_s { SET max_s TO p:STAGE. } }

    PRINT "STAGE:NUMBER = " + STAGE:NUMBER + " | Max p:STAGE = " + max_s AT (0, line).
    SET line TO line + 2.

    // Show every part with LF/OX
    LOCAL part_idx IS 0.
    FOR p IN all_parts {
        LOCAL has_fuel IS FALSE.
        FOR r IN p:RESOURCES {
            IF r:NAME = "LiquidFuel" OR r:NAME = "Oxidizer" {
                SET has_fuel TO TRUE.
                BREAK.
            }
        }
        IF has_fuel {
            SET part_idx TO part_idx + 1.
            LOCAL title IS p:TITLE.
            IF title:LENGTH > 40 { SET title TO title:SUBSTRING(0,37) + "...". }
            PRINT "#" + part_idx + " [" + p:STAGE + "] " + title AT (0, line).
            SET line TO line + 1.

            FOR r IN p:RESOURCES {
                IF r:NAME = "LiquidFuel" OR r:NAME = "Oxidizer" {
                    LOCAL amt IS r:AMOUNT.
                    LOCAL cap IS r:CAPACITY.
                    LOCAL en  IS CHOOSE "YES" IF r:ENABLED ELSE "NO ".
                    PRINT "   " + r:NAME + ": " + amt + "/" + cap + "  EN: " + en AT (0, line).
                    SET line TO line + 1.
                }
            }
            PRINT " " AT (0, line).
            SET line TO line + 1.
        }
    }

    IF part_idx = 0 {
        PRINT "NO LF/OX FOUND ANYWHERE" AT (0, line).
    }

    WAIT 1.0.
}