#!/bin/bash 
#=============================================================================
#          FILE: install-eSim-25.04.sh
# 
#         USAGE: ./install-eSim-25.04.sh --install 
#                            OR
#                ./install-eSim-25.04.sh --uninstall
#                
#   DESCRIPTION: Installation script for eSim EDA Suite on Ubuntu 25.04 and above
#
#       OPTIONS: ---
#  REQUIREMENTS: Ubuntu 25.04+, Python 3.13, KiCad 8.0, NGHDL
#          BUGS: ---
#         NOTES: Includes fixes for PEP 668, Python 3.13 PyQt5 compatibility,
#                KiCad 8.0 configuration, GTK3 migration, and LLVM 18 backend.
#       AUTHORS: Fahim Khan, Rahul Paknikar, Saurabh Bansode,
#                Sumanto Kar, Partha Singha Roy, Harsha Narayana P, 
#                Jayanth Tatineni, Anshul Verma
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#       CREATED: Wednesday 15 July 2015 15:26
#      REVISION: Sunday 24 May 2026 10:00
#=============================================================================

# Determine actual calling user when script is run with sudo
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null)
[ -z "$TARGET_HOME" ] && TARGET_HOME="$HOME"

config_dir="$TARGET_HOME/.esim"
config_file="config.ini"
eSim_Home=$(pwd)
ngspiceFlag=0

## All Functions go here

error_exit()
{
    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"
    exit 1
}

function createConfigFile
{
    echo "Creating eSim configuration directory and config.ini..."
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi

    cat <<EOF > "$config_dir/$config_file"
[eSim]
eSim_HOME = $eSim_Home
LICENSE = %(eSim_HOME)s/LICENSE
KicadLib = %(eSim_HOME)s/library/kicadLibrary.tar.xz
IMAGES = %(eSim_HOME)s/images
VERSION = %(eSim_HOME)s/VERSION
MODELICA_MAP_JSON = %(eSim_HOME)s/library/ngspicetoModelica/Mapping.json
EOF

    chown -R "$TARGET_USER:$TARGET_USER" "$config_dir"
}

function installDependency
{
    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    echo "Updating apt index files..................."
    sudo apt-get update
    
    set -e      # Re-enable exit on error
    trap error_exit ERR
    
    echo "Installing system Python and GUI dependencies for Ubuntu 25.04..."
    sudo apt-get install -y \
        python3-venv \
        python3-virtualenv \
        python3-pip \
        python3-pyqt5 \
        python3-matplotlib \
        python3-numpy \
        python3-psutil \
        python3-setuptools \
        xterm

    echo "Creating virtual environment with system site packages enabled..."
    rm -rf "$config_dir/env"
    # Python 3.13 / PEP 668: --system-site-packages enables access to Ubuntu's native python3-pyqt5
    # without compiling PyQt5 from source on PyPI (which has no wheels for Python 3.13)
    python3 -m venv --system-site-packages "$config_dir/env" || virtualenv --system-site-packages "$config_dir/env"
    
    echo "Starting the virtual env..................."
    source "$config_dir/env/bin/activate"

    echo "Upgrading Pip inside virtual environment..."
    "$config_dir/env/bin/pip" install --upgrade pip

    # Install NgVeri pure-python dependencies inside virtual environment
    echo "Installing Watchdog........................"
    "$config_dir/env/bin/pip" install watchdog

    echo "Installing Hdlparse........................"
    "$config_dir/env/bin/pip" install hdlparse

    echo "Installing Makerchip......................."
    "$config_dir/env/bin/pip" install makerchip-app

    echo "Installing SandPiper Saas.................."
    "$config_dir/env/bin/pip" install sandpiper-saas

    # Adjust permissions of virtualenv for the target user
    chown -R "$TARGET_USER:$TARGET_USER" "$config_dir"
}

function installKicad
{
    echo "Installing KiCad..........................."

    # Check if KiCad 8 is already installed
    if dpkg -s kicad &>/dev/null; then
        installed_version=$(dpkg-query -W -f='${Version}' kicad | cut -d'.' -f1)
        if [[ "$installed_version" == "8" ]]; then
            echo "KiCad 8.0 is already installed."
            return 0
        else
            echo "A different version of KiCad ($installed_version) is installed."
            read -p "Do you want to remove it and install KiCad 8.0? (yes/no): " response
            if [[ "$response" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
                echo "Removing KiCad $installed_version..."
                sudo apt-get remove --purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
                sudo apt-get autoremove -y
            else
                echo "Exiting installation. KiCad $installed_version remains installed."
                exit 1
            fi
        fi
    fi

    # KiCad 8 PPA configuration with fallback
    kicadppa="kicad/kicad-8.0-releases"
    if ! grep -q "^deb .*${kicadppa}" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "Adding KiCad PPA to local apt repository: $kicadppa"
        sudo add-apt-repository -y "ppa:$kicadppa" || echo "Note: PPA not available for this release, using Ubuntu official repositories..."
        sudo apt-get update
    else
        echo "KiCad PPA is already present in sources."
    fi

    # Install KiCad packages without fragile version pinning
    sudo apt-get install -y --no-install-recommends kicad kicad-footprints kicad-symbols kicad-templates

    echo "KiCad installation completed successfully!"
}

function copyKicadLibrary
{
    echo "Configuring custom KiCad Library for eSim..."

    if [ -f "library/kicadLibrary.tar.xz" ]; then
        tar -xJf library/kicadLibrary.tar.xz
    else
        echo "Warning: library/kicadLibrary.tar.xz not found. Skipping extraction."
        return 0
    fi

    # KiCad 8 configuration directory
    kicad_config_dir="$TARGET_HOME/.config/kicad/8.0"
    if [ ! -d "$kicad_config_dir" ]; then
        mkdir -p "$kicad_config_dir"
    fi

    # Copy symbol table for eSim custom symbols into KiCad 8 config directory
    if [ -f "kicadLibrary/template/sym-lib-table" ]; then
        cp kicadLibrary/template/sym-lib-table "$kicad_config_dir/"
        echo "eSim sym-lib-table copied into $kicad_config_dir"
    fi

    # Ensure KiCad system symbols directory exists and copy custom symbols
    kicad_symbols_dir="/usr/share/kicad/symbols"
    sudo mkdir -p "$kicad_symbols_dir"

    if [ -d "kicadLibrary/eSim-symbols" ]; then
        sudo cp -r kicadLibrary/eSim-symbols/* "$kicad_symbols_dir/"
        echo "eSim custom symbols copied to $kicad_symbols_dir"
    fi

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command
    
    # Remove extracted KiCad Library - not needed anymore
    rm -rf kicadLibrary

    set -e      # Re-enable exit on error
    trap error_exit ERR

    # Change ownership of config files to the target user
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/kicad"
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$kicad_symbols_dir"
}

function installNghdl
{
    echo "Installing NGHDL..........................."
    if [ ! -f "nghdl.zip" ]; then
        echo "Warning: nghdl.zip not found in current directory. Skipping NGHDL installation."
        return 0
    fi

    unzip -o nghdl.zip
    cd nghdl/
    chmod +x install-nghdl.sh

    # Patch dispatcher in install-nghdl.sh to support Ubuntu 25.04+
    if ! grep -q '"25.04"' install-nghdl.sh 2>/dev/null; then
        sed -i 's/"24.04")/"24.04"|"25.04"|"25.10"|"26.04")/' install-nghdl.sh 2>/dev/null || true
    fi

    # Ensure 25.04 script exists in nghdl with LLVM 18 and GTK3 fixes
    if [ ! -f "install-nghdl-scripts/install-nghdl-25.04.sh" ]; then
        if [ -f "install-nghdl-scripts/install-nghdl-24.04.sh" ]; then
            cp "install-nghdl-scripts/install-nghdl-24.04.sh" "install-nghdl-scripts/install-nghdl-25.04.sh"
            # Fix 1: Use LLVM 18 instead of LLVM 20 for GHDL 4.1.0 compatibility
            sed -i 's/sudo apt install -y llvm llvm-dev/sudo apt install -y llvm-18 llvm-18-dev/' "install-nghdl-scripts/install-nghdl-25.04.sh"
            sed -i 's/--with-llvm-config=\/usr\/bin\/llvm-config/--with-llvm-config=\/usr\/bin\/llvm-config-18/' "install-nghdl-scripts/install-nghdl-25.04.sh"
            # Fix 2: Remove dropped libcanberra-gtk-module (GTK2)
            sed -i 's/libcanberra-gtk-module libcanberra-gtk3-module/libcanberra-gtk3-module/' "install-nghdl-scripts/install-nghdl-25.04.sh"
            # Fix 3: Use libncurses-dev instead of deprecated libncurses5-dev
            sed -i 's/libncurses5-dev/libncurses-dev/' "install-nghdl-scripts/install-nghdl-25.04.sh"
        fi
    fi

    # Do not trap on error of any command. Let NGHDL script handle its own errors.
    trap "" ERR

    ./install-nghdl.sh --install       # Install NGHDL
        
    # Set trap again to error_exit function to exit on errors
    trap error_exit ERR

    ngspiceFlag=1
    cd ../
}

function installSky130Pdk
{
    echo "Installing SKY130 PDK......................"
    
    if [ -f "library/sky130_fd_pr.tar.xz" ]; then
        echo "Extracting SKY130 PDK archive..."
        tar -xJf library/sky130_fd_pr.tar.xz
        sudo rm -rf /usr/share/local/sky130_fd_pr
        sudo mkdir -p /usr/share/local/
        sudo mv sky130_fd_pr /usr/share/local/
        sudo chown -R "$TARGET_USER:$TARGET_USER" /usr/share/local/sky130_fd_pr/
        echo "SKY130 PDK installed successfully at /usr/share/local/sky130_fd_pr"
    elif [ -d "/usr/share/local/sky130_fd_pr" ]; then
        echo "SKY130 PDK is already present at /usr/share/local/sky130_fd_pr"
    else
        echo "Notice: library/sky130_fd_pr.tar.xz not found. Skipping local extraction."
    fi
}

function createDesktopStartScript
{    
    echo "Creating desktop launcher and start script..."

    # Generating new esim-start.sh
    cat <<EOF > esim-start.sh
#!/bin/bash
cd "$eSim_Home/src/frontEnd"
source "$config_dir/env/bin/activate"
python3 Application.py
EOF

    # Make it executable and copy to /usr/bin/esim
    sudo chmod 755 esim-start.sh
    sudo cp -vp esim-start.sh /usr/bin/esim
    rm esim-start.sh

    # Generating esim.desktop file
    cat <<EOF > esim.desktop
[Desktop Entry]
Version=1.0
Name=eSim
Comment=EDA Tool
GenericName=eSim
Keywords=eda-tools
Exec=esim %u
Terminal=true
X-MultipleArgs=false
Type=Application
Icon=$config_dir/logo.png
Categories=Development;
StartupNotify=true
EOF

    # Make esim.desktop file executable and copy
    sudo chmod 755 esim.desktop
    sudo cp -vp esim.desktop /usr/share/applications/

    # Copy to User Desktop if desktop folder exists
    if [ -d "$TARGET_HOME/Desktop" ]; then
        cp -vp esim.desktop "$TARGET_HOME/Desktop/"
        chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/Desktop/esim.desktop"
        chmod a+x "$TARGET_HOME/Desktop/esim.desktop"
        gio set "$TARGET_HOME/Desktop/esim.desktop" "metadata::trusted" true 2>/dev/null || true
    fi
    rm esim.desktop

    # Copying logo.png to .esim directory to access as icon
    if [ -f "images/logo.png" ]; then
        cp -vp images/logo.png "$config_dir/"
        chown "$TARGET_USER:$TARGET_USER" "$config_dir/logo.png"
    fi
}

####################################################################
#                   MAIN START FROM HERE                           #
####################################################################

### Checking if file is passed as argument to script
if [ "$#" -eq 1 ]; then
    option=$1
else
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1
fi

## Checking flags
if [ "$option" == "--install" ]; then

    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap error_exit ERR

    echo "Enter proxy details if you are connected to internet through proxy"
    echo -n "Is your internet connection behind proxy? (y/n): "
    read getProxy
    if [ "$getProxy" == "y" -o "$getProxy" == "Y" ]; then
        echo -n 'Proxy Hostname :'
        read proxyHostname
        echo -n 'Proxy Port :'
        read proxyPort
        echo -n username@$proxyHostname:$proxyPort :
        read username
        echo -n 'Password :'
        read -s passwd

        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ftp_proxy FTP_PROXY

        export http_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export https_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export HTTP_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort
        export HTTPS_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort
        export ftp_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export FTP_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort

        echo "Install with proxy"
    elif [ "$getProxy" == "n" -o "$getProxy" == "N" ]; then
        echo "Install without proxy"
    else
        echo "Please select the right option"
        exit 0    
    fi

    # Calling functions in sequence
    createConfigFile
    installDependency
    installKicad
    copyKicadLibrary
    installNghdl
    installSky130Pdk
    createDesktopStartScript

    echo "-----------------eSim Installed Successfully-----------------"
    echo "Type \"esim\" in Terminal to launch it"
    echo "or double click on \"eSim\" icon placed on Desktop"

elif [ "$option" == "--uninstall" ]; then
    echo -n "Are you sure? It will remove eSim completely including KiCad, Makerchip, NGHDL and SKY130 PDK along with their models and libraries (y/n):"
    read getConfirmation
    if [ "$getConfirmation" == "y" -o "$getConfirmation" == "Y" ]; then
        echo "Removing eSim............................"
        sudo rm -rf "$config_dir" "$TARGET_HOME/Desktop/esim.desktop" /usr/bin/esim /usr/share/applications/esim.desktop
        
        echo "Removing KiCad..........................."
        sudo apt-get purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates 2>/dev/null || true
        sudo rm -rf /usr/share/kicad
        sudo rm -f /etc/apt/sources.list.d/kicad*
        rm -rf "$TARGET_HOME/.config/kicad"

        echo "Removing Virtual env......................."
        rm -rf "$config_dir/env"

        echo "Removing SKY130 PDK......................"
        sudo rm -rf /usr/share/local/sky130_fd_pr

        echo "Removing NGHDL..........................."
        rm -rf library/modelParamXML/Nghdl/* 2>/dev/null || true
        rm -rf library/modelParamXML/Ngveri/* 2>/dev/null || true
        if [ -d "nghdl" ]; then
            cd nghdl/
            chmod +x install-nghdl.sh 2>/dev/null || true
            ./install-nghdl.sh --uninstall 2>/dev/null || true
            cd ../
            rm -rf nghdl
        fi
        echo -e "----------------eSim Uninstalled Successfully----------------"
    elif [ "$getConfirmation" == "n" -o "$getConfirmation" == "N" ]; then
        exit 0
    else 
        echo "Please select the right option."
        exit 0
    fi
else 
    echo "Please select the proper operation."
    echo "--install"
    echo "--uninstall"
fi
