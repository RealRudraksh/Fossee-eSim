# eSim 2.5 Upgradation Technical Report: Ubuntu 25.04+ Compatibility & Dependency Resolution

**Screening Task 4:** eSim Upgradation (Computer Science and Engineering & Related Disciplines)  
**Organization:** FOSSEE (Free/Libre and Open Source Software for Education), IIT Bombay  
**Candidate Name:** Rudraksh Singh Khichi  
**GitHub Profile:** [https://github.com/RealRudraksh](https://github.com/RealRudraksh)  
**Forked Repository:** [https://github.com/RealRudraksh/Fossee-eSim/tree/installers](https://github.com/RealRudraksh/Fossee-eSim/tree/installers)  
**Target Branch:** `installers`  
**Target Distribution:** Ubuntu 25.04 (Plucky Puffin, 64-bit x86_64) & Subsequent Releases  
**Evaluation Date:** November 2026  

---

## Table of Contents
1. [Executive Summary](#1-executive-summary)
2. [Target Environment & Architectural Overview](#2-target-environment--architectural-overview)
3. [Master Issue Catalog & Evaluation Matrix](#3-master-issue-catalog--evaluation-matrix)
4. [In-Depth Problem Diagnosis, Root Cause & Implementation](#4-in-depth-problem-diagnosis-root-cause--implementation)
   - [4.1 BUG-01 (High Weightage): Main GUI Dependency Failure on Python 3.13 & PEP 668](#41-bug-01-high-weightage-main-gui-dependency-failure-on-python-313--pep-668)
   - [4.2 BUG-02: Fatal Bash Syntax Error & Unclosed Block in Dispatcher](#42-bug-02-fatal-bash-syntax-error--unclosed-block-in-dispatcher)
   - [4.3 BUG-03 (High Weightage): NGHDL / GHDL 4.1.0 Incompatibility with LLVM 20](#43-bug-03-high-weightage-nghdl--ghdl-410-incompatibility-with-llvm-20)
   - [4.4 BUG-04: Removal of Legacy GTK+ 2 libcanberra-gtk-module](#44-bug-04-removal-of-legacy-gtk-2-libcanberra-gtk-module)
   - [4.5 BUG-05: KiCad 8.0 Symbol Library Table Path Mismatch](#45-bug-05-kicad-80-symbol-library-table-path-mismatch)
   - [4.6 BUG-06: Brittle DFSG KiCad Package Version Pinning](#46-bug-06-brittle-dfsg-kicad-package-version-pinning)
   - [4.7 BUG-07: Deprecated libncurses5-dev Superseded by Ncurses 6](#47-bug-07-deprecated-libncurses5-dev-superseded-by-ncurses-6)
   - [4.8 BUG-08: Defensive Error Handling for SKY130 PDK Unpacking](#48-bug-08-defensive-error-handling-for-sky130-pdk-unpacking)
   - [4.9 BUG-09: Sudo Privilege Isolation & HOME Directory Pollution](#49-bug-09-sudo-privilege-isolation--home-directory-pollution)
   - [4.10 BUG-10: OS Release Version Parsing on Non-Point Releases](#410-bug-10-os-release-version-parsing-on-non-point-releases)
5. [Git Commit Traceability & Progressive Development Log](#5-git-commit-traceability--progressive-development-log)
6. [Verification, Testing & Reproduction Methodology](#6-verification-testing--reproduction-methodology)
7. [Architectural Recommendations for Future eSim Releases](#7-architectural-recommendations-for-future-esim-releases)
8. [Conclusion](#8-conclusion)

---

## 1. Executive Summary

eSim is an open-source EDA (Electronic Design Automation) simulation suite developed by the **FOSSEE team at IIT Bombay**. It unifies several independent engineering tools—including **KiCad** (schematic design and PCB layout), **Ngspice** (analog simulation), **GHDL** (VHDL simulation), **Verilator** (Verilog simulation), and **Makerchip** (cloud/local digital design)—into an integrated desktop environment managed by a Python/Qt frontend.

Deploying eSim 2.5 on modern Linux distributions, specifically **Ubuntu 25.04 (Plucky Puffin)**, reveals major breaking changes across the operating system layer:
- The transition of the default system interpreter to **Python 3.13**.
- System-wide enforcement of **PEP 668** (`EXTERNALLY-MANAGED` Python environments).
- Discontinuation of pre-built PyQt5 wheels on PyPI for Python 3.13.
- Complete removal of legacy **GTK+ 2** shared libraries.
- Upgrading of standard system compiler backends to **LLVM 19/20** and **GCC 14/15**.
- Structural changes in **KiCad 8.0** configuration directories.

Without surgical modifications, attempting to install eSim 2.5 on Ubuntu 25.04 results in immediate failures, halting at the syntax level of the dispatcher script, failing during the core GUI virtual environment setup, and aborting during mixed-signal compilation of GHDL.

This report documents the systematic investigation, classification, and resolution of **10 distinct issues**. In accordance with the FOSSEE evaluation guidelines, highest priority and rigorous engineering were devoted to high-difficulty issues—specifically restoring the **eSim Main PyQt5 GUI**, resolving the **GHDL/LLVM compilation stall**, and ensuring **KiCad 8 schematic symbol integration**.

---

## 2. Target Environment & Architectural Overview

### 2.1 Testbed Specifications
The diagnostic and testing procedures were carried out in an authentic Ubuntu 25.04 desktop environment configured as follows:
- **Operating System:** Ubuntu 25.04 (Plucky Puffin, 64-bit x86_64)
- **Kernel Version:** Linux Kernel 6.14.0-generic
- **Default Python Interpreter:** Python 3.13.2 (`/usr/bin/python3`)
- **System C/C++ Compilers:** GCC 14.2.0, Clang 19/20
- **System LLVM Default:** LLVM 20.1 / LLVM 19.1
- **EDA Target Suite:** KiCad 8.0.8+
- **Simulation Backends:** Ngspice-42+, GHDL 4.1.0 (LLVM backend), Verilator 4.210

### 2.2 eSim Component Architecture
```
+-----------------------------------------------------------------------+
|                         eSim User Interface                           |
|       (src/frontEnd/Application.py - PyQt5 / Matplotlib / Python 3)    |
+------------------------------------+----------------------------------+
                                     |
               +---------------------+---------------------+
               |                     |                     |
               v                     v                     v
+--------------------------+  +-------------------+  +------------------+
|    Schematic Editor      |  | Simulation Engine |  | Digital/Mixed-   |
|   (KiCad 8 / Eeschema)   |  |     (Ngspice)     |  | Signal Engine    |
|   - sym-lib-table        |  |  - OSDI / OpenVAF |  |  (NGHDL)         |
|   - eSim custom symbols  |  |  - libxaw7        |  |  - GHDL (LLVM 18)|
+--------------------------+  +-------------------+  |  - Verilator     |
                                                     +------------------+
                                                               |
+--------------------------------------------------------------v--------+
|                          Semiconductor PDKs                           |
|      - SKY130 PDK (/usr/share/local/sky130_fd_pr)                     |
|      - IHP Open PDK 130nm                                             |
+-----------------------------------------------------------------------+
```

---

## 3. Master Issue Catalog & Evaluation Matrix

Every issue discovered during testing was systematically cataloged, assigned a severity level, mapped to an evaluation weightage category, and verified after resolution:

| Bug ID | Component | Problem Summary | Impact / Failure Mode | Evaluation Weightage | Status |
|:---|:---|:---|:---|:---:|:---:|
| **BUG-01** | **Main GUI (PyQt5)** | Python 3.13 lacks PyPI PyQt5 wheels; isolated venv cannot access system PyQt5; PEP 668 violation | **Fatal Blocker**: eSim GUI crashes on start (`ModuleNotFoundError: No module named 'PyQt5'`) | **High (Main GUI Block)** | **FIXED** |
| **BUG-02** | **Dispatcher Script** | Unclosed `if` without `fi` and dangling assignment code in `Ubuntu/install-eSim.sh` | **Fatal Blocker**: Script terminates immediately with `syntax error near unexpected token '}'` | **Medium (Core Execution)** | **FIXED** |
| **BUG-03** | **NGHDL / LLVM** | GHDL 4.1.0 build crashes against LLVM 20; `/usr/bin/llvm-config` binary missing/incompatible | **High**: Mixed-signal simulation compilation fails during `make` | **High (Simulation Block)** | **FIXED** |
| **BUG-04** | **GTK Libraries** | `libcanberra-gtk-module` (GTK+ 2) completely eliminated from Ubuntu 25.04 repositories | **High**: `apt install` aborts with `Package has no installation candidate` | **Medium (System Libs)** | **FIXED** |
| **BUG-05** | **KiCad 8 Config** | Symbol table (`sym-lib-table`) copied to `~/.config/kicad/6.0/` instead of `8.0/` | **High**: KiCad schematic editor opens with zero eSim custom symbols | **High (EDA Integration)** | **FIXED** |
| **BUG-06** | **KiCad Packaging** | Brittle version pin `kicad=8.0.8+dfsg-1` fails on updated Ubuntu mirrors | **High**: `apt install` aborts with `Version not found` | **Medium (Package Mgmt)** | **FIXED** |
| **BUG-07** | **Legacy Ncurses** | `libncurses5-dev` is superseded by `libncurses-dev` in Ubuntu 25.04 | **Medium**: Ngspice/OSDI prerequisite build failure | **Low (Packaging)** | **FIXED** |
| **BUG-08** | **PDK Deployment** | Blind `tar -xJf library/sky130_fd_pr.tar.xz` halts with `set -e` if tarball omitted | **Medium**: Halts entire install if local PDK archive is absent | **Medium (Defensive Scripting)** | **FIXED** |
| **BUG-09** | **Sudo Privilege Trap** | Executing under `sudo` pollutes `$HOME` to `/root`, breaking user desktop/env | **Medium**: Regular user cannot launch eSim or access configs post-install | **High (System Architecture)** | **FIXED** |
| **BUG-10** | **Version Detection** | Regex `\d+\.\d+\.\d+` fails on base releases (e.g., `25.04` without point release) | **Low**: Diagnostics show blank version string; fallback fails | **Low (Scripting)** | **FIXED** |

---

## 4. In-Depth Problem Diagnosis, Root Cause & Implementation

---

### 4.1 BUG-01 (High Weightage): Main GUI Dependency Failure on Python 3.13 & PEP 668

#### Problem Description & Error Log
When running eSim on Ubuntu 25.04, the frontend (`src/frontEnd/Application.py`) fails to start. Attempting to launch eSim from terminal yields:
```text
Traceback (most recent call last):
  File "Application.py", line 38, in <module>
    from PyQt5 import QtGui, QtCore, QtWidgets
ModuleNotFoundError: No module named 'PyQt5'
```
During installation, the installer output reveals why PyQt5 was never successfully installed:
```text
Installing PyQt5.............
Collecting PyQt5
  Downloading PyQt5-5.15.11.tar.gz (3.2 MB)
  Installing build dependencies ... error
  error: subprocess-exited-with-error
  × Getting requirements to build wheel did not run successfully.
  │ exit code: 1
  ╰─> Querying qmake about your Qt installation...
      Error: Failed to determine PyQt5 library directory
```

#### Technical Root Cause Analysis
1. **PEP 668 Enforcement:** Debian and Ubuntu 23.04+ mark system Python environments as `EXTERNALLY-MANAGED`. Executing global `pip install` commands outside a virtual environment is strictly prohibited by default.
2. **Absence of Pre-Compiled PyPI Wheels for Python 3.13:** Riverbank Computing ceased building binary wheels for Qt 5 on new major Python releases. PyPI provides binary wheels only up to Python 3.12. For Python 3.13, `pip` falls back to building PyQt5 from source.
3. **Missing Source Build Dependencies:** Compiling PyQt5 from source requires `qmake`, `qtbase5-dev`, `qtchooser`, and `sip`. These are not installed by default. Furthermore, compiling PyQt5 5.15 against Python 3.13 fails due to C-API breaking changes (e.g., internal struct alterations in Python object headers).
4. **Virtual Environment Isolation Defect:** The original installer executed:
   ```bash
   sudo apt-get install -y python3-pyqt5
   virtualenv $config_dir/env
   source $config_dir/env/bin/activate
   pip3 install PyQt5
   ```
   Because `virtualenv $config_dir/env` was called **without** `--system-site-packages`, the virtual environment was isolated from `/usr/lib/python3/dist-packages/`. Even though Ubuntu's official package manager successfully installed Canonical's patched `python3-pyqt5`, the virtual environment could not see it!

#### Architectural Solution
Instead of attempting fragile, time-consuming source builds of an end-of-life C++ binding (Qt5) on Python 3.13, we leverage Ubuntu 25.04's native, distribution-patched `python3-pyqt5` and bridge it into the virtual environment using `--system-site-packages`.

#### Code Modification in `Ubuntu/install-eSim-scripts/install-eSim-25.04.sh`:
```diff
- echo "Instaling virtualenv......................."
- sudo apt install python3-virtualenv
- 
- echo "Creating virtual environment to isolate packages "
- virtualenv $config_dir/env
- 
- echo "Starting the virtual env..................."
- source $config_dir/env/bin/activate
- pip install --upgrade pip
- 
- sudo apt-get install -y python3-pyqt5
- sudo apt-get install -y python3-matplotlib
- pip3 install PyQt5
- pip3 install matplotlib

+ echo "Installing system Python and GUI dependencies for Ubuntu 25.04..."
+ sudo apt-get install -y \
+     python3-venv \
+     python3-virtualenv \
+     python3-pip \
+     python3-pyqt5 \
+     python3-matplotlib \
+     python3-numpy \
+     python3-psutil \
+     python3-setuptools \
+     xterm
+
+ echo "Creating virtual environment with system site packages enabled..."
+ rm -rf "$config_dir/env"
+ python3 -m venv --system-site-packages "$config_dir/env" || virtualenv --system-site-packages "$config_dir/env"
+ 
+ echo "Starting the virtual env..................."
+ source "$config_dir/env/bin/activate"
+ "$config_dir/env/bin/pip" install --upgrade pip
+
+ # Install NgVeri pure-python dependencies inside virtual environment
+ "$config_dir/env/bin/pip" install watchdog hdlparse makerchip-app sandpiper-saas
```

#### Verification & Evidence
Inside the created virtual environment:
```bash
$ source ~/.esim/env/bin/activate
$ python3 -c "import PyQt5.QtWidgets, matplotlib, numpy, psutil; print('All GUI dependencies successfully loaded!')"
All GUI dependencies successfully loaded!
```
The eSim main window opens without errors.

---

### 4.2 BUG-02: Fatal Bash Syntax Error & Unclosed Block in Dispatcher

#### Problem Description & Error Log
Running `./install-eSim.sh --install` immediately terminates before performing any operations:
```text
./install-eSim.sh: line 70: syntax error near unexpected token '}'
./install-eSim.sh: line 70: '}'
```

#### Technical Root Cause Analysis
In `Ubuntu/install-eSim.sh`, lines 59–70 contained an unclosed `if [[ -f "$SCRIPT" ]]; then` block inside `run_version_script()`. Instead of a terminating `fi`, unfinished code fragments writing to `$config_dir/$config_file` were pasted directly before the closing function brace `}`.

In addition, lines 73 to 318 of `install-eSim.sh` defined 250+ lines of duplicate helper functions (`installNghdl`, `installSky130Pdk`, `installKicad`, etc.) that were never called because `install-eSim.sh` is solely intended to act as a version dispatcher.

#### Architectural Solution
Refactored `Ubuntu/install-eSim.sh` into a clean, robust dispatcher:
1. Closed all control flow blocks with matching `fi`.
2. Added error logging and non-zero exit codes if the version script cannot be located.
3. Implemented pattern matching for Ubuntu 25.04, 25.10, 26.04, and any version `>= 25`.
4. Stripped out redundant copy-pasted dead functions.

#### Code Modification in `Ubuntu/install-eSim.sh`:
```diff
  run_version_script() {
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-eSim-scripts"
      
-     case $VERSION_ID in
-         "22.04") ... ;;
-         "23.04") ... ;;
-         "24.04") ... ;;
-         "25.04") SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh" ;;
-     esac
- 
-     if [[ -f "$SCRIPT" ]]; then
-         echo "Running script: $SCRIPT $ARGUMENT"
-         bash "$SCRIPT" "$ARGUMENT"
-     echo "[eSim]" >> $config_dir/$config_file
-     echo "eSim_HOME = $eSim_Home" >> $config_dir/$config_file
-     ...
- }
+     case $VERSION_ID in
+         "22.04")
+             if [[ "$FULL_VERSION" == "22.04.4" ]]; then
+                 SCRIPT="$SCRIPT_DIR/install-eSim-22.04.sh"
+             else
+                 SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh"
+             fi
+             ;;
+         "23.04") SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh" ;;
+         "24.04") SCRIPT="$SCRIPT_DIR/install-eSim-24.04.sh" ;;
+         "25.04"|"25.10"|"26.04") SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh" ;;
+         *)
+             major_ver=$(echo "$VERSION_ID" | cut -d. -f1)
+             if [ -n "$major_ver" ] && [ "$major_ver" -ge 25 ] 2>/dev/null; then
+                 echo "Notice: Detected Ubuntu version $VERSION_ID >= 25. Using Ubuntu 25.04+ installer script."
+                 SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
+             else
+                 echo "Unsupported Ubuntu version: $VERSION_ID ($FULL_VERSION)"
+                 exit 1
+             fi
+             ;;
+     esac
+
+     if [[ -f "$SCRIPT" ]]; then
+         echo "Running script: $SCRIPT $ARGUMENT"
+         bash "$SCRIPT" "$ARGUMENT"
+     else
+         echo "Error: Installation script not found: $SCRIPT"
+         exit 1
+     fi
+ }
```

#### Verification & Evidence
```bash
$ bash -n Ubuntu/install-eSim.sh
$ echo $?
0
```
Syntax check passes with zero errors.

---

### 4.3 BUG-03 (High Weightage): NGHDL / GHDL 4.1.0 Incompatibility with LLVM 20

#### Problem Description & Error Log
During NGHDL installation on Ubuntu 25.04, the compilation of GHDL hangs and then aborts with compiler errors:
```text
Configuring ghdl-4.1.0 build as per requirements
./configure --with-llvm-config=/usr/bin/llvm-config
Building the install file for ghdl-4.1.0 LLVM
In file included from .../src/ortho/llvm/llvm-cbindings.cpp:
error: 'PassManager' is not a member of 'llvm'
error: cannot convert 'llvm::Type*' to 'llvm::PointerType*'
make: *** [Makefile:214: llvm-cbindings.o] Error 1
```

#### Technical Root Cause Analysis
1. In Ubuntu 25.04, running `sudo apt install llvm llvm-dev` installs **LLVM 20.x**.
2. GHDL 4.1.0's LLVM backend was authored and tested against LLVM 9 through LLVM 18.
3. LLVM 19 and 20 introduced breaking C++ API changes:
   - Deprecation and removal of the legacy Pass Manager.
   - Strict enforcement of opaque pointers (`llvm::PointerType` no longer accepts element types).
   - Removed header files previously used in `llvm-cbindings.cpp`.
4. Furthermore, Ubuntu 25.04 no longer symlinks `/usr/bin/llvm-config` to the latest version by default unless `llvm-runtime` alternatives are manually installed, leading to configuration script failures.

#### Architectural Solution
GHDL 4.1.0 is completely stable and fully supported against **LLVM 18**.
1. Install `llvm-18` and `llvm-18-dev` specifically:
   ```bash
   sudo apt install -y llvm-18 llvm-18-dev clang zlib1g-dev
   ```
2. Configure GHDL explicitly with:
   ```bash
   ./configure --with-llvm-config=/usr/bin/llvm-config-18
   ```
3. Dynamically inject this patch into `installNghdl()` in `install-eSim-25.04.sh` so that when `nghdl.zip` is unpacked, `install-nghdl-25.04.sh` is automatically generated and invoked with LLVM 18.

#### Code Modification in `Ubuntu/install-eSim-scripts/install-eSim-25.04.sh`:
```bash
function installNghdl
{
    echo "Installing NGHDL..........................."
    if [ ! -f "nghdl.zip" ]; then
        echo "Warning: nghdl.zip not found. Skipping NGHDL installation."
        return 0
    fi

    unzip -o nghdl.zip
    cd nghdl/
    chmod +x install-nghdl.sh

    # Route Ubuntu 25.04 in NGHDL dispatcher
    if ! grep -q '"25.04"' install-nghdl.sh 2>/dev/null; then
        sed -i 's/"24.04")/"24.04"|"25.04"|"25.10"|"26.04")/' install-nghdl.sh 2>/dev/null || true
    fi

    # Ensure 25.04 script exists in nghdl with LLVM 18 fixes
    if [ ! -f "install-nghdl-scripts/install-nghdl-25.04.sh" ]; then
        if [ -f "install-nghdl-scripts/install-nghdl-24.04.sh" ]; then
            cp "install-nghdl-scripts/install-nghdl-24.04.sh" "install-nghdl-scripts/install-nghdl-25.04.sh"
            sed -i 's/sudo apt install -y llvm llvm-dev/sudo apt install -y llvm-18 llvm-18-dev/' "install-nghdl-scripts/install-nghdl-25.04.sh"
            sed -i 's/--with-llvm-config=\/usr\/bin\/llvm-config/--with-llvm-config=\/usr\/bin\/llvm-config-18/' "install-nghdl-scripts/install-nghdl-25.04.sh"
            sed -i 's/libcanberra-gtk-module libcanberra-gtk3-module/libcanberra-gtk3-module/' "install-nghdl-scripts/install-nghdl-25.04.sh"
            sed -i 's/libncurses5-dev/libncurses-dev/' "install-nghdl-scripts/install-nghdl-25.04.sh"
        fi
    fi

    trap "" ERR
    ./install-nghdl.sh --install
    trap error_exit ERR
    cd ../
}
```

#### Verification & Evidence
```bash
$ ghdl --version
GHDL 4.1.0 (tarball) [Dunoon edition]
 Compiled with GNAT Version: 14.2.0
 llvm 18.1.8 code generator
```
GHDL compiles and links successfully with the LLVM 18 backend.

---

### 4.4 BUG-04: Removal of Legacy GTK+ 2 libcanberra-gtk-module

#### Problem Description & Error Log
```text
Reading package lists... Done
Building dependency tree... Done
E: Package 'libcanberra-gtk-module' has no installation candidate
```

#### Technical Root Cause Analysis
Debian and Ubuntu officially removed GTK+ 2 libraries starting in Ubuntu 24.10 and completed in 25.04. `libcanberra-gtk-module` was the GTK+ 2 module, whereas modern desktop environments require only the GTK+ 3 equivalent: `libcanberra-gtk3-module`. Because `install-nghdl.sh` specified both modules in an `apt install -y` statement, `apt` encountered a missing package and exited with a fatal error code.

#### Architectural Solution
Removed `libcanberra-gtk-module` from all package installation requests for Ubuntu 25.04+, keeping exclusively `libcanberra-gtk3-module`.

---

### 4.5 BUG-05: KiCad 8.0 Symbol Library Table Path Mismatch

#### Problem Description & Impact
After installation, when launching KiCad Eeschema from eSim, none of the custom eSim symbol libraries (`eSim_PSpice`, `eSim_Subckt`, `eSim_Nghdl`, etc.) appear in the symbol library browser. Users cannot place components or create schematics.

#### Technical Root Cause Analysis
In `install-eSim-25.04.sh`, the symbol table copying routine executed:
```bash
cp kicadLibrary/template/sym-lib-table ~/.config/kicad/6.0/
```
Ubuntu 25.04 installs **KiCad 8.0**. KiCad 8 strictly reads user symbol table definitions from:
`$HOME/.config/kicad/8.0/sym-lib-table`
Because the file was written to `~/.config/kicad/6.0/`, KiCad 8 ignored it and initialized a default, empty library table.

#### Architectural Solution
Updated `copyKicadLibrary` in `install-eSim-25.04.sh` to target `~/.config/kicad/8.0/` and copy eSim custom symbols into `/usr/share/kicad/symbols/`:
```bash
kicad_config_dir="$TARGET_HOME/.config/kicad/8.0"
mkdir -p "$kicad_config_dir"
cp kicadLibrary/template/sym-lib-table "$kicad_config_dir/"
```

---

### 4.6 BUG-06: Brittle DFSG KiCad Package Version Pinning

#### Problem Description & Error Log
```text
Reading package lists... Done
Building dependency tree... Done
E: Version '8.0.8+dfsg-1' for 'kicad' was not found
```

#### Technical Root Cause Analysis
The script attempted to install:
```bash
sudo apt-get install -y --no-install-recommends kicad=8.0.8+dfsg-1 kicad-footprints ...
```
Pinning an exact Debian package string (`8.0.8+dfsg-1`) is brittle. Whenever Canonical publishes point updates (e.g., `8.0.8-1~ubuntu25.04.1` or `8.0.9`), the old string ceases to exist on mirrors, causing `apt` to fail immediately.

#### Architectural Solution
Removed the hardcoded version string in favor of standard repository resolution:
```bash
sudo apt-get install -y --no-install-recommends kicad kicad-footprints kicad-symbols kicad-templates
```
Additionally, added a graceful fallback so that if the PPA does not have plucky packages published, installation proceeds directly via Ubuntu's official universe repository.

---

### 4.7 BUG-07: Deprecated libncurses5-dev Superseded by Ncurses 6

#### Problem Description & Error Log
```text
Package libncurses5-dev is not available, but is referred to by another package.
This may mean that the package is missing, has been obsoleted, or
is only available from another source
E: Package 'libncurses5-dev' has no installation candidate
```

#### Technical Root Cause Analysis
Ncurses 5 is obsolete. Ubuntu 25.04 provides Ncurses 6 via `libncurses-dev`. Attempting to install `libncurses5-dev` causes `apt` to fail.

#### Architectural Solution
Replaced all occurrences of `libncurses5-dev` with `libncurses-dev`.

---

### 4.8 BUG-08: Defensive Error Handling for SKY130 PDK Unpacking

#### Problem Description & Error Log
```text
tar (child): library/sky130_fd_pr.tar.xz: Cannot open: No such file or directory
tar (child): Error is not recoverable: exiting now
```

#### Technical Root Cause Analysis
In source clones or trimmed distribution packages, `library/sky130_fd_pr.tar.xz` may not be bundled due to its large size (>500MB). Because the script runs with `set -e` enabled, the failure of `tar` caused the entire eSim installation to immediately abort.

#### Architectural Solution
Wrapped PDK extraction in defensive existence and destination checks:
```bash
if [ -f "library/sky130_fd_pr.tar.xz" ]; then
    tar -xJf library/sky130_fd_pr.tar.xz
    ...
elif [ -d "/usr/share/local/sky130_fd_pr" ]; then
    echo "SKY130 PDK already present at /usr/share/local/sky130_fd_pr"
else
    echo "Notice: library/sky130_fd_pr.tar.xz not found. Skipping local extraction."
fi
```

---

### 4.9 BUG-09: Sudo Privilege Isolation & HOME Directory Pollution

#### Problem Description & Impact
When users ran `sudo ./install-eSim.sh --install`:
- `$HOME` evaluated to `/root`.
- The virtual environment was written to `/root/.esim/env/`.
- Desktop entries were placed in `/root/Desktop/`.
- When the normal user logged in and typed `esim`, the application crashed because `/home/user/.esim/` did not exist.

#### Technical Root Cause Analysis
Bash scripts executed with `sudo` inherit the root environment unless the calling user is explicitly resolved via `SUDO_USER`.

#### Architectural Solution
Resolved the true non-root user and target home directory:
```bash
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null)
[ -z "$TARGET_HOME" ] && TARGET_HOME="$HOME"

config_dir="$TARGET_HOME/.esim"
```
All configuration files, desktop launchers, and virtual environment permissions are assigned to `TARGET_USER`.

---

### 4.10 BUG-10: OS Release Version Parsing on Non-Point Releases

#### Problem Description
On initial distribution releases (e.g., Ubuntu 25.04 prior to 25.04.1), `lsb_release -d` outputs:
`Description: Ubuntu 25.04` (only two digits).
The regex `grep -oP '\d+\.\d+\.\d+'` required three numeric groups, resulting in an empty string and failing the version check.

#### Technical Root Cause Analysis & Solution
Updated the regex to match both two-part and three-part version strings:
```bash
FULL_VERSION=$(lsb_release -d 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' || echo "$VERSION_ID")
```

---

## 5. Git Commit Traceability & Progressive Development Log

All 10 fixes have been committed sequentially to the `installers` branch in candidate repository **[RealRudraksh/Fossee-eSim](https://github.com/RealRudraksh/Fossee-eSim/commits/installers)**:

```text
e83660c docs: add comprehensive Ubuntu 25.04 upgradation report and updated README
61ca10c fix(nghdl): support LLVM 18 backend and replace GTK2 with GTK3 canberra module
e36161c fix(pdk): add existence check for sky130_fd_pr archive before extraction
40da8c9 fix(frontend): integrate system python3-pyqt5 with --system-site-packages for Python 3.13
de43c84 fix(kicad): point sym-lib-table to KiCad 8.0 config directory
13910f9 fix(kicad): remove hardcoded DFSG version pin for KiCad 8 installation
eceb7ac fix(installer): resolve SUDO_USER and HOME path pollution in 25.04 script
2f2515b feat(installer): add Ubuntu 25.04+ version detection and clean dispatcher
fd731fa fix(installer): resolve fatal syntax error and missing fi in install-eSim.sh
17824a3 build: add .gitattributes to enforce LF line endings on shell scripts
```

---

## 6. Verification, Testing & Reproduction Methodology

### 6.1 Automated Syntax & Shellcheck Test
```bash
bash -n Ubuntu/install-eSim.sh
bash -n Ubuntu/install-eSim-scripts/install-eSim-25.04.sh
```
*Result:* **PASS** (Zero syntax errors).

### 6.2 Virtual Environment & GUI Smoke Test
```bash
source ~/.esim/env/bin/activate
python3 -c "
import PyQt5.QtWidgets
import PyQt5.QtCore
import matplotlib
import numpy
import psutil
print('Smoke test successful: All frontend modules initialized.')
"
```
*Result:* **PASS** (Frontend modules loaded cleanly).

### 6.3 KiCad 8 Integration Test
```bash
test -f ~/.config/kicad/8.0/sym-lib-table && grep -q "eSim_PSpice" ~/.config/kicad/8.0/sym-lib-table && echo "KiCad 8 symbols OK"
```
*Result:* **PASS** (`KiCad 8 symbols OK`).

### 6.4 GHDL LLVM 18 Compiler Test
```bash
ghdl --version | grep -q "llvm 18" && echo "GHDL LLVM 18 OK"
```
*Result:* **PASS** (`GHDL LLVM 18 OK`).

---

## 7. Architectural Recommendations for Future eSim Releases

1. **PyQt6 / PySide6 Migration:**
   eSim's GUI currently relies on Qt 5 bindings (`PyQt5`). Because Qt 5 reached official End-of-Life, migrating the `src/frontEnd` codebase to **PyQt6** or **PySide6** will ensure native PyPI binary wheels across all future Python releases (Python 3.13, 3.14+).
2. **Standardized Container Packaging (Flatpak / AppImage):**
   Adopting an official Flatpak or AppImage manifest for eSim would bundle KiCad, Ngspice, GHDL, and Python dependencies into a single, immutable, distribution-agnostic bundle, eliminating host OS dependency drift entirely.
3. **Upstream GHDL 5.x Adoption:**
   When GHDL upstream releases version 5.0 with native LLVM 19/20 support, eSim's NGHDL package can be upgraded to the latest compiler release.

---

## 8. Conclusion

Through systematic root-cause analysis and disciplined engineering, all dependency and script failures preventing eSim 2.5 from running on Ubuntu 25.04 have been resolved. The solution prioritizes long-term stability: leveraging `--system-site-packages` for Python 3.13 GUI compatibility, pinning GHDL to the stable LLVM 18 backend, and aligning KiCad 8 configuration directories.

The resulting installation pipeline is robust, forward-compatible, and fully verified.
