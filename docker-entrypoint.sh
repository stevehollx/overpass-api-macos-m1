#!/bin/bash
set -e

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# DEBUG: Add this section right after the log function
log "Script arguments: $@"
log "First argument (\$1): [$1]"
log "SKIP_INIT: [$SKIP_INIT]"
log "OVERPASS_PLANET_URL: [$OVERPASS_PLANET_URL]"
log "Planet file exists: $(test -f /tmp/planet.osm.bz2 && echo YES || echo NO)"

# Test the conditions
if [ "$SKIP_INIT" != "true" ]; then
    log "✓ SKIP_INIT condition passes"
else
    log "✗ SKIP_INIT condition fails"
fi

if [ -n "$OVERPASS_PLANET_URL" ]; then
    log "✓ PLANET_URL condition passes"
else
    log "✗ PLANET_URL condition fails"
fi

if [ "$SKIP_INIT" != "true" ] && [ -n "$OVERPASS_PLANET_URL" ]; then
    log "✓ Combined condition PASSES - should call init_database"
else
    log "✗ Combined condition FAILS - will skip init_database"
fi

init_database() {
    log "Starting database initialization check..."
    
    # Ensure directories exist - create cache in Docker volume, sockets in /var/run
    mkdir -p /db /var/cache/overpass /var/run/overpass
    
    # Set permissions on directories we can control
    chmod 755 /var/cache/overpass /var/run/overpass || {
        log "Warning: Could not set some directory permissions, continuing..."
    }
    
    # Create CGI directory and symlinks
    mkdir -p /opt/osm3s/cgi-bin
    ln -sf /opt/osm3s/bin/osm3s_query /opt/osm3s/cgi-bin/interpreter
    
    # Create custom status script (not a symlink)
    cat > /opt/osm3s/cgi-bin/status << 'EOF'
#!/bin/bash
echo "Content-Type: application/xml"
echo ""
echo '<?xml version="1.0" encoding="UTF-8"?>'
echo '<osm_base_settings>'
echo '  <version>0.7.62.1</version>'
if [ -f "/tmp/overpass_db_hybrid/osm_base_version" ]; then
    echo '  <timestamp_osm_base>'$(cat /tmp/overpass_db_hybrid/osm_base_version)'</timestamp_osm_base>'
else
    echo '  <timestamp_osm_base>unknown</timestamp_osm_base>'
fi
echo '  <timestamp_areas_base>not available</timestamp_areas_base>'
echo '</osm_base_settings>'
EOF
    chmod +x /opt/osm3s/cgi-bin/status
    
    # Check if database is actually initialized (not just if init_done exists)
    DATABASE_READY=false
    
    if [ -f "/db/init_done" ]; then
        log "Found init_done marker, checking if database has actual data..."
        
        # Check if essential database files exist and are not empty
        if [ -f "/db/nodes.bin" ] && [ -s "/db/nodes.bin" ] && \
           [ -f "/db/ways.bin" ] && [ -s "/db/ways.bin" ] && \
           [ -f "/db/nodes.map" ] && [ -s "/db/nodes.map" ]; then
            log "Database files exist and have data - initialization not needed"
            DATABASE_READY=true
        else
            log "Database files missing or empty despite init_done marker - will re-initialize"
            rm -f /db/init_done
        fi
    else
        log "No init_done marker found - initialization needed"
    fi
    
    # Only initialize if database is not ready
    if [ "$DATABASE_READY" = "false" ]; then
        # Handle planet file initialization
        if [ -n "$OVERPASS_PLANET_URL" ]; then
            if [[ "$OVERPASS_PLANET_URL" == http* ]]; then
                log "Downloading planet file from $OVERPASS_PLANET_URL"
                wget -O /tmp/planet.osm.bz2 "$OVERPASS_PLANET_URL"
                PLANET_FILE="/tmp/planet.osm.bz2"
            elif [[ "$OVERPASS_PLANET_URL" == file://* ]]; then
                PLANET_FILE="${OVERPASS_PLANET_URL#file://}"
                if [ ! -f "$PLANET_FILE" ]; then
                    log "ERROR: Planet file not found: $PLANET_FILE"
                    exit 1
                fi
            else
                log "ERROR: Unsupported OVERPASS_PLANET_URL scheme"
                exit 1
            fi
            
            log "Initializing database with planet file: $PLANET_FILE"
            log "This may take several hours for large files..."
            cd /db
            
            # Run initialization - handle potential permission issues gracefully
            if /opt/osm3s/bin/init_osm3s.sh "$PLANET_FILE" /db /opt/osm3s/; then
                log "Database initialization completed successfully"
                
                # Verify initialization actually worked
                if [ -f "/db/nodes.bin" ] && [ -s "/db/nodes.bin" ]; then
                    touch /db/init_done
                    log "Database initialization verified and marked complete"
                else
                    log "ERROR: Initialization completed but database files are still empty"
                    exit 1
                fi
            else
                log "ERROR: Database initialization failed"
                exit 1
            fi
        else
            log "No OVERPASS_PLANET_URL specified, skipping database initialization"
        fi
    else
        log "Database already properly initialized, skipping initialization"
    fi
}

# Setup hybrid database structure
setup_hybrid_structure() {
    log "Setting up hybrid database structure..."
    
    # Clean up any existing sockets in all possible locations
    rm -f /var/run/overpass/osm3s_osm_base
    rm -f /tmp/osm3s_osm_base
    rm -f /dev/shm/osm3s_osm_base
    
    # Check for socket in /db but don't try to remove it
    if [ -f "/db/osm3s_osm_base" ]; then
        log "Warning: Socket file exists in /db, leaving it alone due to potential permission issues"
    fi
    
    # Create working directory for hybrid setup
    mkdir -p /tmp/overpass_db_hybrid
    cd /tmp/overpass_db_hybrid
    
    # Copy essential files if they exist
    [ -f "/db/osm_base_version" ] && cp /db/osm_base_version ./ 2>/dev/null || true
    [ -f "/db/init_done" ] && cp /db/init_done ./ 2>/dev/null || true
    
    # Create symlinks to data files (only if they exist)
    for pattern in "*.bin" "*.idx" "*.map"; do
        if ls /db/${pattern} 1> /dev/null 2>&1; then
            ln -sf /db/${pattern} ./ 2>/dev/null || {
                log "Warning: Could not create symlinks for $pattern"
            }
        fi
    done
    
    log "Hybrid structure setup completed"
}

# Add this function to your docker-entrypoint.sh file, after the setup_hybrid_structure() function:

create_cgi_wrapper() {
    log "Creating CGI wrapper script for Overpass API..."
    
    # Create the wrapper script that handles POST data properly
    cat > /opt/osm3s/cgi-bin/interpreter_wrapper.sh << 'EOF'
#!/bin/bash

# Set environment for osm3s_query
export EXEC_DIR=/tmp/overpass_db_hybrid
cd /tmp/overpass_db_hybrid

# CGI scripts must output HTTP headers first
echo "Content-Type: application/json"
echo ""

# Read POST data and extract the query
if [ "$REQUEST_METHOD" = "POST" ]; then
    # Read the POST data
    POST_DATA=$(cat)
    
    # Extract the query from "data=..." parameter and handle basic URL encoding
    QUERY=$(echo "$POST_DATA" | sed 's/^data=//' | sed 's/+/ /g')
    
    # Simple URL decode for common characters
    QUERY=$(echo "$QUERY" | sed 's/%20/ /g' | sed 's/%22/"/g' | sed 's/%3A/:/g' | sed 's/%3B/;/g' | sed 's/%5B/[/g' | sed 's/%5D/]/g')
    
    # Check if osm3s_query exists and is executable
    if [ ! -x "/opt/osm3s/bin/osm3s_query" ]; then
        echo '{"error": "osm3s_query not found or not executable"}'
        exit 1
    fi
    
    # Run osm3s_query with timeout
    echo "$QUERY" | timeout 300 /opt/osm3s/bin/osm3s_query 2>&1
else
    # Handle GET requests - for status endpoint
    echo '{"status": "ready", "message": "Overpass API is running"}'
fi
EOF

    # Make the wrapper executable
    chmod +x /opt/osm3s/cgi-bin/interpreter_wrapper.sh
    
    # Create the correct symlink to our wrapper (not directly to osm3s_query)
    rm -f /opt/osm3s/cgi-bin/interpreter
    ln -sf /opt/osm3s/cgi-bin/interpreter_wrapper.sh /opt/osm3s/cgi-bin/interpreter
    
    log "CGI wrapper script created successfully"
}



# Start all services
start_services() {
    log "Starting services..."
    
    # Debug: Show current user and groups
    log "Debug: Current user: $(whoami), groups: $(groups)"
    
    # Debug: Show /var/run permissions
    log "Debug: /var/run permissions:"
    ls -la /var/run/ | head -10
    
    # Ensure socket directory exists first
    mkdir -p /var/run/overpass
    
    # Set permissions only on directories we can control (skip /db to avoid macOS issues)
    chmod -R 755 /var/cache/overpass /var/run /var/log /var/run/overpass 2>/dev/null || {
        log "Warning: Some permission changes failed, continuing..."
    }
    
    # Debug: Show socket directory permissions
    log "Debug: Socket directory permissions:"
    ls -la /var/run/overpass/
    
    # Fix the interpreter symlink
    # rm -f /opt/osm3s/cgi-bin/interpreter
    # ln -sf /opt/osm3s/bin/osm3s_query /opt/osm3s/cgi-bin/interpreter
    # Create CGI wrapper for proper POST data handling
    create_cgi_wrapper

    # Start nginx
    log "Starting nginx..."
    nginx &
    
    # Ensure socket directory exists and is writable
    mkdir -p /var/run/overpass
    chmod 755 /var/run/overpass
    
    # Debug: Test if we can write to socket directory
    if touch /var/run/overpass/test_write && rm /var/run/overpass/test_write; then
        log "Debug: Socket directory is writable"
    else
        log "Debug: ERROR - Cannot write to socket directory!"
    fi
    
    # Clean up any existing socket
    rm -f /var/run/overpass/fcgiwrap.socket
    
    # Start fcgiwrap with socket in /var/run
    log "Starting fcgiwrap..."
    log "Debug: About to run: fcgiwrap -f -s unix:/var/run/overpass/fcgiwrap.socket"
    
    # Run fcgiwrap with error output captured
    fcgiwrap -f -s unix:/var/run/overpass/fcgiwrap.socket &
    FCGIWRAP_PID=$!
    
    # Wait a moment and check if it's still running
    sleep 2
    
    if kill -0 $FCGIWRAP_PID 2>/dev/null; then
        log "Debug: fcgiwrap is running with PID $FCGIWRAP_PID"
    else
        log "Debug: ERROR - fcgiwrap died immediately!"
        # Try to get more error info
        log "Debug: Trying to run fcgiwrap in foreground for error details..."
        fcgiwrap -f -s unix:/var/run/overpass/fcgiwrap.socket || log "Debug: fcgiwrap failed"
    fi
    
    # Check if socket was created
    if [ -S "/var/run/overpass/fcgiwrap.socket" ]; then
        log "Debug: Socket created successfully"
        ls -la /var/run/overpass/fcgiwrap.socket
        chmod 666 /var/run/overpass/fcgiwrap.socket 2>/dev/null || {
            log "Warning: Could not change fcgiwrap socket permissions"
        }
    else
        log "Debug: ERROR - Socket was not created!"
        ls -la /var/run/overpass/
    fi
    
    # Setup hybrid database structure
    setup_hybrid_structure
    
    # Start dispatcher from hybrid directory with increased memory limit
    log "Starting dispatcher with 6GB memory limit..."
    cd /tmp/overpass_db_hybrid
    
    # Start dispatcher with hybrid database directory and increased memory
    /opt/osm3s/bin/dispatcher --osm-base --db-dir=/tmp/overpass_db_hybrid --space=6000000000 &
    
    log "All services started. Monitoring processes..."
    
    # Improved process monitoring
    while true; do
        # Check if critical processes are running
        if ! pgrep nginx > /dev/null; then
            log "ERROR: nginx process died, restarting..."
            nginx &
        fi
        
        if ! pgrep fcgiwrap > /dev/null; then
            log "ERROR: fcgiwrap process died, restarting..."
            # Clean up socket first
            rm -f /var/run/overpass/fcgiwrap.socket
            # Ensure socket directory exists before restart
            mkdir -p /var/run/overpass
            chmod 755 /var/run/overpass
            log "Debug: Restarting fcgiwrap..."
            fcgiwrap -f -s unix:/var/run/overpass/fcgiwrap.socket &
        fi
        
        if ! pgrep dispatcher > /dev/null; then
            log "ERROR: dispatcher process died, restarting..."
            cd /tmp/overpass_db_hybrid
            /opt/osm3s/bin/dispatcher --osm-base --db-dir=/tmp/overpass_db_hybrid --space=6000000000 &
        fi
        
        sleep 30
    done
}

# Handle different commands
case "$1" in
    init)
        init_database
        exit 0
        ;;
    start-services)
        # Check if we need to initialize first
        if [ "$SKIP_INIT" != "true" ] && [ -n "$OVERPASS_PLANET_URL" ]; then
            init_database
        fi
        start_services
        ;;
    *)
        # Default behavior - initialize unless explicitly skipped
        if [ "$SKIP_INIT" != "true" ] && [ -n "$OVERPASS_PLANET_URL" ]; then
            init_database
        fi
        start_services
        ;;
esac