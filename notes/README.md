# Ki-Sandbox Workspace

## Git Push aus der Sandbox — Setup

### Hintergrund

Die Sandbox läuft in einem Container. `/workspace` ist ein gemountetes Verzeichnis
vom Host (`/dev/sda5` → `/srv/ki-workspace/project`). Das `/home/ki-user/` der Sandbox
ist ein separates Container-Filesystem — eine `.git-credentials` Datei die auf dem Host
unter `/home/ki-user/` liegt, ist für die Sandbox **nicht** sichtbar.

### Einmalig einrichten

**1. PAT Token auf GitHub erstellen**

Unter https://github.com/settings/tokens → "Fine-grained tokens" → "Generate new token"

**Option A — Nur git push auf bestehende Repos**

- "Repository access" → "Only select repositories" → gewünschte Repos auswählen
- Berechtigung: `Contents: Read & Write`
- Empfehlung: kurze Gültigkeit (7–30 Tage)

**Option B — git push + neue Repositories anlegen (über die GitHub API)**

- "Repository access" → **"All repositories"**
- Berechtigungen:
  - `Administration: Read & Write` (zum Anlegen neuer Repos)
  - `Contents: Read & Write` (für git push/pull)
- Empfehlung: kurze Gültigkeit (7–30 Tage)

> Option B wird benötigt wenn die KI-Sandbox neue Repos per API anlegen soll
> (`curl https://api.github.com/user/repos`). Option A reicht für normalen git-Betrieb.

**2. Credentials-Datei im gemounteten Bereich ablegen (auf dem Host)**

```bash
sudo bash -c 'echo "https://GITHUB_USERNAME:DEIN_TOKEN@github.com" > /srv/ki-workspace/project/.git-credentials'
sudo chown ki-user:ki-user /srv/ki-workspace/project/.git-credentials
sudo chmod 600 /srv/ki-workspace/project/.git-credentials
```

`sudo` ist nötig, weil `/srv/ki-workspace/project/` UID 1001 (`ki-user`) gehört und der
Host-User (`herubuntu`) dort keine Schreibrechte hat. Nach `sudo` gehört die Datei `root`
— `chown` übergibt sie an `ki-user` damit die Sandbox sie lesen kann.

Diese Datei liegt unter `/workspace/.git-credentials` aus Sicht der Sandbox.

**3. Repository credential helper konfigurieren (einmalig pro Repository)**

```bash
git -C /workspace/REPO_NAME config --local credential.helper "store --file /workspace/.git-credentials"
```

Schreibt in `.git/config` des Repositories — funktioniert ohne globale Schreibrechte.

### Warum nicht global?

- `git config --global` schreibt in `/home/ki-user/.gitconfig` der Sandbox → **kein Schreibzugriff**
- `--local` schreibt in `.git/config` innerhalb von `/workspace/` → **funktioniert**

### Token in Remote-URL vermeiden

Den Token **nicht** per `git remote set-url https://user:TOKEN@github.com/...` einbetten —
der Token landet dann im Klartext in `.git/config` und taucht in `git remote -v` auf.
Stattdessen die Credentials-Datei wie oben beschrieben verwenden.

### Token erneuern

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

Die Repository-Konfiguration muss nicht erneut gesetzt werden.

### Sicherheitshinweise

- `.git-credentials` enthält den Token im Klartext — Dateiberechtigungen prüfen (`chmod 600`)
- Token nie in den Chat eingeben — er wird im Verlauf gespeichert
- Bei versehentlicher Exposition: Token sofort unter https://github.com/settings/tokens widerrufen
