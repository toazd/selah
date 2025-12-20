-- Create a function to get user email by username that bypasses RLS
CREATE OR REPLACE FUNCTION public.get_user_email_by_username(username_param text)
RETURNS TABLE (
  email text
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT 
    au.email
  FROM profiles p
  JOIN auth.users au ON p.id = au.id
  WHERE p.username = username_param
  LIMIT 1;
$$;

-- Grant execute permission to anonymous and authenticated users
GRANT EXECUTE ON FUNCTION public.get_user_email_by_username(text) TO anon, authenticated;
