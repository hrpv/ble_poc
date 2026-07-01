#!/usr/bin/env bash
# Räumt die Reste der gescheiterten SSH/cryptography/Rust-Versuche vom Host auf.
# Auf dem HOST ausführen (nicht in der Sandbox).
#
# Aufruf: ./cleanup.sh

set -euo pipefail

PROJECT_DIR="/srv/ki-workspace/project/ble_poc"
APP_DIR="${PROJECT_DIR}/app"

echo "== Schritt 1: Rust/rustup entfernen =="
echo "(wurde nur für 'cryptography' gebraucht, das wir nicht mehr verwenden)"

if command -v rustup &>/dev/null; then
    rustup self uninstall -y
else
    echo "rustup ist nicht (mehr) im PATH — prüfe trotzdem auf Restdateien."
fi

# Falls rustup schon entfernt wurde aber Verzeichnisse übrig sind, oder
# rustup nie ordentlich deinstalliert wurde:
for dir in "$HOME/.cargo" "$HOME/.rustup"; do
    if [[ -d "$dir" ]]; then
        echo "Entferne $dir"
        rm -rf "$dir"
    fi
done

# Zeile, die wir in ~/.bashrc ergänzt hatten, wieder rausnehmen
if [[ -f "$HOME/.bashrc" ]] && grep -q 'cargo/env' "$HOME/.bashrc"; then
    echo "Entferne Cargo-env-Zeile aus ~/.bashrc"
    sed -i '/\.cargo\/env/d' "$HOME/.bashrc"
fi

echo "== Schritt 2: Verwaiste Build-Caches im Projekt =="
echo "(Reste der abgebrochenen Python-3.11/cryptography-Build-Versuche)"

if [[ -d "${APP_DIR}/.buildozer" ]]; then
    read -r -p "Komplettes '.buildozer'-Verzeichnis im Projekt löschen (voller Rebuild beim nächsten Mal, SDK/NDK selbst bleiben erhalten unter ~/.buildozer)? [j/N] " answer
    if [[ "${answer,,}" == "j" ]]; then
        rm -rf "${APP_DIR}/.buildozer" "${APP_DIR}/bin"
        echo "Entfernt: ${APP_DIR}/.buildozer und ${APP_DIR}/bin"
    else
        echo "Übersprungen — .buildozer bleibt erhalten."
    fi
else
    echo "Kein .buildozer-Verzeichnis im Projekt gefunden, nichts zu tun."
fi

echo "== Fertig =="
echo "Rust/Cargo ist entfernt. Aktueller Build (python3,kivy,pyjnius) braucht es nicht mehr."
