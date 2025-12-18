-- COMPLETE REPLACEMENT Supabase Schema for Selah Bible App
-- This schema exactly matches what your app expects via supabase_sync_service.dart
-- Run this in your Supabase SQL Editor to replace the current schema

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables if they exist (for clean replacement)
DROP TABLE IF EXISTS search_history CASCADE;
DROP TABLE IF EXISTS history CASCADE;
DROP TABLE IF EXISTS notes CASCADE;
DROP TABLE IF EXISTS highlights CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- Profiles table (extends auth.users)
-- NOTE: All column names are quoted to preserve exact case
CREATE TABLE profiles (
  "id" UUID REFERENCES auth.users(id) PRIMARY KEY,
  "username" TEXT UNIQUE NOT NULL,
  "created_at" TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Highlights table - EXACTLY matches what sync service expects
-- NOTE: All column names are quoted to preserve exact case
CREATE TABLE highlights (
  "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  "user_id" UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  "book" TEXT NOT NULL,
  "chapter" INTEGER NOT NULL,
  "verse" INTEGER NOT NULL,
  "start" INTEGER NOT NULL,
  "end" INTEGER NOT NULL,
  "color" BIGINT NOT NULL,
  "created_at" BIGINT NOT NULL UNIQUE, -- Used for upsert conflicts
  "updated_at" BIGINT NOT NULL -- Used for sync filtering
);

-- Notes table - EXACTLY matches what sync service expects  
-- NOTE: All column names are quoted to preserve exact case
CREATE TABLE notes (
  "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  "user_id" UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  "book" TEXT NOT NULL,
  "chapter" INTEGER NOT NULL,
  "verse" INTEGER NOT NULL,
  "note_text" TEXT NOT NULL,
  "created_at" BIGINT NOT NULL UNIQUE, -- Used for upsert conflicts
  "updated_at" BIGINT NOT NULL -- Used for sync filtering
);

-- History table - EXACTLY matches what sync service expects
-- NOTE: All column names are quoted to preserve exact case
CREATE TABLE history (
  "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  "user_id" UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  "book" TEXT NOT NULL,
  "chapter" INTEGER NOT NULL,
  "verse" INTEGER, -- Can be null for chapter-level history
  "timestamp" BIGINT NOT NULL UNIQUE -- Used for upsert conflicts
);

-- Search history table - EXACTLY matches what sync service expects
-- NOTE: All column names are quoted to preserve exact case
CREATE TABLE search_history (
  "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  "user_id" UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  "query" TEXT NOT NULL,
  "useRegex" BOOLEAN NOT NULL,
  "useNearby" BOOLEAN NOT NULL,
  "useWholeWord" BOOLEAN NOT NULL,
  "useRedLetter" BOOLEAN NOT NULL,
  "caseSensitive" BOOLEAN NOT NULL,
  "bookFilterType" TEXT NOT NULL,
  "customBookFilter" TEXT NOT NULL,
  "timestamp" BIGINT NOT NULL UNIQUE -- Used for upsert conflicts
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE highlights ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE history ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = "id");

CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = "id");

CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = "id");

-- RLS Policies for highlights
CREATE POLICY "Users can view own highlights" ON highlights
  FOR SELECT USING (auth.uid() = "user_id");

CREATE POLICY "Users can insert own highlights" ON highlights
  FOR INSERT WITH CHECK (auth.uid() = "user_id");

CREATE POLICY "Users can update own highlights" ON highlights
  FOR UPDATE USING (auth.uid() = "user_id");

CREATE POLICY "Users can delete own highlights" ON highlights
  FOR DELETE USING (auth.uid() = "user_id");

-- RLS Policies for notes
CREATE POLICY "Users can view own notes" ON notes
  FOR SELECT USING (auth.uid() = "user_id");

CREATE POLICY "Users can insert own notes" ON notes
  FOR INSERT WITH CHECK (auth.uid() = "user_id");

CREATE POLICY "Users can update own notes" ON notes
  FOR UPDATE USING (auth.uid() = "user_id");

CREATE POLICY "Users can delete own notes" ON notes
  FOR DELETE USING (auth.uid() = "user_id");

-- RLS Policies for history
CREATE POLICY "Users can view own history" ON history
  FOR SELECT USING (auth.uid() = "user_id");

CREATE POLICY "Users can insert own history" ON history
  FOR INSERT WITH CHECK (auth.uid() = "user_id");

CREATE POLICY "Users can update own history" ON history
  FOR UPDATE USING (auth.uid() = "user_id");

CREATE POLICY "Users can delete own history" ON history
  FOR DELETE USING (auth.uid() = "user_id");

-- RLS Policies for search_history
CREATE POLICY "Users can view own search history" ON search_history
  FOR SELECT USING (auth.uid() = "user_id");

CREATE POLICY "Users can insert own search history" ON search_history
  FOR INSERT WITH CHECK (auth.uid() = "user_id");

CREATE POLICY "Users can update own search history" ON search_history
  FOR UPDATE USING (auth.uid() = "user_id");

CREATE POLICY "Users can delete own search history" ON search_history
  FOR DELETE USING (auth.uid() = "user_id");

-- Performance indexes
CREATE INDEX idx_highlights_user_id ON highlights("user_id");
CREATE INDEX idx_highlights_created_at ON highlights("created_at");
CREATE INDEX idx_highlights_updated_at ON highlights("updated_at");
CREATE INDEX idx_highlights_user_updated ON highlights("user_id", "updated_at");

CREATE INDEX idx_notes_user_id ON notes("user_id");
CREATE INDEX idx_notes_created_at ON notes("created_at");
CREATE INDEX idx_notes_updated_at ON notes("updated_at");
CREATE INDEX idx_notes_user_updated ON notes("user_id", "updated_at");

CREATE INDEX idx_history_user_id ON history("user_id");
CREATE INDEX idx_history_timestamp ON history("timestamp");
CREATE INDEX idx_history_user_timestamp ON history("user_id", "timestamp");

CREATE INDEX idx_search_history_user_id ON search_history("user_id");
CREATE INDEX idx_search_history_timestamp ON search_history("timestamp");
CREATE INDEX idx_search_history_user_timestamp ON search_history("user_id", "timestamp");

-- Additional indexes for sync performance
CREATE INDEX idx_highlights_user_recent ON highlights("user_id", "updated_at" DESC) WHERE "updated_at" > 0;
CREATE INDEX idx_notes_user_recent ON notes("user_id", "updated_at" DESC) WHERE "updated_at" > 0;
CREATE INDEX idx_history_user_recent ON history("user_id", "timestamp" DESC) WHERE "timestamp" > 0;
CREATE INDEX idx_search_history_user_recent ON search_history("user_id", "timestamp" DESC) WHERE "timestamp" > 0;
