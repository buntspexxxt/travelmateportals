#!/bin/sh

# Travelmate-Skript für Wi-Fi DUS-Airport

SSID="Wi-Fi DUS-Airport"
REPORT_URL="https://joplin.specht.tv/report"

# Dummy E-Mail, falls nicht in Travelmate LuCI hinterlegt
# (Wird in diesem Skript nicht direkt verwendet, da kein Formular gefunden wurde,
# aber gemäß der Regeln definiert.)
email=$(uci -q get travelrouter.global.user_email || echo "dummy@example.com")

# Travelmate-Benutzername und -Passwort.
# Diese Variablen ($trm_user, $trm_pass) werden von Travelmate gesetzt,
# falls der Nutzer sie in der LuCI-Oberfläche konfiguriert hat.
# Da im bereitgestellten HTML-Code kein explizites Login-Formular mit diesen Feldern
# identifiziert werden konnte, werden sie in diesem Skript nicht direkt für eine POST-Anfrage verwendet.
# Sie sind jedoch hier zur Kenntnisnahme aufgeführt, falls sich das Portal ändert.
TRM_USER="$trm_user"
TRM_PASS="$trm_pass"

# Der bereitgestellte HTML-Code ist ein JavaScript-Loader für eine "Szene".
# Die eigentliche interaktive Portal-Seite (z.B. mit einem Login-Formular oder einer Akzeptanzseite)
# wird dynamisch geladen. Wir extrahieren die relevanten URLs und IDs aus dem HTML-Code,
# um die finale Szene direkt anzufordern.

# Extrahiert aus dem HTML:
# scene_template: https://469.rdr.conn4.com/scenes/{id}/
# scene_id: agbRwik_7LwIN_lF (gefunden in schedule.events[0].payload.data.id)
SCENE_BASE_URL="https://469.rdr.conn4.com/scenes/"
SCENE_ID="agbRwik_7LwIN_lF"
FINAL_SCENE_URL="${SCENE_BASE_URL}${SCENE_ID}/"

echo "INFO: Starte Travelmate-Skript für SSID: ${SSID}"
echo "INFO: Versuche, die Haupt-Portal-Szene abzurufen: ${FINAL_SCENE_URL}"

# Versuche, die finale Szene abzurufen.
# Das erfolgreiche Abrufen dieser URL simuliert, dass ein Browser die Portal-Seite geladen hat
# und bereit für Interaktion wäre. Da kein Login-Formular im *vorliegenden* HTML erkennbar ist,
# können wir hier keine Login-Daten senden.
# Wir gehen davon aus, dass das Erreichen dieser Szene das Ziel für Travelmate ist,
# um eine Verbindung herzustellen oder den nächsten Schritt (manuelle Interaktion) vorzubereiten.

# Verwende curl, um die Szene abzurufen.
# -L: Folge Weiterleitungen (Redirects)
# -s: Silent Mode (kein Fortschrittsbalken oder Fehlermeldungen anzeigen)
# -o /dev/null: Ignoriere den Output (wir wollen nur den Statuscode)
# -w "%{http_code}": Gib den HTTP-Statuscode nach Abschluss der Anfrage aus
HTTP_CODE=$(curl -L -s -o /dev/null -w "%{http_code}" "${FINAL_SCENE_URL}")
CURL_STATUS=$? # Der Exit-Code von curl (0 bei Erfolg)

if [ "$CURL_STATUS" -eq 0 ] && [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
    echo "INFO: Portal-Szene erfolgreich abgerufen (HTTP Code: ${HTTP_CODE})."
    echo "INFO: Es wurde kein explizites Login-Formular (z.B. für E-Mail/Passwort) im initialen HTML gefunden."
    echo "INFO: Das Skript geht davon aus, dass das Erreichen dieser Szene den initialen Portal-Schritt abschließt."
    # Sende Erfolgsbericht
    curl -s -X POST "${REPORT_URL}" -d "ssid=${SSID}&status=success" &
    exit 0
else
    echo "ERROR: Fehler beim Abrufen der Portal-Szene ${FINAL_SCENE_URL}."
    echo "ERROR: HTTP Code: ${HTTP_CODE}, Curl Exit-Status: ${CURL_STATUS}."
    echo "ERROR: Dies könnte auf Probleme beim Erreichen des Portals oder eine Änderung der Portalstruktur hindeuten."
    # Sende Fehlerbericht
    curl -s -X POST "${REPORT_URL}" -d "ssid=${SSID}&status=failure&message=Could not reach main portal scene" &
    exit 1
fi