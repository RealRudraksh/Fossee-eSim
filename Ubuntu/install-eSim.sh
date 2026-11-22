#!/bin/bash
#=============================================================================
#          FILE: install-eSim.sh
# 
#         USAGE: ./install-eSim.sh --install 
#                            OR
#                ./install-eSim.sh --uninstall
#                
#   DESCRIPTION: Installation dispatcher script for eSim EDA Suite
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#       AUTHORS: Fahim Khan, Rahul Paknikar, Saurabh Bansode,
#                Sumanto Kar, Partha Singha Roy, Jayanth Tatineni,
#                Anshul Verma, Shiva Krishna Sangati, Harsha Narayana P
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#       CREATED: Wednesday 15 July 2015 15:26
#      REVISION: Sunday 24 May 2026 10:00
#=============================================================================

# Function to detect Ubuntu version and full version string
get_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        VERSION_ID=$(grep "^VERSION_ID" /etc/os-release | cut -d '"' -f 2)
    else
        echo "Error: /etc/os-release not found. Cannot determine OS version."
        exit 1
    fi
    FULL_VERSION=$(lsb_release -d 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' || echo "$VERSION_ID")
    echo "Detected Ubuntu Version: $VERSION_ID ($FULL_VERSION)"
}

# Function to choose and run the appropriate script
run_version_script() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-eSim-scripts"
    
    # Decide script based on version
    case $VERSION_ID in
        "22.04")
            if [[ "$FULL_VERSION" == "22.04.4" ]]; then
                SCRIPT="$SCRIPT_DIR/install-eSim-22.04.sh"
            else
                SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh"
            fi
            ;;
        "23.04")
            SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh"
            ;;
        "24.04")
            SCRIPT="$SCRIPT_DIR/install-eSim-24.04.sh"
            ;;
        "25.04"|"25.10"|"26.04")
            SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
            ;;
        *)
            # Check if version is 25 or above
            major_ver=$(echo "$VERSION_ID" | cut -d. -f1)
            if [ -n "$major_ver" ] && [ "$major_ver" -ge 25 ] 2>/dev/null; then
                echo "Notice: Detected Ubuntu version $VERSION_ID >= 25. Using Ubuntu 25.04+ installer script."
                SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
            else
                echo "Unsupported Ubuntu version: $VERSION_ID ($FULL_VERSION)"
                echo "eSim is currently supported on Ubuntu 22.04, 23.04, 24.04, and 25.04+."
                exit 1
            fi
            ;;
    esac

    # Run the script if found
    if [[ -f "$SCRIPT" ]]; then
        echo "Running script: $SCRIPT $ARGUMENT"
        bash "$SCRIPT" "$ARGUMENT"
    else
        echo "Error: Installation script not found: $SCRIPT"
        exit 1
    fi
}

####################################################################
#                   MAIN START FROM HERE                           #
####################################################################

### Checking if file is passed as argument to script
if [ "$#" -ne 1 ]; then
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1
fi

ARGUMENT=$1
if [[ "$ARGUMENT" != "--install" && "$ARGUMENT" != "--uninstall" ]]; then
    echo "Invalid argument: $ARGUMENT"
    echo "Usage: $0 --install | --uninstall"
    exit 1
fi

get_ubuntu_version
run_version_script
