# Git Push Setup — Zusammenfassung

Zwei getrennte Wege: **Git Credential Manager (GCM)** für dich persönlich (Windows/Linux),
**Personal Access Token (PAT)** für die KI-Sandbox.

---

## 1. Persönliche Nutzung — Git Credential Manager (GCM)

GCM übernimmt Browser-basierten OAuth-Login und speichert das Token danach sicher im
OS-eigenen Store. Kein manueller PAT nötig.

### Windows
Kommt mit Git for Windows bereits vorinstalliert. Prüfen:
```bash
git config --get credential.helper
```
Beim ersten `git push` öffnet sich automatisch ein Browserfenster für den Login.
Token landet im **Windows Credential Manager**.

### Linux
```bash
sudo apt install ./gcm-linux-x64-2.8.0.deb
git-credential-manager configure
sudo apt install libsecret-1-0 gnome-keyring   # falls Secret Service fehlt

# WICHTIG — ohne diesen Schritt kommt Fehler "No credential store has been selected":
git config --global credential.credentialStore secretservice
```
Danach `git push` → Browser-Login → Token landet im **libsecret / GNOME Keyring**.

`--global` gilt nur für den eigenen Linux-User, **nicht** für `ki-user` oder die Sandbox.

### Alte/falsche Credentials löschen
```bash
git credential-manager github logout
# oder gezielt:
git credential-manager delete https://github.com
```
Windows GUI: *Anmeldeinformationsverwaltung* → Windows-Anmeldeinformationen → Eintrag entfernen.
Linux GUI: *Seahorse* (GNOME) oder *KWalletManager* (KDE).

Kompletter Reset:
```bash
git-credential-manager unconfigure
```

---

## 2. KI-Sandbox — Personal Access Token (PAT)

Sandbox hat kein Browser-Popup → GCM/OAuth funktioniert dort nicht. PAT + Datei ist der Weg.

### PAT auf GitHub erstellen
`github.com/settings/tokens` → **Fine-grained tokens** → *Generate new token*

- Repository access: **Only select repositories** → eigenes Repo auswählen
- Permissions → **+ Add permissions** → Tab **Repositories** → `Contents` suchen →
  **Read and write**
- Gültigkeit kurz halten (z. B. 7–30 Tage)

> Nur wenn die Sandbox auch neue Repos per API anlegen soll: stattdessen
> "All repositories" + zusätzlich `Administration: Read & Write`.

### Sandbox-Besonderheit: Container-Filesystem

⚠️ **Wichtigste Falle:** Die Sandbox läuft in einem Container mit eigenem Filesystem.
`/home/ki-user/` auf dem **Host** ist NICHT dasselbe wie `/home/ki-user/` **in der Sandbox**.
Eine Datei dort auf dem Host abgelegt, sieht der Container nicht.

Einziger sichtbarer Bereich ist der gemountete Ordner:
**Host** `/srv/ki-workspace/project` ↔ **Sandbox** `/workspace`

### Setup (auf dem Host)

```bash
# Credentials-Datei im gemounteten Bereich anlegen:
sudo bash -c 'echo "https://GITHUB_USERNAME:DEIN_TOKEN@github.com" > /srv/ki-workspace/project/.git-credentials'
sudo chown ki-user:ki-user /srv/ki-workspace/project/.git-credentials
sudo chmod 600 /srv/ki-workspace/project/.git-credentials
```
`sudo` nötig, da der Ordner UID 1001 (`ki-user`) gehört, nicht dem Host-User.

```bash
# Pro Repository (nicht global!) den Credential Helper setzen:
git -C /workspace/REPO_NAME config --local credential.helper "store --file /workspace/.git-credentials"
```

**Warum `--local` und nicht `--global`:** `--global` würde in
`/home/ki-user/.gitconfig` der Sandbox schreiben — dort hat `ki-user` keine
Schreibrechte. `--local` schreibt in `.git/config` innerhalb von `/workspace/`,
das funktioniert.

**Token nie direkt in die Remote-URL einbetten** (`git remote set-url ...TOKEN@...`) —
landet dann im Klartext in `.git/config` und in `git remote -v`. Stattdessen immer über
die Credentials-Datei wie oben.

### Token erneuern (nach Ablauf)

⚠️ `.git-credentials` kann mehr als eine Zeile enthalten (z. B. zusätzliche
Proxy-Credentials). **Nicht** mit `echo ... > Datei` überschreiben — das löscht alle
anderen Zeilen. Stattdessen die Datei in-place bearbeiten:

```bash
sudo nano /srv/ki-workspace/project/.git-credentials
# nur die GitHub-Zeile mit dem neuen Token ersetzen, Rest unverändert lassen
```

Lesen erfordert ebenfalls `sudo`, da die Datei `ki-user` (UID 1001) gehört, nicht dem
Host-User:
```bash
sudo cat /srv/ki-workspace/project/.git-credentials
```
`cat` ohne `sudo` schlägt mit "Permission denied" fehl.

Repository-Konfiguration muss nicht erneut gesetzt werden.

### Sicherheit
- `chmod 600` auf die Credentials-Datei
- Token nie im Chat/Terminal-History im Klartext stehen lassen
- Bei Verdacht auf Exposition: Token sofort unter `github.com/settings/tokens` widerrufen

---

## 3. Git-Grundlagen: mv / rm / add

**Faustregel:** Wo möglich `git mv` / `git rm` nutzen statt Shell-`mv`/`rm` + `git add` —
staged automatisch und wird als echter Rename/Delete erkannt (bessere History).

| Aktion | Befehl | Staged automatisch? |
|---|---|---|
| Datei/Ordner verschieben oder umbenennen | `git mv quelle ziel` | ✅ Ja |
| Datei löschen | `git rm datei` | ✅ Ja |
| Dateiinhalt ändern | Editor + `git add datei` | ❌ Nein — `git add` zwingend |
| Neue Datei | erstellen + `git add datei` | ❌ Nein — `git add` zwingend |

```bash
# Mehrere Dateien in ein Verzeichnis verschieben:
mkdir -p dir
git mv file1 file2 file3 dir/

# Ganzen Ordner umbenennen:
git mv alter_name neuer_name

# Alle Dateien aus einem Ordner ins aktuelle Verzeichnis holen:
git mv quellordner/* .
# Achtung: versteckte Dateien (.dotfiles) werden von * NICHT erfasst
# Achtung: leerer Ordner bleibt übrig -> danach: rmdir quellordner
# Vorher testen ohne Ausführung: git mv -n quelle ziel
```

Mehrere `git mv`/`git rm`/`git add` können beliebig gesammelt werden, bevor committed wird:
```bash
git mv fileA dir1/
git mv fileB dir2/
git status              # zeigt alle staged Änderungen
git commit -m "Reorganize"
```

Staging rückgängig machen (vor dem Commit):
```bash
git restore --staged datei      # einzelne Datei
git reset                       # alles (Dateien bleiben aber physisch verschoben)
```

`mkdir -p` statt `mkdir`: legt fehlende Elternverzeichnisse automatisch mit an und
meckert nicht, falls der Ordner schon existiert (idempotent, gut für Scripts).

`ls -1`: eine Datei pro Zeile, nur Namen (`-1a` inkl. versteckter Dateien).

---

## 4. GCM komplett zurücksetzen

Falls GCM neu eingerichtet werden muss (z. B. nach Fehlkonfiguration oder Store-Wechsel).

### Schritt 1 — Gespeicherte Credentials löschen

```bash
git credential-manager github logout
# oder gezielt für einen Host:
git credential-manager delete https://github.com
```

Zur Kontrolle, ob noch Accounts hinterlegt sind:
```bash
git-credential-manager github list
```

Falls darüber nichts mehr übrig sein soll, direkt im OS-Store nachsehen:

**Linux (secretservice):**
```bash
secret-tool search service github.com
secret-tool clear service github.com
```
Grafisch: *Seahorse* (GNOME) oder *KWalletManager* (KDE) — nach "github" suchen, löschen.

**Windows:**
*Anmeldeinformationsverwaltung* → Windows-Anmeldeinformationen → Eintrag mit
`git:https://github.com` suchen → Entfernen.

### Schritt 2 — GCM als Credential Helper entfernen

```bash
git-credential-manager unconfigure
```
Entfernt GCM aus der globalen Git-Konfiguration. Gespeicherte Secrets im OS-Store
sind davon **nicht** betroffen — die müssen wie in Schritt 1 separat gelöscht werden.

### Schritt 3 — Neu einrichten

```bash
git-credential-manager configure
git config --global credential.credentialStore secretservice   # Linux, sonst Fehler "No credential store selected"
```

Danach normal `git push` → Browser-Login löst neuen Eintrag im Store aus.

### Typischer Fehler nach Neuinstallation

```
fatal: No credential store has been selected.
```
→ Fehlender Schritt: `credential.credentialStore` wurde nicht gesetzt (siehe Schritt 3,
zweite Zeile). Unter Linux mit Desktop-Umgebung ist `secretservice` die richtige Wahl.
