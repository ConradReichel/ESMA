# ESMA – Hühnerpatenmanager

Flutter-Webanwendung für die interne Verwaltung von Hühnerprofilen, Patenschaften und Interessentenanfragen. Die App ist als führende Datenquelle vorgesehen; öffentlich freigegebene Hühner können über die API und per Wix-CMS-Synchronisierung veröffentlicht werden.

## Projektstruktur

- `app/`: Flutter Web UI
- `api/`: Azure Functions v4 API in TypeScript
- `database/`: PostgreSQL-Schema
- `staticwebapp.config.json`: Entra ID Anmeldung und Admin-Routen
- `infra/`: Azure Developer CLI Bereitstellung

## Lokal starten

Voraussetzungen: Flutter mit Web-Unterstützung, Node.js 22, Azure Functions Core Tools v4 und Docker Compose.

1. Lokale Function-Speicheremulation und PostgreSQL starten: `docker compose up -d`.
2. API einrichten: `cd api && cp local.settings.example.json local.settings.json && npm install && npm run build && npm start`.
3. Flutter starten: in einem zweiten Terminal `cd app && flutter pub get && flutter run -d chrome --web-port=4280 --dart-define=ESMA_API_URL=http://localhost:7071`.
4. Der lokale Function-Host läuft im Development-Modus; `ESMA_DEMO_MODE=true` erlaubt nur lokal die Admin-Oberfläche ohne Entra-Anmeldung. Diese Einstellung darf nicht in Azure gesetzt werden.

## Azure bereitstellen

Die Bicep-Vorlage in `infra/main.bicep` stellt eine Azure Static Web App Standard und Azure Database for PostgreSQL Flexible Server bereit. Die HTTP-API läuft als integrierte, verwaltete Azure-Functions-API der Static Web App. Damit übernimmt Static Web Apps Anmeldung, Rollenprüfung und `/api`-Routing; eine separate Function-App muss nicht betrieben werden. Die Wix-Synchronisierung wird im Adminbereich manuell ausgelöst.

Kopiere `infra/main.parameters.example.json` nach `infra/main.parameters.json`, setze ein starkes Datenbankpasswort und ergänze bei Bedarf Wix-Zugangsdaten (die echte Parameterdatei ist in `.gitignore`). Infrastruktur bereitstellen: `az deployment group create --resource-group <resource-group> --template-file infra/main.bicep --parameters @infra/main.parameters.json`. Lege für die GitHub Actions das Static-Web-Apps-Deploymenttoken als Repository-Secret `AZURE_STATIC_WEB_APPS_API_TOKEN` an. Der Workflow baut Flutter und Functions und veröffentlicht beides.

Die API wendet `database/schema.sql` beim ersten Function-Aufruf idempotent an; `database/apply.sh` ist für manuelle Migrationen verfügbar. Die Vorlage gestattet PostgreSQL-Zugriff vom Azure-Dienstnetz (Firewallregel `0.0.0.0`); der Datenbankzugang ist zusätzlich mit TLS und Passwort geschützt. Für produktive Anforderungen an Netzwerkisolation muss die API auf einen Host mit privatem Datenbankzugang umgestellt werden.

Microsoft Entra ID ist als integrierter Identitätsanbieter von Static Web Apps verfügbar. Weise ausschließlich den zugelassenen Vereinskonten die benutzerdefinierte Static-Web-Apps-Rolle `admin` zu: Azure Portal → Static Web App → **Settings → Role Management → Invite**, Identitätsanbieter Microsoft Entra ID auswählen und `admin` als Rolle eintragen. [Microsoft-Anleitung zur Rollenverwaltung](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-custom#manage-roles). Die Admin-Oberfläche liegt unter `/admin`; die API prüft die über Static Web Apps übermittelte Rolle zusätzlich zu den geschützten Routen.

### PostgreSQL

Lokale Verbindung:

```text
postgresql://esma:esma-local-only@localhost:5432/esma
```

Docker lädt `database/schema.sql` beim Erstellen des lokalen Datenbank-Volumes. Azure-Schemata werden beim ersten API-Aufruf angewendet; `database/apply.sh` kann ein Schema manuell neu anwenden. Für Azure verwendet der PostgreSQL-Client TLS.

### Wix CMS

Erstelle eine Wix-CMS-Sammlung mit ID `Patenhuehner` (oder setze `WIX_COLLECTION_ID`) und stelle die dafür nötigen Wix API-Berechtigungen bereit. Die Synchronisierung überträgt nur veröffentlichte Profile mit Name, Nummer, Rasse, Geschlecht, Farbe, Schlupfjahr, Beschreibung, Bild-URL und Verfügbarkeitsstatus. Die stabile Hühner-ID dient als Wix Item-ID, damit wiederholte Synchronisierung Einträge aktualisiert statt zu duplizieren. Filtere die Wix-Website auf `isAvailable = true`; nicht mehr veröffentlichte Profile werden bei der nächsten Synchronisierung aus der Wix-Sammlung entfernt. Wix-Speicherfehler sind im API-Log sichtbar. Der Wix-API-Schlüssel wird als Function-App-Einstellung der Static Web App gespeichert. Für direkte Browserabfragen der öffentlichen API ist `CORS_ORIGIN` auf die Vereinswebsite beschränkt; passe `publicWebsiteOrigin` in der Parameterdatei an, falls Wix eine andere veröffentlichte Domain verwendet.

## API (v1)

- `GET /api/v1/public/chickens` – verfügbare, freigegebene Hühnerprofile.
- `POST /api/v1/public/requests` – öffentliche Patenschafts-/Wartelistenanfrage.
- `GET|POST /api/v1/admin/chickens` und `PUT|DELETE /api/v1/admin/chickens/{id}` – Hühnerverwaltung.
- `GET|POST /api/v1/admin/sponsorships` und `PUT /api/v1/admin/sponsorships/{id}` – Patenschaften.
- `GET /api/v1/admin/requests` und `PUT /api/v1/admin/requests/{id}` – Anfrageverwaltung.
- `POST /api/v1/admin/wix/sync` – veröffentlichte Profile mit Wix abgleichen.

Kontaktdaten werden ausschließlich intern gespeichert und nie in der öffentlichen API-Antwort oder Wix-Payload ausgegeben. Stripe und EasyVerein sind noch nicht integriert; externe Kontakt-IDs sind im Datenmodell vorgesehen.

## Fachliche Hinweise

Beiträge und Vertragsbedingungen werden nicht fest vorgegeben. Eine Patenschaft speichert den individuell vereinbarten Betrag, Zahlungsrhythmus, Beginn, Ende und Status, ohne Zahlungen auszulösen. Die Anwendung erfindet keine Vereinsregeln und ersetzt keine Vertrags- oder Spendenabwicklung.
