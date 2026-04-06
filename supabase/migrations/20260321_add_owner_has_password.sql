-- Add has_password column to owners table
-- This tracks whether a Google-only user has set a password, unlocking manual login option

ALTER TABLE owners
ADD COLUMN IF NOT EXISTS has_password BOOLEAN NOT NULL DEFAULT false;

-- Create index for efficient queries on has_password
CREATE INDEX IF NOT EXISTS idx_owners_has_password ON owners(has_password);

-- Update existing records with manually-created accounts to have has_password=true
-- (Owners created via manual signup always have password)
UPDATE owners
SET has_password = true
WHERE has_password = false
	AND 'email' = ANY(auth_methods)
	AND NOT ('google' = ANY(auth_methods));

-- Update backend RPC to handle has_password parameter
-- The create_owner_profile RPC should accept user_has_password parameter:
-- 
-- CREATE OR REPLACE FUNCTION create_owner_profile(
--   user_id UUID,
--   user_name TEXT,
--   user_email TEXT,
--   user_phone TEXT,
--   user_has_password BOOLEAN DEFAULT false
-- )
-- RETURNS void AS $$
-- BEGIN
--   INSERT INTO owners (id, name, email, phone, has_password, auth_methods, created_at)
--   VALUES (user_id, user_name, user_email, user_phone, user_has_password, ARRAY['email'], NOW())
--   ON CONFLICT (id) DO UPDATE SET
--     has_password = EXCLUDED.has_password;
-- END;
-- $$ LANGUAGE plpgsql SECURITY DEFINER;
