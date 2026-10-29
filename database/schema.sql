CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS app_settings (
  key text PRIMARY KEY,
  value text NOT NULL DEFAULT ''
);
INSERT INTO app_settings (key, value) VALUES
  ('organization_name', ''), ('location', ''), ('logo_url', '')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS chickens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number text NOT NULL UNIQUE,
  name text NOT NULL,
  ring_number text,
  breed text NOT NULL DEFAULT '',
  sex text NOT NULL DEFAULT 'Huhn',
  color text NOT NULL DEFAULT '',
  hatch_year integer CHECK (hatch_year IS NULL OR hatch_year BETWEEN 1900 AND 2200),
  description text NOT NULL DEFAULT '',
  image_url text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('available','reserved','sponsored','inactive')),
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS chickens_public_available_idx ON chickens (published, status);

CREATE TABLE IF NOT EXISTS contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name text NOT NULL,
  last_name text NOT NULL,
  email text NOT NULL UNIQUE,
  phone text NOT NULL DEFAULT '',
  external_easyverein_id text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sponsorships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chicken_id uuid NOT NULL REFERENCES chickens(id) ON DELETE RESTRICT,
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('pending','active','ended','cancelled')),
  starts_on date,
  ends_on date,
  amount_cents integer CHECK (amount_cents IS NULL OR amount_cents >= 0),
  payment_frequency text NOT NULL DEFAULT '',
  notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_sponsorship_per_chicken
  ON sponsorships(chicken_id) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS inquiries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chicken_id uuid REFERENCES chickens(id) ON DELETE SET NULL,
  first_name text NOT NULL,
  last_name text NOT NULL,
  email text NOT NULL,
  phone text NOT NULL DEFAULT '',
  message text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new','in_progress','accepted','declined','converted')),
  privacy_accepted boolean NOT NULL DEFAULT false CHECK (privacy_accepted),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS wix_sync_state (
  chicken_id uuid PRIMARY KEY REFERENCES chickens(id) ON DELETE CASCADE,
  synced_at timestamptz NOT NULL DEFAULT now(),
  last_error text
);
