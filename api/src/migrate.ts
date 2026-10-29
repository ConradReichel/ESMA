import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Pool } from 'pg';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  host: process.env.PGHOST,
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE,
  ssl: process.env.PGSSLMODE === 'disable' ? false : undefined,
});

async function main(): Promise<void> {
  const schema = await readFile(process.env.SCHEMA_PATH || join(__dirname, '../../../database/schema.sql'), 'utf8');
  await pool.query(schema);
  console.log('Database schema applied.');
}

main().catch((error) => { console.error('Database migration failed:', error); process.exitCode = 1; }).finally(() => pool.end());
