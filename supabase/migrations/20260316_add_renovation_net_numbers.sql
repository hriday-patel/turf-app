-- Migration: Add renovation_net_numbers to turfs
-- Supports net-level closure when turf status is RENOVATION

ALTER TABLE turfs
ADD COLUMN IF NOT EXISTS renovation_net_numbers int[] NOT NULL DEFAULT array[]::int[];

-- Keep only positive net numbers and avoid NULL arrays.
-- This is best-effort cleanup for existing rows.
UPDATE turfs
SET renovation_net_numbers = (
  SELECT COALESCE(array_agg(v), array[]::int[])
  FROM (
    SELECT DISTINCT x AS v
    FROM unnest(COALESCE(renovation_net_numbers, array[]::int[])) AS x
    WHERE x > 0
    ORDER BY x
  ) t
);
