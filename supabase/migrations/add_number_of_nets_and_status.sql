-- Migration: Add number_of_nets and status columns to turfs table
-- Run this in your Supabase SQL Editor (Dashboard > SQL Editor > New Query)

-- Add number_of_nets column (default 1)
ALTER TABLE turfs 
ADD COLUMN IF NOT EXISTS number_of_nets int NOT NULL DEFAULT 1;

-- Add status column (default 'OPEN')
ALTER TABLE turfs 
ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'OPEN';

-- Add check constraint for status values
ALTER TABLE turfs 
ADD CONSTRAINT turfs_status_check 
CHECK (status IN ('OPEN', 'CLOSED', 'RENOVATION'))
NOT VALID;

-- Validate the constraint (this will check existing rows)
ALTER TABLE turfs VALIDATE CONSTRAINT turfs_status_check;

-- Update any existing turfs to have default values (optional, just in case)
UPDATE turfs SET number_of_nets = 1 WHERE number_of_nets IS NULL;
UPDATE turfs SET status = 'OPEN' WHERE status IS NULL;
