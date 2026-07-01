# Buildozer BLE Proof-of-Concept — Kubuntu 24.04

Ziel: Eine minimale Android-APK bauen, die per BLE scannt und einen TCP-Server bereitstellt, über den man die Scan-Ergebnisse abrufen kann.

`main.py` und `buildozer.spec` liegen bereits fertig im `app/`-Verzeichnis — die Schritte unten beziehen sich darauf.

> **Update:** Der SSH-Server (`asyncssh`/`cryptography`) ist wieder aktiv. PR #3333 im
> python-for-android-Repo hat das Linker-Namespace-Problem behoben: Rust-Erweiterungen werden
> jetzt beim Build mit `-lpython` verlinkt, sodass `_rust.abi3.so` die Python-C-API-Symbole
> (`_Py_TrueStruct` usw.) korrekt auflöst. Der lokale p4a-Clone in `python-for-android/`
> enthält diesen Fix — `install_and_build.sh` installiert ihn per `pip install -e`.

---

## Teil 1 — Buildozer installieren

### 1.1 System-Abhängigkeiten

```bash
sudo apt update && sudo apt upgrade -y

sudo apt install -y \
    python3 python3-pip python3-venv \
    git zip unzip openjdk-17-jdk \
    autoconf libtool pkg-config \
    zlib1g-dev libncurses-dev libncursesw5-dev \
    cmake libffi-dev libssl-dev \
    build-essential ccache
```

`libtinfo5` gibt es ab Ubuntu 24.04 nicht mehr — `install_and_build.sh` legt bei Bedarf automatisch einen Kompatibilitäts-Symlink auf `libtinfo.so.6` an.

### 1.2 Python-Umgebung anlegen

```bash
cd ~/ble_poc
python3 -m venv venv
source venv/bin/activate
```

### 1.3 Buildozer installieren

```bash
pip install --upgrade pip
pip install buildozer
pip install cython
```

Version prüfen:
```bash
buildozer --version
```

---

## Teil 2 — Projekt

`app/main.py` enthält den gesamten App-Code (BLE-Scan + TCP-Server), `app/buildozer.spec` die Build-Konfiguration. Beide sind bereits vorbereitet — nichts mehr selbst anlegen nötig.

Login für den SSH-Server ist hartcodiert auf `poc` / `poc1234` (reiner PoC, keine echte Authentifizierung).

---

## Teil 3 — APK bauen

### 3.1 Ersten Build starten

```bash
cd ~/ble_poc/app
source ~/ble_poc/venv/bin/activate
buildozer android debug
```

**Beim ersten Build lädt Buildozer automatisch herunter:**
- Android SDK (~500 MB)
- Android NDK (~1 GB)
- Weitere Build-Tools

Das dauert beim ersten Mal **30–60 Minuten** — danach deutlich schneller.

### 3.2 Wo ist die APK?

Nach erfolgreichem Build liegt die APK hier:

```
~/ble_poc/app/bin/blepoc-0.1-arm64-v8a-debug.apk
```

### 3.3 APK auf das Handy installieren

Direkt per `adb` (Handy per USB, USB-Debugging an):

```bash
adb install -r bin/blepoc-0.1-arm64-v8a-debug.apk
adb shell am start -n org.test.blepoc/org.kivy.android.PythonActivity
```

---

## Teil 4 — Fehlersuche

### Build schlägt fehl

Log ausgeben:
```bash
buildozer android debug 2>&1 | tee build.log
```

Dann `build.log` nach `ERROR` durchsuchen.

### Häufige Probleme

| Problem | Lösung |
|---|---|
| `SDK not found` | `buildozer android update` ausführen |
| `NDK not found` | In `buildozer.spec`: `android.ndk = 25b` setzen |
| `cython error` | `pip install cython==0.29.37` (ältere Version) |
| `permission denied` | APK deinstallieren, neu installieren |
| `zlib headers must be installed` | `sudo apt install zlib1g-dev` (siehe Teil 1.1) |

### Logcat mitlesen

```bash
adb logcat -c
adb shell am start -n org.test.blepoc/org.kivy.android.PythonActivity
adb logcat | grep -i -E 'python|blepoc|traceback|fatal'
```

### Sauberer Neustart

```bash
buildozer android clean
buildozer android debug
```

---

## Teil 5 — Test

Nach Installation auf dem Handy:

1. App öffnen — alle Berechtigungsanfragen bestätigen
2. Bluetooth einschalten
3. Auf dem Display sollten BLE-Geräte erscheinen
4. SSH-Verbindung vom PC testen:

```bash
ssh poc@<handy-ip> -p 8022
```

Passwort: `poc1234`. Danach werden die aktuell gescannten BLE-Geräte ausgegeben und die Verbindung schließt.

> Beim ersten Verbindungsaufbau erscheint eine Host-Key-Warnung (neuer Key) — mit `yes` bestätigen oder `-o StrictHostKeyChecking=no` anhängen.

**Was wir erwarten:**
- BMS taucht in der Liste auf (Name oder MAC-Adresse)
- TCP-Verbindung funktioniert

Wenn beides klappt — BLE funktioniert und wir können den nächsten Schritt angehen: BMS-Protokoll auslesen.

---

## Lessons Learned

Diese Punkte haben uns beim Bau dieses PoC am meisten Zeit gekostet — falls du das Projekt erweiterst oder ein ähnliches aufsetzt, hier die Kurzfassung:

### asyncssh/cryptography unter python-for-android — gelöst

**Problem:** `cryptography`s Rust-Erweiterung (`_rust.abi3.so`) schlägt beim Import mit
`cannot locate symbol "_Py_TrueStruct"` fehl. Ursache: Android-Linker-Namespace-Isolation —
`libpython3.14.so` wird von Java geladen, aber `_rust.abi3.so` kann die Python-C-API-Symbole
nicht auflösen wenn es per `dlopen()` in einem anderen Namespace nachgeladen wird.

**Lösung: `patchelf`** — nach dem Build `libpython3.14.so` als NEEDED-Eintrag eintragen:
```bash
patchelf --add-needed libpython3.14.so \
  .buildozer/.../cryptography/hazmat/bindings/_rust.abi3.so
```
Danach `dists/` löschen und buildozer neu verpacken lassen. Das lokale Recipe in
`app/p4a-recipes/cryptography/__init__.py` automatisiert diesen Schritt für künftige Builds
(aktiviert über `p4a.local_recipes = ./p4a-recipes` in `buildozer.spec`).

**Warum PR #3333 allein nicht reicht:** Der Fix fügt `-Clink-arg=-lpython3.14` zu RUSTFLAGS
hinzu. Aber `libpython3.14.so` liegt im zweiten `-L`-Pfad (`android-build/`), der durch
RUSTFLAGS-Whitespace-Splitting nicht als Linker-Argument ankommt — nur als separates rustc-Flag.
Der Linker findet `libpython3.14.so` daher nicht und trägt es nicht in NEEDED ein.

**Weitere Stolpersteine:**
- `asyncssh >= 2.20.0` braucht `cryptography >= 48.0.1` (ML-KEM/post-quantum) — p4a-Recipe
  hat nur 46.0.3. Lösung: `asyncssh==2.18.0` in requirements pinnen.
- `typing_extensions` muss explizit in requirements stehen (asyncssh-Abhängigkeit).
- `rustup` + `rustup target add aarch64-linux-android` muss auf dem Build-Rechner installiert
  sein, bevor buildozer läuft.

### Pyjnius: `__javaclass__` muss beim Überschreiben explizit gesetzt werden
Eine Java-Klasse per `autoclass()` holen und direkt per Python-Vererbung Methoden überschreiben
funktioniert nicht automatisch — Pyjnius wirft `jnius.JavaException: __javaclass__ definition
missing`. Die Unterklasse braucht das Attribut explizit:
```python
class MyClass(SomeAutoclassedJavaClass):
    __javaclass__ = 'android/path/to/SomeClass'
```

### Abstrakte Android-Klassen dynamisch erweitern ist instabil
Das Erweitern von `android.bluetooth.le.ScanCallback` (eine abstrakte Klasse) über Pyjnius führte
auf einem Testgerät (Samsung Galaxy S7, Android 8.0) zu einem nativen `SIGABRT`-Absturz in
`jnius.so`. Robuster: die ältere, interface-basierte API verwenden — echte Java-**Interfaces**
lassen sich über `PythonJavaClass` + `@java_method` zuverlässig implementieren, abstrakte
Klassen dynamisch zu erweitern ist fragiler. Deshalb hier `BluetoothAdapter.LeScanCallback` +
`startLeScan()` statt `BluetoothLeScanner.startScan(ScanCallback)`.

### Sandbox-Limits (falls mit einer KI-Sandbox statt direkt auf dem Zielrechner gearbeitet wird)
- Kein `sudo`/`apt` möglich (Container mit `no-new-privileges`) — Systempakete müssen auf dem
  echten Zielrechner installiert werden, nicht in der Sandbox.
- `pip`/`venv` lassen sich in einer reinen Sandbox ohne Root nicht systemweit installieren;
  funktioniert nur in einem workspace-lokalen `--target`-Verzeichnis.
- `libtinfo5` existiert ab Ubuntu 24.04 nicht mehr in den Repos — `libncursesw5-dev` wird
  automatisch durch `libncurses-dev` ersetzt; falls NDK-Tools trotzdem `libtinfo.so.5` vermissen,
  reicht ein Kompatibilitäts-Symlink auf `libtinfo.so.6`.
