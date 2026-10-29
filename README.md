# ESMA – Hühnerpatenmanager

Flutter-Webanwendung zur Verwaltung von Hühnerprofilen, Patenschaften und Interessentenanfragen. Das Projekt verwendet OCI-Container, PostgreSQL und OIDC. Es kann auf einem Linux-Server bei Hetzner, IONOS oder einem anderen Docker-Compose-Host betrieben werden.

## Komponenten

- `app/`: Flutter-Weboberfläche mit Keycloak JavaScript Adapter
- `api/`: Fastify-API auf Node.js 22
- `database/`: PostgreSQL-Schema und Backup-Werkzeuge
- `keycloak/`: Realm-Voreinstellung für interne Benutzer und OIDC
- `docker-compose.yml`: PostgreSQL, Keycloak, Migration, API, Web und Caddy
- `api/src/storage.ts`: austauschbare Bildspeicher-Adapter

## Betrieb auf einem Server

Voraussetzungen: Docker Engine und Docker Compose v2. Weise die DNS-Namen für App und Anmeldung auf die öffentliche IP des Servers und erlaube eingehend TCP 80/443.

```sh
cp .env.example .env
```

Setze in `.env` `APP_DOMAIN`, `AUTH_DOMAIN` sowie zwei starke, getrennte Passwörter für PostgreSQL und den Keycloak-Administrationszugang. Wähle den gewünschten Speicher mit `STORAGE_DRIVER` (siehe unten). Starte anschließend:

```sh
docker compose up -d --build
```

Caddy stellt für öffentliche Domains automatisch HTTPS bereit. Öffne `https://AUTH_DOMAIN`, melde dich mit dem Keycloak-Bootstrap-Konto an und passe unter **Clients → esma-web** `Valid redirect URIs` und `Web origins` an die Domain aus `APP_DOMAIN` an. Die Realm-Voreinstellung enthält Beispielwerte für `app.example.org` und `localhost`.

Wenn eine externe Website (zum Beispiel Wix) die öffentliche API direkt im Browser aufruft, setze `CORS_ORIGIN` auf genau deren HTTPS-Origin. Bei der üblichen Bereitstellung über dieselbe App-Domain ist kein zusätzlicher CORS-Origin nötig.

Lege in Keycloak interne Benutzer an und weise ihnen die Realm-Rolle `admin` zu. Der Keycloak-Administrationszugang dient nur der Einrichtung und sollte nicht für den täglichen Zugriff verwendet werden. Externe OIDC-Anbieter können unter **Identity providers** ergänzt werden. Weise externen Benutzern die ESMA-Rolle nur über einen passenden, kontrollierten Mapper zu.

Compose führt das idempotente PostgreSQL-Schema als Migrationsschritt aus, bevor die API startet. Für spätere Schemaänderungen Schema aktualisieren und den Migrationsdienst erneut starten:

```sh
docker compose run --rm migrate
```

## Bildspeicher auswählen

Setze `STORAGE_DRIVER` in `.env` auf einen der folgenden Werte:

| Treiber | Konfiguration | Einsatz |
| --- | --- | --- |
| `local` | `LOCAL_STORAGE_PATH` (im Container `/data/images`) | Einzelserver mit persistentem Compose-Volume |
| `s3` | `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`; optional `S3_FORCE_PATH_STYLE` | S3-kompatible Dienste wie Hetzner, IONOS, MinIO oder andere Anbieter |
| `azure-blob` | `AZURE_STORAGE_CONNECTION_STRING`, optional `AZURE_STORAGE_CONTAINER` | Bestehende Azure-Bildspeicher |

Die API speichert nur UUID-basierte Objektschlüssel, hält Speicherbereiche privat und liefert Bilder über `/api/v1/public/images/{chickenId}` aus. `s3` verwendet die AWS S3 API; Anbieter-spezifische Endpunkte und Zugangsdaten stehen ausschließlich in `.env`. Der S3-Treiber legt den Bucket nicht an: Er muss vorher beim Anbieter angelegt werden. Fehlen für den ausgewählten Treiber Zugangsdaten, beendet sich die API mit einer verständlichen Fehlermeldung.

Der lokale Treiber verwendet das persistente Docker-Volume `image_data`. Bei S3- oder Azure-Nutzung müssen Bilder über die jeweilige Storage-Sicherung gesichert werden. Ein Treiberwechsel kopiert keine Bestandsbilder automatisch.

## Datenmigration aus Azure

Vor der Umstellung erstelle einen PostgreSQL-Dump der App-Datenbank und stelle ihn im neuen PostgreSQL wieder her. Das Keycloak-System startet neu mit eigener Benutzerverwaltung; Azure-Entra-Benutzer müssen intern angelegt oder als externer OIDC-Anbieter angebunden und Rollen zugewiesen werden.

Für vorhandene Hühnerbilder stellt die API einen Kopierlauf von Azure Blob Storage in den konfigurierten Zieltreiber bereit. Wähle in `.env` das Ziel (`local` oder `s3`) und setze dort dessen Zugangsdaten. Führe dann den Befehl im API-Container aus:

```sh
docker compose exec \
  -e SOURCE_AZURE_STORAGE_CONNECTION_STRING='…' \
  -e SOURCE_AZURE_STORAGE_CONTAINER='chicken-images' \
  api npm run migrate-images
```

Der Kopierlauf bricht bei einem fehlenden Quellbild ab und verändert die Azure-Quelle nicht. Wiederholungen überschreiben dieselben UUID-Schlüssel sicher. Erst nach Prüfung der Bilder sollte der alte Azure-Speicher abgeschaltet werden.

## Backups

`database/backup.sh [Zielverzeichnis]` sichert beide PostgreSQL-Datenbanken: ESMA und Keycloak. Bei `STORAGE_DRIVER=local` wird zusätzlich das Bild-Volume archiviert. Speichere Backups außerhalb des Servers und richte regelmäßige Aufbewahrung/Rotation ein. Für S3 und Azure sind zusätzlich die Backup- oder Versionierungsfunktionen des jeweiligen Speicheranbieters zu konfigurieren.

Wiederherstellung erfolgt in eine gestoppte bzw. leere Installation mit `pg_restore` für beide Datenbanken; bei lokalem Bildspeicher das Archiv in das Volume `image_data` zurückspielen. Vor einer produktiven Wiederherstellung die Zielinstallation und Backups sichern.

## Entwicklung

Voraussetzungen: Flutter, Node.js 22 und Docker Compose. Kopiere `.env.example` nach `.env`, setze lokale Passwörter und nutze `APP_DOMAIN=localhost`, `AUTH_DOMAIN=auth.localhost`. Caddy verwendet für lokale Domains seine interne Zertifizierungsstelle; der Browser muss dem lokalen Zertifikat vertrauen.

```sh
npm --prefix web-auth install
npm --prefix web-auth run build
docker compose up -d --build
```

Öffne `https://localhost`. Für den öffentlichen Bereich sind keine Demo-Zugangsdaten eingebaut. Admin-Funktionen benötigen ein Keycloak-Konto mit Realm-Rolle `admin`.

## API

- `GET /api/v1/public/chickens` – verfügbare, freigegebene Profile
- `GET /api/v1/public/images/{chickenId}` – Bilder veröffentlichter Hühner
- `POST /api/v1/public/requests` – öffentliche Patenschafts-/Wartelistenanfrage
- `GET|POST /api/v1/admin/chickens` und `PUT|DELETE /api/v1/admin/chickens/{id}` – Hühnerverwaltung
- `GET|POST /api/v1/admin/sponsorships` und `PUT /api/v1/admin/sponsorships/{id}` – Patenschaften
- `GET /api/v1/admin/requests` und `PUT /api/v1/admin/requests/{id}` – Anfragen
- `POST /api/v1/admin/wix/sync` – veröffentlichte Profile mit Wix abgleichen

Admin-Endpunkte verlangen ein gültiges OIDC-Bearer-Token mit Keycloak-Realm-Rolle `admin` und passender API-Audience. Kontaktdaten werden nur intern gespeichert. Wix bleibt optional; Stripe und EasyVerein sind nicht integriert.
