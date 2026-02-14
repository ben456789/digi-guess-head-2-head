-- =============================================================================
-- Supabase Migration: Recreate games table for Digimon version
-- Run this in your Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- AFTER you have backed up data you care about.
-- This will DROP and RECREATE the `games` table.
-- =============================================================================

-- 1) Drop old games table (Pokemon schema)
DROP TABLE IF EXISTS games CASCADE;

-- 2) Create new games table (Digimon schema)
CREATE TABLE games (
  game_code TEXT PRIMARY KEY,
  host_id TEXT NOT NULL,
  selected_levels INTEGER[] NOT NULL DEFAULT '{}',
  available_digimon JSONB NOT NULL DEFAULT '[]',
  players JSONB NOT NULL DEFAULT '{}',
  messages JSONB NOT NULL DEFAULT '[]',
  current_phase TEXT NOT NULL DEFAULT 'waitingForPlayers',
  current_player_id TEXT,
  winner TEXT,
  last_activity BIGINT,
  created_at BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
  time_left INTEGER NOT NULL DEFAULT 30,
  current_round INTEGER NOT NULL DEFAULT 1,
  max_rounds INTEGER NOT NULL DEFAULT 20,
  last_guess_result TEXT,
  current_guess TEXT,
  players_ready_to_play_again JSONB NOT NULL DEFAULT '{}',
  players_typing JSONB NOT NULL DEFAULT '{}'
);

-- 3) Enable Row Level Security
ALTER TABLE games ENABLE ROW LEVEL SECURITY;

-- 4) RLS Policies (open, Firebase-style anonymous access)

-- Allow anonymous users to SELECT any game
CREATE POLICY "Allow anonymous read" ON games
  FOR SELECT USING (true);

-- Allow anonymous users to INSERT games
CREATE POLICY "Allow anonymous insert" ON games
  FOR INSERT WITH CHECK (true);

-- Allow anonymous users to UPDATE any game
CREATE POLICY "Allow anonymous update" ON games
  FOR UPDATE USING (true);

-- Allow anonymous users to DELETE any game
CREATE POLICY "Allow anonymous delete" ON games
  FOR DELETE USING (true);

-- 5) Enable Realtime for the games table
-- Go to Supabase Dashboard → Database → Replication and ensure the 'games' table
-- is enabled for the `supabase_realtime` publication, or run:
ALTER PUBLICATION supabase_realtime ADD TABLE games;

-- 6) Index to support cleanup queries (find old games)
CREATE INDEX IF NOT EXISTS idx_games_created_at ON games (created_at);
