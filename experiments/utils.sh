#
# Utility functions for experiment scripts
#

# Array to store process IDs
declare -a PIDS=()

# Add a process ID to the tracking list
track_process() {
    PIDS+=($1)
}

# Track the most recently started background process
track_last_process() {
    track_process $!
}

# Cleanup function to kill all tracked processes
cleanup() {
    echo "Cleaning up processes..."
    for pid in "${PIDS[@]}"; do
        if ps -p "$pid" > /dev/null; then
            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
        fi
    done
}

# Set up process tracking and cleanup
setup_process_tracking() {
    # Set trap to call cleanup function on script exit
    trap cleanup EXIT INT TERM
}

# Print error message to stderr
echoerr() { echo "$@" 1>&2; }