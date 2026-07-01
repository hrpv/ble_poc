#!/usr/bin/env bash
# Auf dem HOST (außerhalb der Sandbox) als root/sudo ausführen.
# Gibt sowohl ki-user (UID 1001, der Sandbox-User) als auch herubuntu
# gleichzeitig Lese-/Schreibrechte auf das Projektverzeichnis, ohne den
# Owner zu wechseln. Bevorzugt POSIX-ACLs, fällt sonst auf eine
# gemeinsame Gruppe zurück.
#
# Aufruf: sudo ./setup_access.sh

set -euo pipefail

PROJECT_DIR="/srv/ki-workspace/project/ble_poc"
KI_USER_UID="1001"
HOST_USER="herubuntu"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "FEHLER: Bitte mit sudo/root ausführen." >&2
    exit 1
fi

if [[ ! -d "${PROJECT_DIR}" ]]; then
    echo "FEHLER: ${PROJECT_DIR} existiert nicht." >&2
    exit 1
fi

if ! id "${HOST_USER}" &>/dev/null; then
    echo "FEHLER: Nutzer '${HOST_USER}' existiert nicht auf diesem Host." >&2
    exit 1
fi

if command -v setfacl &>/dev/null; then
    echo "== Setze ACLs (uid ${KI_USER_UID} und ${HOST_USER}) =="

    # Aktuelle Rechte
    setfacl -R  -m "u:${KI_USER_UID}:rwX" -m "u:${HOST_USER}:rwX" "${PROJECT_DIR}"
    # Default-ACLs, damit neu angelegte Dateien/Ordner die Rechte erben
    setfacl -R  -d -m "u:${KI_USER_UID}:rwX" -d -m "u:${HOST_USER}:rwX" "${PROJECT_DIR}"

    echo "== Fertig. Kontrolle: =="
    getfacl "${PROJECT_DIR}"
else
    echo "== setfacl nicht verfügbar — Fallback auf gemeinsame Gruppe =="

    GROUP_NAME="ble_poc_shared"

    if ! getent group "${GROUP_NAME}" &>/dev/null; then
        groupadd "${GROUP_NAME}"
    fi

    usermod -aG "${GROUP_NAME}" "${HOST_USER}"

    # ki-user läuft nur innerhalb der Sandbox/Container — falls es auf dem
    # Host einen passenden Account/UID gibt, ebenfalls zur Gruppe hinzufügen.
    if id -nu "${KI_USER_UID}" &>/dev/null; then
        usermod -aG "${GROUP_NAME}" "$(id -nu "${KI_USER_UID}")"
    fi

    chgrp -R "${GROUP_NAME}" "${PROJECT_DIR}"
    chmod -R g+rwX "${PROJECT_DIR}"
    find "${PROJECT_DIR}" -type d -exec chmod g+s {} \;

    echo "== Fertig. ${HOST_USER} muss sich neu einloggen, damit die neue Gruppe wirkt. =="
fi
