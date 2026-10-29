import { Pool } from 'pg';
import { BlobServiceClient } from '@azure/storage-blob';
import { createStorage } from './storage';

async function main(): Promise<void> {
  const sourceConnection = process.env.SOURCE_AZURE_STORAGE_CONNECTION_STRING;
  if (!sourceConnection) throw new Error('SOURCE_AZURE_STORAGE_CONNECTION_STRING fehlt.');
  if ((process.env.STORAGE_DRIVER || 'local') === 'azure-blob') throw new Error('Ziel-STORAGE_DRIVER darf nicht azure-blob sein.');
  const source = BlobServiceClient.fromConnectionString(sourceConnection)
    .getContainerClient(process.env.SOURCE_AZURE_STORAGE_CONTAINER || 'chicken-images');
  const target = createStorage();
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    host: process.env.PGHOST,
    port: Number(process.env.PGPORT || 5432),
    user: process.env.PGUSER,
    password: process.env.PGPASSWORD,
    database: process.env.PGDATABASE,
    ssl: process.env.PGSSLMODE === 'disable' ? false : undefined,
  });
  try {
    const { rows } = await pool.query("SELECT id FROM chickens WHERE image_url <> '' ORDER BY id");
    let migrated = 0;
    for (const row of rows) {
      const id = String(row.id);
      const blob = source.getBlockBlobClient(id);
      const exists = await blob.exists();
      if (!exists) throw new Error(`Azure-Bild für Huhn ${id} fehlt; Migration abgebrochen.`);
      const bytes = await blob.downloadToBuffer();
      const properties = await blob.getProperties();
      const contentType = properties.contentType || 'application/octet-stream';
      await target.put(id, bytes, contentType);
      migrated++;
    }
    console.log(`${migrated} Bilder migriert. Azure-Quelle wurde nicht verändert.`);
  } finally { await pool.end(); }
}

main().catch((error) => { console.error('Bildmigration fehlgeschlagen:', error); process.exitCode = 1; });
