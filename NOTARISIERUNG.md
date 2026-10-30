# YA7: Developer-ID-Signierung und Notarisierung

Stand: 30. Oktober 2026. Ziel: direkte DMG-Weitergabe außerhalb des Mac App Store.
Version 0.2.8 (Build 10) wurde von Apple mit **Accepted** ohne Feststellungen notarisiert.
Finale Datei: `YA7-0.2.8-macOS.dmg`. Ticket angeheftet und validiert;
Gatekeeper akzeptiert DMG und enthaltene App als **Notarized Developer ID**.
Ein frischer Installationstest auf einem zweiten Mac steht noch aus.

Zertifikat, Team-ID und Zugangsdaten werden lokal eingerichtet. Die unten genannten
Werte sind Platzhalter. Keine privaten Schluessel oder Apple-Passwoerter ins Repository
aufnehmen. Der folgende Ablauf dient zukuenftigen Builds; vorhandene finale Dateien
werden nicht ueberschrieben.

## Einmalig im eigenen Apple-Konto

1. Aktive Mitgliedschaft im Apple Developer Program sicherstellen.
2. Xcode → Einstellungen → Apple Accounts → eigenes Team → Manage Certificates … →
   „+“ → **Developer ID Application**. Das Zertifikat mit zugehörigem privaten Schlüssel
   muss auf diesem Mac verfügbar sein. „Apple Development“ genügt nicht. Für ein lokales
   Developer-ID-Zertifikat verlangt Apple die Rolle Account Holder; fehlt die Auswahl,
   Mitgliedschaft und Team-Rolle prüfen. Ein Developer-ID-Installer-Zertifikat wird für
   diese Drag-and-drop-DMG nicht benötigt.
3. Die zehnstellige Team-ID im Entwicklerkonto ablesen.
4. Ein anwendungsspezifisches Apple-Passwort erstellen, wenn Apple-ID-Anmeldung für
   `notarytool` verwendet wird. Zugangsdaten ausschließlich im Schlüsselbund speichern:

```sh
xcrun notarytool store-credentials "YA7-notary"
```

Das Werkzeug fragt interaktiv nach Apple-ID, Team-ID und dem anwendungsspezifischen
Passwort. Keine Passwörter, privaten Schlüssel oder API-Schlüssel in den Quellcode
oder in den Chat kopieren. Alternativ unterstützt Apple ein App-Store-Connect-API-Key-
Profil; der übrige Ablauf kann denselben Schlüsselbund-Profilnamen verwenden.

## Signierten Release bauen

Die folgenden Werte sind Platzhalter und durch die eigenen Kontowerte zu ersetzen:

```sh
export YA7_SIGNING_IDENTITY='Developer ID Application: DEIN NAME (DEINETEAMID)'
export YA7_DEVELOPMENT_TEAM='DEINETEAMID'
export YA7_NOTARY_PROFILE='YA7-notary'
sh build-app.sh
```

Die Haupt-App, drei Finder-Erweiterungen und vier Kopien des 7-Zip-Helfers werden von
innen nach außen signiert. Die Helfer erhalten Hardened Runtime und bei echter
Signierung einen sicheren Zeitstempel. Die bestehenden Sandbox-Berechtigungen der
Finder-Helfer bleiben erhalten. Release-Builds erhalten keine Debug-Berechtigung
`get-task-allow`. Die lokale Ad-hoc-Voreinstellung bleibt für Entwicklung verfügbar.

## Einreichung ausführen

```sh
python3 Scripts/verify-release.py ../YA7.app --team-id "$YA7_DEVELOPMENT_TEAM"
sh Scripts/notarize.sh
```

Der Preflight prüft jede Mach-O-Datei in beiden Architekturen: gültige Signatur,
Apple-Vertrauenskette, Developer-ID-Zertifikat, einheitliche Team-ID, sicheren
Zeitstempel, Hardened Runtime, fehlende Debug-Berechtigung und Lizenz-/Quellpaket.

Das Notarisierungsskript erstellt die DMG zunächst ausschließlich im Arbeitsordner,
signiert sie und übermittelt sie mit `notarytool` an Apple. Nur bei **Accepted**, einem
Prüfprotokoll ohne Feststellungen, erfolgreichem Stapling und Gatekeeper-Prüfung wird
sie nach `YA7-<Version>-macOS.dmg` exportiert. Das Protokoll bleibt unter
`work/YA7-notary.*` erhalten. Die SHA-256-Prüfsumme wird nach dem Stapling berechnet.
Eine existierende finale Ausgabe wird nicht überschrieben.

Apple prüft beim Einreichen der äußeren DMG auch die enthaltenen Code-Komponenten.
Notarisierung ist keine App-Store-Prüfung und keine Lizenz-, Marken- oder Qualitätsfreigabe.
Das Skript sendet Software an Apple und gehört nur zu einem ausdrücklich beauftragten
Notarisierungslauf; es ist kein lokaler Routinecheck für die Refactoring-Automatisierung.

## Lokale Prüfung ohne Developer-ID-Zertifikat

```sh
python3 Scripts/verify-release.py ../YA7.app --allow-local
```

Dieser Modus toleriert lokale Signierung und fehlende sichere Zeitstempel, prüft aber
Struktur, Runtime, Debug-Berechtigungen und Lizenzmaterial. Er wird vom eigentlichen
Notarisierungsskript nicht verwendet und erlaubt keine Einreichung.

## Vor öffentlicher Freigabe noch entscheiden/prüfen

- Anbieter-/Supportkontakt und Lizenzmodell für den eigenen YA7-Code festlegen.
- Dauerhafte Bundle-Kennung festlegen; aktuell noch `de.local.archiv.prototype`.
- YA7-Namen und App-Icon auf Rechte Dritter prüfen; bisher nur öffentliche Namensvorprüfung.
- Frische Installation und Aktualisierung aus einer tatsächlich heruntergeladenen DMG
  einschließlich aller drei Finder-Aktionen auf einem zweiten Mac prüfen.
- Intel und macOS 14 tatsächlich testen; bislang Universal-Build und Laufzeittests auf
  dem Entwicklungsmac. Große/defekte Archive, RAR-Szenarien und Abbruch ergänzend prüfen.
- Bekannte Auffälligkeiten bei überlappenden Archiv-Leseaufträgen sowie Lebenszyklus
  erfolgreicher Finder-Temp-Ausgaben gesondert beurteilen; hier nicht automatisch geändert.

Für einen späteren Mac-App-Store-Vertrieb sind zusätzliche Arbeiten erforderlich:
Die Haupt-App ist aktuell nicht sandboxed. Datenschutzmanifest/Required-Reason-APIs
(u. a. UserDefaults und Dateizeitstempel), Store-Datenschutzangaben und Angaben zur
Verschlüsselung sind gesondert zu prüfen. Diese Store-Punkte sind nicht mit der
vorbereiteten direkten DMG-Notarisierung gleichzusetzen.

## Apple- und Lizenzquellen

- https://developer.apple.com/help/account/certificates/create-developer-id-certificates/
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- https://developer.apple.com/documentation/security/resolving-common-notarization-issues
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
- https://developer.apple.com/library/archive/technotes/tn2206/
- https://www.7-zip.org/faq.html
- https://github.com/ip7z/7zip/releases/tag/26.05
- https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html
