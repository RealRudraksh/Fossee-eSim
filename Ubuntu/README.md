# eSim Installer (Ubuntu OS)

This directory contains the installation scripts and packaging documentation for eSim EDA Suite on Ubuntu distributions, including **Ubuntu 25.04 (Plucky Puffin) and above**.

For the detailed technical report on Ubuntu 25.04 compatibility, dependency issues, and resolved bugs, see [REPORT.md](REPORT.md).

---

## Supported Ubuntu Versions

| Ubuntu Version | Architecture | Installer Script | Status |
|---|---|---|---|
| **Ubuntu 25.04 / 25.10 / 26.04** | x86_64 | `install-eSim-scripts/install-eSim-25.04.sh` | **Supported (Latest)** |
| **Ubuntu 24.04 LTS** | x86_64 | `install-eSim-scripts/install-eSim-24.04.sh` | Supported |
| **Ubuntu 23.04** | x86_64 | `install-eSim-scripts/install-eSim-23.04.sh` | Supported |
| **Ubuntu 22.04 LTS** | x86_64 | `install-eSim-scripts/install-eSim-22.04.sh` | Supported |

---

## Installation on Ubuntu 25.04+

1. Ensure the installer script is executable:
   ```bash
   chmod +x install-eSim.sh
   ```

2. Run the installer:
   ```bash
   ./install-eSim.sh --install
   ```

3. To uninstall eSim:
   ```bash
   ./install-eSim.sh --uninstall
   ```

---

## Key Highlights for Ubuntu 25.04 Support

- **Python 3.13 & PyQt5 Compatibility:** Resolves PyPI wheel absence on Python 3.13 by integrating Ubuntu's native `python3-pyqt5` into the eSim virtual environment via `--system-site-packages`.
- **PEP 668 Compliance:** All pip package installations are managed inside an isolated virtual environment (`~/.esim/env`).
- **KiCad 8.0 Integration:** Automatically configures eSim custom symbol libraries in `~/.config/kicad/8.0/sym-lib-table`.
- **NGHDL & GHDL LLVM 18 Backend:** Solves GHDL 4.1.0 build incompatibilities with LLVM 20 by directing the toolchain to LLVM 18 (`llvm-config-18`).
- **GTK3 Migration:** Automatically drops obsolete GTK2 `libcanberra-gtk-module` in favor of `libcanberra-gtk3-module`.

---

## Packaging eSim for Ubuntu OS

If you are packaging an eSim release archive for distribution:

1. Take the `master` branch containing the source code. Rename the folder to `eSim-<version>`.
2. Add the installer script `install-eSim.sh` and `install-eSim-scripts/` from the `installers` branch.
3. Add the eSim executable (if freezing) in the `eSim-<version>` folder. Remove development files (`.git`, `.github`, `.travis.yml`, etc.).
4. Add the eSim user manual `eSim_Manual_<version>.pdf` at location `library/browser/User-Manual/`.
5. Add `nghdl.zip` into the eSim root directory.
6. Compress `kicadLibrary` folder to `library/kicadLibrary.tar.xz` format and remove the uncompressed directory.
7. Compress `eSim-<version>` to a `.zip` archive for distribution.
