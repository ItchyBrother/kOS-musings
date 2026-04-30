FUNCTION EnableAllCommandPodRCS {
    LOCAL enabled IS 0.
    
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE("ModuleCommand") {
            IF p:HASMODULE("ModuleRCS") {
                LOCAL rcsModule IS p:GETMODULE("ModuleRCS").
                
                // Check if "rcsEnabled" field exists and what its value is
                IF rcsModule:HASFIELD("rcsEnabled") {
                    IF NOT rcsModule:GETFIELD("rcsEnabled") {
                        // It's disabled, so toggle it on
                        rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                        PRINT "Enabled RCS on: " + p:TITLE.
                        SET enabled TO enabled + 1.
                    } ELSE {
                        PRINT "RCS already enabled on: " + p:TITLE.
                    }
                } ELSE {
                    // Can't check state, just toggle and hope
                    rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                    PRINT "Toggled RCS on: " + p:TITLE.
                    SET enabled TO enabled + 1.
                }
            } ELSE IF p:HASMODULE("ModuleRCSFX") {
                LOCAL rcsModule IS p:GETMODULE("ModuleRCSFX").
                
                IF rcsModule:HASFIELD("rcsEnabled") {
                    IF NOT rcsModule:GETFIELD("rcsEnabled") {
                        rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                        PRINT "Enabled RCS on: " + p:TITLE.
                        SET enabled TO enabled + 1.
                    } ELSE {
                        PRINT "RCS already enabled on: " + p:TITLE.
                    }
                } ELSE {
                    rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                    PRINT "Toggled RCS on: " + p:TITLE.
                    SET enabled TO enabled + 1.
                }
            }
        }
    }
}
EnableAllCommandPodRCS().
WAIT UNTIL FALSE.