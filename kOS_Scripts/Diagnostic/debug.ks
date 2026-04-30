// Debug version - shows what events are available
FUNCTION DiagnoseCommandPodRCS {
    PRINT "=== DIAGNOSING COMMAND POD RCS ===".
    
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE("ModuleCommand") {
            PRINT "Found command pod: " + p:TITLE.
            PRINT "  Checking for RCS modules...".
            
            // Check ModuleRCS
            IF p:HASMODULE("ModuleRCS") {
                PRINT "  Has ModuleRCS".
                LOCAL rcsModule IS p:GETMODULE("ModuleRCS").
                
                PRINT "  Available EVENTS:".
                FOR evt IN rcsModule:ALLEVENTNAMES {
                    PRINT "    - " + evt.
                }
                
                PRINT "  Available ACTIONS:".
                FOR act IN rcsModule:ALLACTIONNAMES {
                    PRINT "    - " + act.
                }
            }
            
            // Check ModuleRCSFX
            IF p:HASMODULE("ModuleRCSFX") {
                PRINT "  Has ModuleRCSFX".
                LOCAL rcsModule IS p:GETMODULE("ModuleRCSFX").
                
                PRINT "  Available EVENTS:".
                FOR evt IN rcsModule:ALLEVENTNAMES {
                    PRINT "    - " + evt.
                }
                
                PRINT "  Available ACTIONS:".
                FOR act IN rcsModule:ALLACTIONNAMES {
                    PRINT "    - " + act.
                }
            }
            
            PRINT "".
        }
    }
    
    PRINT "Press any key to continue...".
    TERMINAL:INPUT:GETCHAR().
}

// Run the diagnostic
DiagnoseCommandPodRCS().