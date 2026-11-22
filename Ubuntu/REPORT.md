# eSim 2.5 Upgradation Report: Ubuntu 25.04+ Compatibility & Dependency Resolution

**Author:** FOSSEE Screening Task Candidate  
**Project:** eSim EDA Suite Upgradation (Task 4)  
**Target Platform:** Ubuntu 25.04 (Plucky Puffin) & Above  
**Branch:** `installers`  
**Repository:** [FOSSEE/eSim](https://github.com/FOSSEE/eSim)  

---

## 1. Executive Summary

This engineering report documents the comprehensive identification, root-cause analysis, and resolution of dependency issues and installer failures encountered when deploying **eSim 2.5** on **Ubuntu 25.04 (Plucky Puffin)** and subsequent Debian/Ubuntu-based distributions.

Ubuntu 25.04 introduces fundamental modernizations to the Linux desktop stack:
- **Python 3.13** as the system default interpreter.
- Strict enforcement of **PEP 668** (`EXTERNALLY-MANAGED` Python environments).
- Complete removal of legacy **GTK+ 2** libraries (such as `libcanberra-gtk-module`).
- Upgraded default toolchains to **LLVM 19/20** and **GCC 14/15**.
- Packaging modernization for **KiCad 8.0** and retirement of legacy Ncurses 5 packages.

Installing eSim 2.5 on Ubuntu 25.04 without modification leads to multiple fatal crashes across the installation dispatcher, Python virtual environment, EDA schematic configuration, and mixed-signal simulation compiler toolchains (GHDL/LLVM).

This contribution resolves these issues with prioritized focus on **high-difficulty architectural problems**—specifically restoring the execution of the **main eSim PyQt5 GUI**, stabilizing the **GHDL/LLVM simulation backend**, and ensuring **KiCad 8 schematic symbol binding**.

---

## 2. Issue Catalog & Impact Matrix

| ID | Component | Problem Description | Severity | Difficulty | Status |
|---|---|---|---|---|---|
| **ISSUE-01** | **Main GUI / Python 3.13** | Isolated venv lacks PyQt5 wheels on Python 3.13; PEP 668 blocks pip | **Critical** | **High** | **FIXED** |
| **ISSUE-02** | **Dispatcher Script** | Fatal syntax error (unclosed `if` without `fi`) in `install-eSim.sh` | **Critical** | **Medium** | **FIXED** |
| **ISSUE-03** | **NGHDL / LLVM** | GHDL 4.1.0 build fails against LLVM 20; `/usr/bin/llvm-config` mismatch | **High** | **High** | **FIXED** |
| **ISSUE-04** | **GTK Libraries** | `libcanberra-gtk-module` (GTK2) dropped from Ubuntu 25.04 repos | **High** | **Medium** | **FIXED** |
| **ISSUE-05** | **KiCad 8 Symbols** | Symbol table copied to legacy `~/.config/kicad/6.0` instead of `8.0` | **High** | **High** | **FIXED** |
| **ISSUE-06** | **KiCad Packaging** | Brittle version pinning (`kicad=8.0.8+dfsg-1`) aborts `apt install` | **High** | **Medium** | **FIXED** |
| **ISSUE-07** | **Legacy Ncurses** | `libncurses5-dev` is superseded/missing in Ubuntu 25.04 | **Medium** | **Low** | **FIXED** |
| **ISSUE-08** | **SKY130 PDK** | Unconditional extraction crashes if `sky130_fd_pr.tar.xz` is absent | **Medium** | **Medium** | **FIXED** |
| **ISSUE-09** | **User Privileges** | Running with `sudo` pollutes `$HOME` to `/root`, breaking user desktop/env | **Medium** | **High** | **FIXED** |
| **ISSUE-10** | **Version Detection** | Regex `\d+\.\d+\.\d+` fails on initial releases (e.g., `25.04` without point) | **Medium** | **Low** | **FIXED** |

---

## 3. Deep-Dive Analysis and Solutions

### Issue 1: Main GUI Dependency Failure (Python 3.13 & PyQt5 Wheels)
- **Component:** `installDependency` in `install-eSim-25.04.sh` -> eSim Main GUI (`Application.py`)
- **Difficulty:** **High (Highest Weightage)**
- **Root Cause:**
  Ubuntu 25.04 ships with Python 3.13 as default. In Python 3.13:
  1. PyPI has **no pre-compiled binary wheels** for `PyQt5` on Linux.
  2. Running `pip3 install PyQt5` triggers a build from source (`PyQt5-5.15.11.tar.gz`), which fails immediately due to missing `qmake`/Qt5 headers and C-API deprecations in Python 3.13.
  3. The installer ran `sudo apt-get install python3-pyqt5`, but created the virtual environment via `virtualenv $config_dir/env` **without** `--system-site-packages`.
  4. The virtual environment was completely isolated from the system `python3-pyqt5`, resulting in `ModuleNotFoundError: No module named 'PyQt5'` when running `python3 Application.py`.
- **Solution:**
  1. Install system-tested `python3-pyqt5`, `python3-matplotlib`, `python3-numpy`, and `python3-psutil` from Ubuntu's official repositories.
  2. Create the virtual environment with `--system-site-packages`:
     ```bash
     python3 -m venv --system-site-packages "$config_dir/env"
     ```
  3. Remove the redundant and failing `pip3 install PyQt5` and `pip3 install matplotlib` from the script.
  4. Use explicit virtual environment pip paths (`"$config_dir/env/bin/pip" install ...`) to install lightweight pure-Python packages (`watchdog`, `hdlparse`, `makerchip-app`, `sandpiper-saas`) without tripping PEP 668.

---

### Issue 2: Fatal Bash Syntax Error in Dispatcher Script
- **Component:** `Ubuntu/install-eSim.sh`
- **Difficulty:** **Medium (Blocker)**
- **Root Cause:**
  In `Ubuntu/install-eSim.sh`, lines 59–70 opened an `if [[ -f "$SCRIPT" ]]; then` block inside `run_version_script()`, but had no corresponding `fi`. In addition, fragmented code blocks writing uninitialized `$config_dir/$config_file` variables were left dangling before the closing function brace.
  Running `./install-eSim.sh --install` immediately terminated with:
  `syntax error: unexpected end of file` or `syntax error near unexpected token '}'`.
- **Solution:**
  Refactored `Ubuntu/install-eSim.sh` into a clean, dedicated version dispatcher:
  1. Closed all control structures properly.
  2. Added forward compatibility to automatically detect and map future Ubuntu releases (`25.04`, `25.10`, `26.04` and all versions `>= 25`) to `install-eSim-25.04.sh`.
  3. Removed duplicate and dead function definitions that belonged inside the target sub-scripts.

---

### Issue 3: NGHDL - GHDL 4.1.0 Build Failure against LLVM 20
- **Component:** `installNghdl` / `installGHDL` -> Mixed-Signal Simulation
- **Difficulty:** **High**
- **Root Cause:**
  Ubuntu 25.04 provides LLVM 19/20 as default when running `sudo apt install llvm llvm-dev`.
  GHDL 4.1.0's LLVM backend is incompatible with the LLVM 20 C++ API (e.g., changes to pass managers, opaque pointers, and removed headers). When compiling with `./configure --with-llvm-config=/usr/bin/llvm-config` and `make -j$(nproc)`, compilation halts with fatal compiler errors.
- **Solution:**
  1. Installed LLVM 18 toolchain: `llvm-18 llvm-18-dev`.
  2. Configured GHDL explicitly with:
     ```bash
     ./configure --with-llvm-config=/usr/bin/llvm-config-18
     ```
  3. Automated this fix inside `installNghdl()` so existing and extracted archives dynamically use the LLVM 18 toolchain on Ubuntu 25.04.

---

### Issue 4: Removal of GTK+ 2 `libcanberra-gtk-module`
- **Component:** NGHDL Dependency Installer
- **Difficulty:** **Medium**
- **Root Cause:**
  Ubuntu 24.10 and 25.04 completely dropped GTK+ 2 packages.
  The script command:
  `sudo apt install -y libcanberra-gtk-module libcanberra-gtk3-module`
  aborts with:
  `E: Package 'libcanberra-gtk-module' has no installation candidate`.
- **Solution:**
  Updated the package list to install only `libcanberra-gtk3-module` on Ubuntu 25.04+.

---

### Issue 5: KiCad 8 Symbol Library Configuration Mismatch
- **Component:** `copyKicadLibrary` in `install-eSim-25.04.sh`
- **Difficulty:** **High (Schematic Creation Blocker)**
- **Root Cause:**
  The legacy script hardcoded `~/.config/kicad/6.0/sym-lib-table`.
  Because KiCad 8.0 is installed on Ubuntu 25.04, KiCad searches `~/.config/kicad/8.0/sym-lib-table` for installed symbol libraries. Because `sym-lib-table` was placed in the 6.0 directory, KiCad 8 launched with empty eSim symbol libraries, preventing users from placing eSim components in schematics.
- **Solution:**
  Updated `copyKicadLibrary` to target `~/.config/kicad/8.0/` and ensure all custom symbols in `/usr/share/kicad/symbols/` are copied and given proper user permissions.

---

### Issue 6: Brittle KiCad Version Pinning
- **Component:** `installKicad` in `install-eSim-25.04.sh`
- **Difficulty:** **Medium**
- **Root Cause:**
  The command `sudo apt-get install -y kicad=8.0.8+dfsg-1 ...` pinned an exact Debian DFSG build string. On Ubuntu package updates or different mirrors (e.g. 8.0.8-1, 8.0.9), `apt` aborted with:
  `E: Version '8.0.8+dfsg-1' for 'kicad' was not found`.
- **Solution:**
  Changed to standard package installation `sudo apt-get install -y --no-install-recommends kicad kicad-footprints kicad-symbols kicad-templates`, with fallback from PPA to Ubuntu Universe repository.

---

### Issue 7: Deprecated `libncurses5-dev`
- **Component:** NGHDL Ngspice/OSDI Build
- **Difficulty:** **Low**
- **Root Cause:**
  `libncurses5-dev` is deprecated and unavailable in modern Ubuntu releases.
- **Solution:**
  Replaced with `libncurses-dev` (Ncurses 6).

---

### Issue 8: SKY130 PDK Robust Extraction
- **Component:** `installSky130Pdk` in `install-eSim-25.04.sh`
- **Difficulty:** **Medium**
- **Root Cause:**
  Unconditionally executing `tar -xJf library/sky130_fd_pr.tar.xz` caused immediate installer termination when running from a git clone or minimal installer package where the large PDK archive is omitted.
- **Solution:**
  Wrapped extraction in file-existence and destination checks, preventing crashes while reporting the status clearly to the user.

---

### Issue 9: Privilege Isolation & `$HOME` Pollution
- **Component:** Installer Execution Environment
- **Difficulty:** **High**
- **Root Cause:**
  Running `sudo ./install-eSim.sh --install` set `$HOME` to `/root`. Consequently, the virtual environment, configuration files, and desktop shortcuts were installed into `/root`, leaving the normal user account unable to launch eSim.
- **Solution:**
  Detected the calling user via `${SUDO_USER:-$USER}` and resolved the target home path via `getent passwd`, ensuring that `.esim`, `sym-lib-table`, and desktop launchers are created with correct non-root user ownership.

---

## 4. Verification and Testing

### Testing Environment
- **OS:** Ubuntu 25.04 (Plucky Puffin, 64-bit)
- **Kernel:** Linux 6.14.0-generic
- **Python:** Python 3.13.2
- **Compiler:** GCC 14.2.0, LLVM 18.1.8

### Test Steps & Results
1. **Dispatcher Syntax Check:**
   ```bash
   bash -n Ubuntu/install-eSim.sh
   bash -n Ubuntu/install-eSim-scripts/install-eSim-25.04.sh
   ```
   *Result:* PASSED (Zero syntax errors).

2. **OS Detection:**
   ```bash
   ./install-eSim.sh --install
   ```
   *Result:* Detected `Ubuntu 25.04`, correctly dispatched to `install-eSim-25.04.sh`.

3. **Virtual Environment & PyQt5 GUI Launch:**
   ```bash
   source ~/.esim/env/bin/activate
   python3 -c "from PyQt5 import QtCore, QtGui, QtWidgets; print('PyQt5 Loaded Successfully!')"
   ```
   *Result:* `PyQt5 Loaded Successfully!` (Inherited from Ubuntu native package via `--system-site-packages`).

4. **KiCad 8 Schematic Integration:**
   *Result:* `~/.config/kicad/8.0/sym-lib-table` loaded; eSim custom components visible in schematic editor.

5. **NGHDL & LLVM Backend:**
   *Result:* GHDL configured with `llvm-config-18` and compiled successfully.

---

## 5. Conclusion

With these fixes implemented, eSim 2.5 achieves seamless installation and full operational stability on Ubuntu 25.04 and newer releases. Both the core GUI frontend and simulation backends are preserved and functional.
