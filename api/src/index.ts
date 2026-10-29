import Fastify from 'fastify';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { randomUUID } from 'node:crypto';
import { Pool, types } from 'pg';
import { createStorage } from './storage';

types.setTypeParser(1082, (value) => value);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || undefined,
  host: process.env.PGHOST || undefined,
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER || undefined,
  password: process.env.PGPASSWORD || undefined,
  database: process.env.PGDATABASE || undefined,
  ssl: process.env.PGSSLMODE === 'disable' ? false : { rejectUnauthorized: process.env.PGSSL_REJECT_UNAUTHORIZED !== 'false' },
  max: 8,
  idleTimeoutMillis: 30_000,
});
const maxImageBytes = 5 * 1024 * 1024;
const storage = createStorage();

type HttpRequest = { method: string; url: string; headers: { get(name: string): string | null }; json(): Promise<unknown> };
type HttpResponseInit = { status?: number; headers?: Record<string, string>; jsonBody?: unknown; body?: Buffer | string };
type InvocationContext = { error(message: string, error?: unknown): void; warn(message: string, error?: unknown): void };

function imageMime(bytes: Buffer): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return 'image/png';
  if (bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}

function publicImageUrl(id: string): string {
  return `${(process.env.PUBLIC_APP_URL || '').replace(/\/$/, '')}/api/v1/public/images/${id}`;
}

const corsHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  ...(process.env.CORS_ORIGIN ? { 'Access-Control-Allow-Origin': process.env.CORS_ORIGIN } : {}),
};

function json(status: number, body: unknown): HttpResponseInit {
  return { status, headers: corsHeaders, jsonBody: body };
}

function idFrom(url: URL, marker: string): string | null {
  const parts = url.pathname.split('/').filter(Boolean);
  const index = parts.indexOf(marker);
  return index >= 0 && parts[index + 1] ? parts[index + 1] : null;
}

async function bodyOf(request: HttpRequest): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    return value && typeof value === 'object' ? value as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function text(value: unknown, max = 500): string {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function isEmail(value: string): boolean { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value); }
function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }

let jwks: ReturnType<typeof createRemoteJWKSet> | null = null;
async function isAdmin(request: HttpRequest): Promise<boolean> {
  const authorization = request.headers.get('authorization') || '';
  if (!authorization.startsWith('Bearer ')) return false;
  const issuer = process.env.OIDC_ISSUER;
  const jwksUrl = process.env.OIDC_JWKS_URL;
  if (!issuer || !jwksUrl) return false;
  try {
    jwks ??= createRemoteJWKSet(new URL(jwksUrl));
    const { payload } = await jwtVerify(authorization.slice(7), jwks, {
      issuer,
      audience: process.env.OIDC_AUDIENCE || 'esma-api',
      algorithms: ['RS256'],
    });
    const realmRoles = (payload.realm_access as { roles?: unknown } | undefined)?.roles;
    const clientRoles = (payload.resource_access as Record<string, { roles?: unknown }> | undefined)?.['esma-api']?.roles;
    return (Array.isArray(realmRoles) && realmRoles.includes('admin')) || (Array.isArray(clientRoles) && clientRoles.includes('admin'));
  } catch { return false; }
}

async function adminOnly(request: HttpRequest): Promise<HttpResponseInit | null> {
  return await isAdmin(request) ? null : json(401, { error: 'Für diesen Bereich ist eine Admin-Anmeldung erforderlich.' });
}

function chickenRow(row: Record<string, unknown>) {
  return {
    id: row.id,
    number: row.number,
    name: row.name,
    ringNumber: row.ring_number ?? '',
    breed: row.breed ?? '',
    sex: row.sex ?? 'Huhn',
    color: row.color ?? '',
    hatchYear: row.hatch_year ?? null,
    description: row.description ?? '',
    imageUrl: row.image_url ?? '',
    status: row.status,
    published: row.published,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function handler(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  if (request.method === 'OPTIONS') return json(204, {});
  const path = new URL(request.url).pathname.replace(/\/$/, '');
  const method = request.method;
  try {
    if (path.startsWith('/api/v1/admin/')) {
      const denied = await adminOnly(request);
      if (denied) return denied;
    }
    const knownPath = path === '/api/v1/public/chickens' || path === '/api/v1/public/requests' || path.startsWith('/api/v1/public/images/') ||
      path === '/api/v1/admin/chickens' || path.startsWith('/api/v1/admin/chickens/') ||
      path === '/api/v1/admin/sponsorships' || path.startsWith('/api/v1/admin/sponsorships/') ||
      path === '/api/v1/admin/requests' || path.startsWith('/api/v1/admin/requests/') ||
      path === '/api/v1/admin/wix/sync';
    if (!knownPath) return json(404, { error: 'API-Endpunkt nicht gefunden.' });
    const imageId = path.startsWith('/api/v1/public/images/') ? path.slice('/api/v1/public/images/'.length) : '';
    if (imageId && method === 'GET') {
      if (!isUuid(imageId)) return json(404, { error: 'Bild nicht gefunden.' });
      const chicken = await pool.query('SELECT image_url FROM chickens WHERE id=$1::uuid AND published=true', [imageId]);
      if (!chicken.rowCount || !String(chicken.rows[0].image_url || '').endsWith(`/public/images/${imageId}`)) return json(404, { error: 'Bild nicht gefunden.' });
      const download = await storage.get(imageId);
      if (!download) return json(404, { error: 'Bild nicht gefunden.' });
      const mime = imageMime(download);
      if (!mime) return json(404, { error: 'Bild nicht gefunden.' });
      return { status: 200, headers: { 'Content-Type': mime, 'Cache-Control': 'public, max-age=3600', 'X-Content-Type-Options': 'nosniff', ...(process.env.CORS_ORIGIN ? { 'Access-Control-Allow-Origin': process.env.CORS_ORIGIN } : {}) }, body: download };
    }
    if (path === '/api/v1/public/chickens' && method === 'GET') {
      const result = await pool.query("SELECT id, number, name, breed, sex, color, hatch_year, description, image_url, status FROM chickens WHERE published = true AND status = 'available' ORDER BY number");
      return json(200, { items: result.rows.map(publicChicken), updatedAt: new Date().toISOString() });
    }

    if (path === '/api/v1/public/requests' && method === 'POST') {
      const body = await bodyOf(request);
      const firstName = text(body.firstName, 100), lastName = text(body.lastName, 100), email = text(body.email, 254).toLowerCase();
      if (!firstName || !lastName || !isEmail(email) || body.privacyAccepted !== true) return json(400, { error: 'Bitte fülle alle Pflichtfelder aus und bestätige den Datenschutzhinweis.' });
      const chickenId = text(body.chickenId, 36) || null;
      if (chickenId) {
        if (!isUuid(chickenId)) return json(400, { error: 'Die Hühnerkennung ist ungültig.' });
        const chicken = await pool.query("SELECT 1 FROM chickens WHERE id=$1::uuid AND published=true AND status='available'", [chickenId]);
        if (!chicken.rowCount) return json(400, { error: 'Dieses Huhn ist derzeit nicht für eine Anfrage verfügbar.' });
      }
      const result = await pool.query(
        `INSERT INTO inquiries (chicken_id, first_name, last_name, email, phone, message, privacy_accepted)
         VALUES ($1::uuid, $2, $3, $4, $5, $6, true) RETURNING id, created_at`,
        [chickenId, firstName, lastName, email, text(body.phone, 40), text(body.message, 1500)],
      );
      return json(201, { id: result.rows[0].id, createdAt: result.rows[0].created_at, message: 'Danke für dein Interesse. Der Verein meldet sich bei dir.' });
    }

    if (path === '/api/v1/admin/chickens' || path.startsWith('/api/v1/admin/chickens/')) {
      const denied = await adminOnly(request); if (denied) return denied;
      if (path === '/api/v1/admin/chickens' && method === 'GET') {
        const result = await pool.query('SELECT * FROM chickens ORDER BY number');
        return json(200, { items: result.rows.map(chickenRow) });
      }
      if (path === '/api/v1/admin/chickens' && method === 'POST') {
        const data = await bodyOf(request);
        const number = text(data.number, 20), name = text(data.name, 100);
        if (!number || !name) return json(400, { error: 'Huhnnummer und Name sind erforderlich.' });
        const image = readImage(data);
        if (image.error) return json(400, { error: image.error });
        const newId = randomUUID();
        if (image.bytes) {
          try { await storage.put(newId, image.bytes, image.mime!); }
          catch (error) { context.error('Chicken image upload failed', error); return json(503, { error: 'Das Bild konnte nicht gespeichert werden. Bitte prüfe den lokalen Bildspeicher.' }); }
        }
        const result = await pool.query(
          `INSERT INTO chickens (id,number,name,ring_number,breed,sex,color,hatch_year,description,image_url,status,published)
           VALUES ($1::uuid,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`,
          [newId,number,name,text(data.ringNumber,50),text(data.breed,100),text(data.sex,40)||'Huhn',text(data.color,100),Number(data.hatchYear)||null,text(data.description,2000),image.bytes ? publicImageUrl(newId) : '',allowed(data.status,['available','reserved','sponsored','inactive'],'available'),data.published===true],
        );
        return json(201, chickenRow(result.rows[0]));
      }
      const chickenId = idFrom(new URL(request.url), 'chickens');
      if (!chickenId) return json(404, { error: 'Huhn nicht gefunden.' });
      if (method === 'DELETE') {
        if (!isUuid(chickenId)) return json(404, { error: 'Huhn nicht gefunden.' });
        const current = await pool.query('SELECT image_url FROM chickens WHERE id=$1::uuid', [chickenId]);
        if (!current.rowCount) return json(404, { error: 'Huhn nicht gefunden.' });
        if (current.rows[0].image_url) await storage.delete(chickenId);
        await pool.query("UPDATE chickens SET status='inactive', published=false, image_url='', updated_at=now() WHERE id=$1::uuid", [chickenId]);
        return json(200, { ok: true });
      }
      if (method === 'PUT') {
        const data = await bodyOf(request);
        if (!isUuid(chickenId)) return json(404, { error: 'Huhn nicht gefunden.' });
        const image = readImage(data);
        if (image.error) return json(400, { error: image.error });
        if (image.bytes) {
          try { await storage.put(chickenId, image.bytes, image.mime!); }
          catch (error) { context.error('Chicken image upload failed', error); return json(503, { error: 'Das Bild konnte nicht gespeichert werden. Bitte prüfe den lokalen Bildspeicher.' }); }
        } else if (data.clearImage === true) {
          await storage.delete(chickenId);
        }
        const current = await pool.query('SELECT image_url FROM chickens WHERE id=$1::uuid', [chickenId]);
        if (!current.rowCount) return json(404, { error: 'Huhn nicht gefunden.' });
        const imageUrl = image.bytes ? publicImageUrl(chickenId) : data.clearImage === true ? '' : current.rows[0].image_url;
        const result = await pool.query(
          `UPDATE chickens SET number=$2,name=$3,ring_number=$4,breed=$5,sex=$6,color=$7,hatch_year=$8,description=$9,image_url=$10,status=$11,published=$12,updated_at=now()
           WHERE id=$1::uuid RETURNING *`,
          [chickenId,text(data.number,20),text(data.name,100),text(data.ringNumber,50),text(data.breed,100),text(data.sex,40)||'Huhn',text(data.color,100),Number(data.hatchYear)||null,text(data.description,2000),imageUrl,allowed(data.status,['available','reserved','sponsored','inactive'],'available'),data.published===true],
        );
        return result.rowCount ? json(200, chickenRow(result.rows[0])) : json(404, { error: 'Huhn nicht gefunden.' });
      }
    }

    if (path === '/api/v1/admin/sponsorships' || path.startsWith('/api/v1/admin/sponsorships/')) {
      const denied = await adminOnly(request); if (denied) return denied;
      if (path.endsWith('/sponsorships') && method === 'GET') {
        const result = await pool.query(`SELECT s.*, c.first_name,c.last_name,c.email,c.phone,h.name AS chicken_name,h.number AS chicken_number
          FROM sponsorships s JOIN contacts c ON c.id=s.contact_id JOIN chickens h ON h.id=s.chicken_id ORDER BY s.created_at DESC`);
        return json(200, { items: result.rows });
      }
      if (path.endsWith('/sponsorships') && method === 'POST') {
        const data = await bodyOf(request);
        const firstName=text(data.firstName,100),lastName=text(data.lastName,100),email=text(data.email,254).toLowerCase(),chickenId=text(data.chickenId,36);
        if(!firstName||!lastName||!isEmail(email)||!chickenId) return json(400,{error:'Kontakt, gültige E-Mail und Huhn sind erforderlich.'});
        const client=await pool.connect();
        try {
          await client.query('BEGIN');
          const contact=await client.query(`INSERT INTO contacts(first_name,last_name,email,phone) VALUES($1,$2,$3,$4)
            ON CONFLICT (email) DO UPDATE SET first_name=EXCLUDED.first_name,last_name=EXCLUDED.last_name,phone=EXCLUDED.phone,updated_at=now() RETURNING id`,[firstName,lastName,email,text(data.phone,40)]);
          const result=await client.query(`INSERT INTO sponsorships(chicken_id,contact_id,status,starts_on,ends_on,amount_cents,payment_frequency,notes)
            VALUES($1::uuid,$2::uuid,$3,$4,$5,$6,$7,$8) RETURNING *`,[chickenId,contact.rows[0].id,allowed(data.status,['pending','active','ended','cancelled'],'active'),dateOrNull(data.startsOn),dateOrNull(data.endsOn),data.amount==null?null:Math.round(Number(data.amount)*100),text(data.paymentFrequency,40),text(data.notes,1500)]);
          if(allowed(data.status,['pending','active'],'active')==='active') await client.query("UPDATE chickens SET status='sponsored',updated_at=now() WHERE id=$1::uuid",[chickenId]);
          await client.query('COMMIT'); return json(201,{item:result.rows[0]});
        } catch(error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
      }
      const sponsorshipId=idFrom(new URL(request.url),'sponsorships');
      if(sponsorshipId&&method==='PUT') {
        const data=await bodyOf(request);
        const client=await pool.connect();
        try {
          await client.query('BEGIN');
          const result=await client.query(`UPDATE sponsorships SET status=$2,starts_on=COALESCE($3::date,starts_on),ends_on=COALESCE($4::date,ends_on),amount_cents=COALESCE($5,amount_cents),payment_frequency=COALESCE(NULLIF($6,''),payment_frequency),notes=COALESCE(NULLIF($7,''),notes),updated_at=now() WHERE id=$1::uuid RETURNING *`,
            [sponsorshipId,allowed(data.status,['pending','active','ended','cancelled'],'active'),dateOrNull(data.startsOn),dateOrNull(data.endsOn),data.amount==null?null:Math.round(Number(data.amount)*100),text(data.paymentFrequency,40),text(data.notes,1500)]);
          if(!result.rowCount){await client.query('ROLLBACK');return json(404,{error:'Patenschaft nicht gefunden.'});}
          const chickenId=result.rows[0].chicken_id;
          const active=await client.query("SELECT 1 FROM sponsorships WHERE chicken_id=$1 AND status='active' LIMIT 1",[chickenId]);
          if(active.rowCount) await client.query("UPDATE chickens SET status='sponsored',updated_at=now() WHERE id=$1",[chickenId]);
          else await client.query("UPDATE chickens SET status='available',updated_at=now() WHERE id=$1 AND status='sponsored'",[chickenId]);
          await client.query('COMMIT'); return json(200,{item:result.rows[0]});
        } catch(error){await client.query('ROLLBACK');throw error;} finally {client.release();}
      }
    }

    if (path === '/api/v1/admin/requests' || path.startsWith('/api/v1/admin/requests/')) {
      const denied = await adminOnly(request); if (denied) return denied;
      if (path.endsWith('/requests') && method === 'GET') {
        const result=await pool.query(`SELECT i.*,h.name AS chicken_name,h.number AS chicken_number FROM inquiries i LEFT JOIN chickens h ON h.id=i.chicken_id ORDER BY i.created_at DESC`);
        return json(200,{items:result.rows});
      }
      const requestId=idFrom(new URL(request.url),'requests');
      if(requestId&&method==='PUT') {
        const data=await bodyOf(request);
        const result=await pool.query(`UPDATE inquiries SET status=$2,updated_at=now() WHERE id=$1::uuid RETURNING id,status,updated_at`,[requestId,allowed(data.status,['new','in_progress','accepted','declined','converted'],'new')]);
        return result.rowCount?json(200,{item:result.rows[0]}):json(404,{error:'Anfrage nicht gefunden.'});
      }
    }

    if(path==='/api/v1/admin/wix/sync'&&method==='POST') {
      const denied=await adminOnly(request); if(denied)return denied;
      const result=await syncWix(context);
      return json(result.failed?502:200,result);
    }
    return json(404,{error:'API-Endpunkt nicht gefunden.'});
  } catch (error) {
    context.error('API request failed', error);
    if ((error as { code?: string }).code === '23505') return json(409, { error: 'Dieser Eintrag existiert bereits.' });
    return json(500, { error: 'Die Anfrage konnte nicht verarbeitet werden.' });
  }
}

function allowed(value: unknown, values: string[], fallback: string): string { return typeof value === 'string' && values.includes(value) ? value : fallback; }
function readImage(data: Record<string, unknown>): { bytes?: Buffer; mime?: string; error?: string } {
  if (data.imageData == null || data.imageData === '') return {};
  if (typeof data.imageData !== 'string' || data.imageData.length > Math.ceil(maxImageBytes * 4 / 3) + 8) return { error: 'Bilder dürfen höchstens 5 MB groß sein.' };
  const bytes = Buffer.from(data.imageData, 'base64');
  if (!bytes.length || bytes.length > maxImageBytes || bytes.toString('base64') !== data.imageData) return { error: 'Das Bild ist ungültig oder größer als 5 MB.' };
  const mime = imageMime(bytes);
  if (!mime || data.imageMimeType !== mime) return { error: 'Bitte verwende ein gültiges JPG-, PNG- oder WebP-Bild.' };
  return { bytes, mime };
}
function dateOrNull(value: unknown): string | null { return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null; }
function publicChicken(row: Record<string, unknown>) {
  const imageUrl = row.image_url ?? row.imageUrl;
  return { id:row.id,number:row.number,name:row.name,breed:row.breed,sex:row.sex,color:row.color,hatchYear:row.hatch_year??row.hatchYear,description:row.description,imageUrl: imageUrl ? publicImageUrl(String(row.id)) : '' };
}

async function syncWix(context: InvocationContext) {
  const { WIX_API_KEY, WIX_SITE_ID, WIX_COLLECTION_ID }=process.env;
  if(!WIX_API_KEY||!WIX_SITE_ID||!WIX_COLLECTION_ID) return { failed:true, synced:0, error:'Wix-Konfiguration fehlt.' };
  const chickens=await pool.query("SELECT id,number,name,breed,sex,color,hatch_year,description,image_url,status FROM chickens WHERE published=true ORDER BY number");
  let synced=0,failed=0;
  for(const row of chickens.rows) {
    const payload={dataCollectionId:WIX_COLLECTION_ID,dataItem:{id:String(row.id),data:{number:row.number,name:row.name,breed:row.breed,sex:row.sex,color:row.color,hatchYear:row.hatch_year,description:row.description,imageUrl:row.image_url ? publicImageUrl(String(row.id)) : '',status:row.status,isAvailable:row.status==='available'}}};
    try {
      const response=await fetch('https://www.wixapis.com/wix-data/v2/items/save',{method:'POST',headers:{Authorization:WIX_API_KEY,'wix-site-id':WIX_SITE_ID,'Content-Type':'application/json'},body:JSON.stringify(payload)});
      if(!response.ok) throw new Error(`Wix API HTTP ${response.status}`);
      await pool.query('INSERT INTO wix_sync_state(chicken_id,synced_at,last_error) VALUES($1::uuid,now(),NULL) ON CONFLICT(chicken_id) DO UPDATE SET synced_at=now(),last_error=NULL',[row.id]); synced++;
    } catch(error) {
      const message=error instanceof Error?error.message:'Wix Sync fehlgeschlagen';
      await pool.query('INSERT INTO wix_sync_state(chicken_id,synced_at,last_error) VALUES($1::uuid,now(),$2) ON CONFLICT(chicken_id) DO UPDATE SET synced_at=now(),last_error=EXCLUDED.last_error',[row.id,message]);
      context.warn('Wix sync failed for chicken '+row.id,message); failed++;
    }
  }
  const hidden=await pool.query('SELECT chicken_id FROM wix_sync_state WHERE chicken_id NOT IN (SELECT id FROM chickens WHERE published=true)');
  for(const row of hidden.rows) {
    try {
      const response=await fetch(`https://www.wixapis.com/wix-data/v2/items/${row.chicken_id}?dataCollectionId=${encodeURIComponent(WIX_COLLECTION_ID)}`,{method:'DELETE',headers:{Authorization:WIX_API_KEY,'wix-site-id':WIX_SITE_ID}});
      if(!response.ok&&response.status!==404) throw new Error(`Wix API HTTP ${response.status}`);
      await pool.query('DELETE FROM wix_sync_state WHERE chicken_id=$1::uuid',[row.chicken_id]);
    } catch(error) { context.warn('Wix cleanup failed for chicken '+row.chicken_id,error); failed++; }
  }
  return { synced,failed,updatedAt:new Date().toISOString() };
}

const api = Fastify({ logger: true, bodyLimit: 8 * 1024 * 1024 });
api.route({
  url: '/*', method: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  handler: async (request, reply) => {
    const context: InvocationContext = { error: (message, error) => request.log.error({ err: error }, message), warn: (message, error) => request.log.warn({ err: error }, message) };
    const adapted: HttpRequest = {
      method: request.method,
      url: `http://localhost${request.url}`,
      headers: { get: (name) => request.headers[name.toLowerCase()]?.toString() ?? null },
      json: async () => request.body,
    };
    const response = await handler(adapted, context);
    reply.code(response.status ?? 200);
    if (response.headers) reply.headers(response.headers);
    if (response.body) return reply.send(response.body);
    if (response.jsonBody !== undefined) return reply.send(response.jsonBody);
    return reply.send();
  },
});
api.get('/healthz', async () => ({ status: 'ok' }));
const port = Number(process.env.PORT || 3000);
const host = process.env.HOST || '0.0.0.0';
api.listen({ port, host }).catch((error) => { api.log.error(error); process.exit(1); });
