// Debug script to find APU and RCS event names
CLEARSCREEN.
PRINT "=== APU and RCS Debug ===".
PRINT " ".

PRINT "Searching for APU parts...".
FOR p IN SHIP:PARTS {
    IF p:TITLE:CONTAINS("NH-24") OR p:TITLE:CONTAINS("APU") OR p:NAME:CONTAINS("NH-24") {
        PRINT "Found part: " + p:TITLE.
        PRINT "Part name: " + p:NAME.
        
        IF p:HASMODULE("ModuleResourceConverter") {
            PRINT "  Has ModuleResourceConverter".
            LOCAL conv IS p:GETMODULE("ModuleResourceConverter").
            PRINT "  Available events:".
            FOR evt IN conv:ALLEVENTS {
                PRINT "    - " + evt.
            }
        }
        
        IF p:HASMODULE("ModuleGenerator") {
            PRINT "  Has ModuleGenerator".
            LOCAL gen IS p:GETMODULE("ModuleGenerator").
            PRINT "  Available events:".
            FOR evt IN gen:ALLEVENTS {
                PRINT "    - " + evt.
            }
        }
        PRINT " ".
    }
}

PRINT "Searching for command pod RCS...".
FOR p IN SHIP:PARTS {
    IF p:HASMODULE("ModuleCommand") {
        PRINT "Found command pod: " + p:TITLE.
        PRINT "Part name: " + p:NAME.
        
        IF p:HASMODULE("ModuleRCS") {
            PRINT "  Has ModuleRCS".
            LOCAL rcs IS p:GETMODULE("ModuleRCS").
            PRINT "  Available events:".
            FOR evt IN rcs:ALLEVENTS {
                PRINT "    - " + evt.
            }
        }
        
        IF p:HASMODULE("ModuleRCSFX") {
            PRINT "  Has ModuleRCSFX".
            LOCAL rcs IS p:GETMODULE("ModuleRCSFX").
            PRINT "  Available events:".
            FOR evt IN rcs:ALLEVENTS {
                PRINT "    - " + evt.
            }
        }
        PRINT " ".
    }
}

PRINT "Debug complete. Check the events listed above.".
