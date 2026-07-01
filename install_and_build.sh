#!/usr/bin/env bash
# Install + Build Skript für den BLE PoC — auf dem echten Kubuntu-Rechner ausführen,
# NICHT in der Sandbox. Erwartet Projektpfad: /srv/ki-workspace/project/ble_poc
#
# Aufruf: ./install_and_build.sh
#
# Besonderheiten:
#   - Rust (rustup) wird automatisch installiert falls nicht vorhanden
#   - patchelf trägt libpython in _rust.abi3.so ein (Android-Linker-Namespace-Fix)
#   - asyncssh ist auf 2.18.0 gepinnt (2.20+ braucht cryptography>=48 — p4a hat 46)

set -euo pipefail

PROJECT_DIR="/srv/ki-workspace/project/ble_poc"
APP_DIR="${PROJECT_DIR}/app"
VENV_DIR="${PROJECT_DIR}/venv"

echo "== Schritt 0: Voraussetzungen prüfen =="

if [[ ! -d "${APP_DIR}" ]]; then
    echo "FEHLER: ${APP_DIR} existiert nicht (main.py / buildozer.spec fehlen)." >&2
    exit 1
fi

if [[ ! -w "${PROJECT_DIR}" ]]; then
    cat >&2 <<EOF
FEHLER: ${PROJECT_DIR} ist für $(whoami) nicht beschreibbar.
Buildozer legt dort .buildozer/, bin/ etc. an und braucht Schreibrechte.

Rechte anpassen:
    sudo chown -R \$(whoami):\$(whoami) "${PROJECT_DIR}"

Danach dieses Skript erneut starten.
EOF
    exit 1
fi

echo "== Schritt 1: System-Abhängigkeiten (sudo erforderlich) =="
sudo apt update
sudo apt install -y \
    python3 python3-pip python3-venv \
    git zip unzip openjdk-17-jdk \
    autoconf libtool pkg-config \
    zlib1g-dev libncurses-dev libncursesw5-dev \
    cmake libffi-dev libssl-dev \
    build-essential ccache \
    patchelf

# libtinfo5 gibt es ab Ubuntu 24.04 nicht mehr — Kompatibilitäts-Symlink anlegen.
if ! ldconfig -p | grep -q 'libtinfo\.so\.5'; then
    LIBTINFO6=$(ldconfig -p | grep 'libtinfo\.so\.6' | head -n1 | awk '{print $NF}')
    if [[ -n "${LIBTINFO6}" ]]; then
        sudo ln -sf "${LIBTINFO6}" "$(dirname "${LIBTINFO6}")/libtinfo.so.5"
        sudo ldconfig
        echo "Hinweis: libtinfo.so.5 -> ${LIBTINFO6} symlink angelegt."
    fi
fi

echo "== Schritt 2: Python-Venv anlegen =="
if [[ ! -d "${VENV_DIR}" ]]; then
    python3 -m venv "${VENV_DIR}"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

echo "== Schritt 3: Rust-Toolchain (rustup) installieren =="
if ! command -v rustup &>/dev/null; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
else
    echo "rustup bereits vorhanden: $(rustup --version)"
fi
# Android-Zielarchitektur für den Rust-Cross-Compiler.
rustup target add aarch64-linux-android

echo "== Schritt 4: Buildozer + Cython + python-for-android installieren =="
pip install --upgrade pip
pip install buildozer cython

# p4a vom GitHub develop-Branch — enthält PR #3333 (libpython-Link-Fix).
# Hinweis: Der Fix greift wegen RUSTFLAGS-Whitespace-Splitting nicht vollständig;
# der patchelf-Schritt nach dem Build ist daher weiterhin notwendig.
pip install git+https://github.com/kivy/python-for-android.git

buildozer --version
python -c "import pythonforandroid; print('p4a:', pythonforandroid.__version__)"

echo "== Schritt 5: APK bauen =="
cd "${APP_DIR}"
buildozer android debug

echo "== Schritt 6: patchelf — libpython3.14.so in _rust.abi3.so eintragen =="
# _rust.abi3.so referenziert Python-C-API-Symbole direkt, hat aber libpython nicht
# in NEEDED (Android-Linker-Namespace-Problem). patchelf trägt es nachträglich ein.
RUST_SO=$(find "${APP_DIR}/.buildozer" \
    -path "*/python-installs/blepoc/arm64-v8a/cryptography/hazmat/bindings/_rust.abi3.so" \
    -print -quit)

if [[ -z "${RUST_SO}" ]]; then
    echo "FEHLER: _rust.abi3.so nicht gefunden — Build fehlgeschlagen?" >&2
    exit 1
fi

PYTHON_VERSION=$(python3 -c "
import glob, os
libs = glob.glob('${APP_DIR}/.buildozer/**/libpython3.*.so', recursive=True)
if libs:
    name = os.path.basename(libs[0])          # libpython3.14.so
    print(name.removeprefix('lib').removesuffix('.so'))  # python3.14
")
LIBPYTHON="lib${PYTHON_VERSION}.so"

echo "Patching: patchelf --add-needed ${LIBPYTHON} ${RUST_SO}"
patchelf --add-needed "${LIBPYTHON}" "${RUST_SO}"

# Prüfen ob der Eintrag da ist
readelf -d "${RUST_SO}" | grep NEEDED | grep python \
    && echo "OK: ${LIBPYTHON} ist in NEEDED" \
    || echo "WARNUNG: ${LIBPYTHON} nicht in NEEDED — patchelf fehlgeschlagen?"

echo "== Schritt 7: APK neu verpacken (ohne Recompile) =="
rm -rf "${APP_DIR}/.buildozer/android/platform/build-arm64-v8a/dists/blepoc"
buildozer android debug

APK=$(find "${APP_DIR}/bin" -name '*.apk' -print -quit)
if [[ -n "${APK}" ]]; then
    echo ""
    echo "== Fertig: ${APK} =="
    echo ""
    echo "Installieren:"
    echo "  adb install -r ${APK}"
    echo "  adb shell am start -n org.test.blepoc/org.kivy.android.PythonActivity"
    echo ""
    echo "Testen (nach ~5 Sekunden):"
    echo "  ssh poc@<handy-ip> -p 8022"
else
    echo "WARNUNG: Keine APK in ${APP_DIR}/bin gefunden." >&2
    exit 1
fi
