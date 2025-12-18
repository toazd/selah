-- Enable FULL replica identity for all four tables.
-- Without this, delete operations do not include enough
-- information to match the listeners for the app
-- and no one gets the broadcast (only includes the id uuid 
-- which does not match the filters for the listeners)
--
-- filter by user_id:
--
-- filter: PostgresChangeFilter(
--   type: PostgresChangeFilterType.eq,
--   column: 'user_id',
--   value: _currentUserId,
-- ),
--
ALTER TABLE highlights REPLICA IDENTITY FULL;
ALTER TABLE notes REPLICA IDENTITY FULL;
ALTER TABLE history REPLICA IDENTITY FULL;
ALTER TABLE search_history REPLICA IDENTITY FULL;