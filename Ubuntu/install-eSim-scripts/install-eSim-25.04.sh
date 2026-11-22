#!/bin/bash 
#=============================================================================
#          FILE: install-eSim.sh
# 
#         USAGE: ./install-eSim.sh --install 
#                            OR
#                ./install-eSim.sh --uninstall
#                
#   DESCRIPTION: Installation script for eSim EDA Suite
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#       AUTHORS: Fahim Khan, Rahul Paknikar, Saurabh Bansode,
#                Sumanto Kar, Partha Singha Roy, Harsha Narayana P, 
#                Jayanth Tatineni, Anshul Verma
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#       CREATED: Wednesday 15 July 2015 15:26
#      REVISION: Sunday 25 May 2025 17:40
#=============================================================================

# Determine actual calling user when script is run with sudo
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null)
[ -z "$TARGET_HOME" ] && TARGET_HOME="$HOME"

config_dir="$TARGET_HOME/.esim"
config_file="config.ini"
eSim_Home=$(pwd)
ngspiceFlag=0

## All Functions goes here

error_exit()
{

    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"

}


function createConfigFile
{

    # Creating config.ini file and adding configuration information
    # Check if config file is present
    if [ -d $config_dir ];then
        rm $config_dir/$config_file && touch $config_dir/$config_file
    else
        mkdir $config_dir && touch $config_dir/$config_file
    fi
    
    echo "[eSim]" >> $config_dir/$config_file
    echo "eSim_HOME = $eSim_Home" >> $config_dir/$config_file
    echo "LICENSE = %(eSim_HOME)s/LICENSE" >> $config_dir/$config_file
    echo "KicadLib = %(eSim_HOME)s/library/kicadLibrary.tar.xz" >> $config_dir/$config_file
    echo "IMAGES = %(eSim_HOME)s/images" >> $config_dir/$config_file
    echo "VERSION = %(eSim_HOME)s/VERSION" >> $config_dir/$config_file
    echo "MODELICA_MAP_JSON = %(eSim_HOME)s/library/ngspicetoModelica/Mapping.json" >> $config_dir/$config_file
   
}


function installNghdl
{

    echo "Installing NGHDL..........................."
    unzip -o nghdl.zip
    cd nghdl/
    chmod +x install-nghdl.sh

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
    
    # Extract SKY130 PDK
    tar -xJf library/sky130_fd_pr.tar.xz

    # Remove any previous sky130-fd-pdr instance, if any
    sudo rm -rf /usr/share/local/sky130_fd_pr

    # Copy SKY130 library
    echo "Copying SKY130 PDK........................."

    sudo mkdir -p /usr/share/local/
    sudo mv sky130_fd_pr /usr/share/local/

    # Change ownership from root to the user
    sudo chown -R $USER:$USER /usr/share/local/sky130_fd_pr/

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


function createDesktopStartScript
{    

    # Generating new esim-start.sh
    echo '#!/bin/bash' > esim-start.sh
    echo "cd $eSim_Home/src/frontEnd" >> esim-start.sh
    echo "source $config_dir/env/bin/activate" >> esim-start.sh
    echo "python3 Application.py" >> esim-start.sh

    # Make it executable
    sudo chmod 755 esim-start.sh
    # Copy esim start script
    sudo cp -vp esim-start.sh /usr/bin/esim
    # Remove local copy of esim start script
    rm esim-start.sh

    # Generating esim.desktop file
    echo "[Desktop Entry]" > esim.desktop
    echo "Version=1.0" >> esim.desktop
    echo "Name=eSim" >> esim.desktop
    echo "Comment=EDA Tool" >> esim.desktop
    echo "GenericName=eSim" >> esim.desktop
    echo "Keywords=eda-tools" >> esim.desktop
    echo "Exec=esim %u" >> esim.desktop
    echo "Terminal=true" >> esim.desktop
    echo "X-MultipleArgs=false" >> esim.desktop
    echo "Type=Application" >> esim.desktop
    getIcon="$config_dir/logo.png"
    echo "Icon=$getIcon" >> esim.desktop
    echo "Categories=Development;" >> esim.desktop
    echo "MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;video/webm;application/x-xpinstall;" >> esim.desktop
    echo "StartupNotify=true" >> esim.desktop

    # Make esim.desktop file executable
    sudo chmod 755 esim.desktop
    # Copy desktop icon file to share applications
    sudo cp -vp esim.desktop /usr/share/applications/
    # Copy desktop icon file to Desktop
    cp -vp esim.desktop $HOME/Desktop/

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Make esim.desktop file as trusted application
    gio set $HOME/Desktop/esim.desktop "metadata::trusted" true
    # Set Permission and Execution bit
    chmod a+x $HOME/Desktop/esim.desktop

    # Remove local copy of esim.desktop file
    rm esim.desktop

    set -e      # Re-enable exit on error
    trap error_exit ERR

    # Copying logo.png to .esim directory to access as icon
    cp -vp images/logo.png $config_dir

}


####################################################################
#                   MAIN START FROM HERE                           #
####################################################################

### Checking if file is passsed as argument to script

if [ "$#" -eq 1 ];then
    option=$1
else
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1;
fi

## Checking flags

if [ $option == "--install" ];then

    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap error_exit ERR


    echo "Enter proxy details if you are connected to internet thorugh proxy"
    
    echo -n "Is your internet connection behind proxy? (y/n): "
    read getProxy
    if [ $getProxy == "y" -o $getProxy == "Y" ];then
        echo -n 'Proxy Hostname :'
        read proxyHostname

        echo -n 'Proxy Port :'
        read proxyPort

        echo -n username@$proxyHostname:$proxyPort :
        read username

        echo -n 'Password :'
        read -s passwd

        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        unset ftp_proxy
        unset FTP_PROXY

        export http_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export https_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export https_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export HTTP_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort
        export HTTPS_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort
        export ftp_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export FTP_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort

        echo "Install with proxy"

    elif [ $getProxy == "n" -o $getProxy == "N" ];then
        echo "Install without proxy"
    
    else
        echo "Please select the right option"
        exit 0    
    fi

    # Calling functions
    createConfigFile
    installDependency
    installKicad
    copyKicadLibrary
    installNghdl
    installSky130Pdk
    createDesktopStartScript

    if [ $? -ne 0 ];then
        echo -e "\n\n\nERROR: Unable to install required packages. Please check your internet connection.\n\n"
        exit 0
    fi

    echo "-----------------eSim Installed Successfully-----------------"
    echo "Type \"esim\" in Terminal to launch it"
    echo "or double click on \"eSim\" icon placed on Desktop"


elif [ $option == "--uninstall" ];then
    echo -n "Are you sure? It will remove eSim completely including KiCad, Makerchip, NGHDL and SKY130 PDK along with their models and libraries (y/n):"
    read getConfirmation
    if [ $getConfirmation == "y" -o $getConfirmation == "Y" ];then
        echo "Removing eSim............................"
        sudo rm -rf $HOME/.esim $HOME/Desktop/esim.desktop /usr/bin/esim /usr/share/applications/esim.desktop
        echo "Removing KiCad..........................."
        sudo apt purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
        sudo rm -rf /usr/share/kicad
	sudo rm /etc/apt/sources.list.d/kicad*
        rm -rf $HOME/.config/kicad/6.0

        echo "Removing Virtual env......................."
        sudo rm -r $config_dir/env

        echo "Removing SKY130 PDK......................"
        sudo rm -R /usr/share/local/sky130_fd_pr

        echo "Removing NGHDL..........................."
        rm -rf library/modelParamXML/Nghdl/*
        rm -rf library/modelParamXML/Ngveri/*
        cd nghdl/
        if [ $? -eq 0 ];then
        	chmod +x install-nghdl.sh
    	    ./install-nghdl.sh --uninstall
    	    cd ../
    	    rm -rf nghdl
            if [ $? -eq 0 ];then
                echo -e "----------------eSim Uninstalled Successfully----------------"
            else
                echo -e "\nError while removing some files/directories in \"nghdl\". Please remove it manually"
            fi
        else
            echo -e "\nCannot find \"nghdl\" directory. Please remove it manually"
        fi
    elif [ $getConfirmation == "n" -o $getConfirmation == "N" ];then
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
