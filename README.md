# Travelmate Portals

Dieses Repository ist ein automatischer Speicher für Captive-Portal-Login-Skripte.

## Funktionsweise

Die Skripte in diesem Repository werden **automatisch generiert**, sobald der Travel Router (GL.iNet) auf ein unbekanntes, passwortfreies WLAN-Netzwerk mit einem Captive Portal (Vorschaltseite) trifft.

1. **Erfassung:** Der Router speichert die Webseite des Captive Portals und sendet sie an den zentralen Collector-Server.
2. **KI-Analyse:** Eine Künstliche Intelligenz (Gemini) analysiert den HTML-Code des Portals, akzeptiert Nutzungsbedingungen, füllt versteckte Formulare aus und generiert ein passgenaues Login-Skript.
3. **Upload:** Das fertige Skript wird automatisch über die GitHub REST API in dieses Repository hochgeladen.
4. **Ausführung:** Der Travel Router lädt sich das Skript im Hintergrund herunter (über die Raw-URL) und das Plugin `travelmate` führt den automatischen Login durch.

## Struktur

Jedes Netzwerk erhält seinen eigenen Ordner, benannt nach der SSID des Netzwerks. Darin befindet sich das eigentliche Shell-Skript (`SSID.sh`):

```text
/
├── bluespot/
│   └── bluespot.sh
├── Toverland/
│   └── Toverland.sh
└── README.md
```

## Hinweis

Da die Inhalte maschinell aus lokal abgerufenen Webseiten erzeugt werden, sind manuelle Änderungen in diesem Repository im Normalfall nicht erforderlich.
