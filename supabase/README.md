# TechBridge Learning backend setup

The website code stays in this GitHub repository. Vercel runs the /api/config function, while Supabase provides student authentication and the database. The browser receives only the Supabase publishable/anon key. Never expose a Supabase service-role/secret key.

## 1. Create the database
1. Create a Supabase project at https://supabase.com/dashboard.
2. Open SQL Editor.
3. Run the full contents of supabase/schema.sql.

## 2. Configure Vercel
In the Vercel project connected to this repository, open Settings > Environment Variables and add:
- SUPABASE_URL: Project URL from Supabase > Project Settings > API.
- SUPABASE_ANON_KEY: Publishable key (or legacy anon public key) from Supabase > Project Settings > API.

Add the variables to Production (and Preview if needed), then redeploy. Do not add a service-role key. In Supabase Authentication > URL Configuration, set Site URL to your deployed TechBridge domain and add the student portal URL (your-domain/student.html) to Redirect URLs.

## 3. Make your account the only admin
1. Open /student.html on the deployed site.
2. Create your account using your email and a strong password. Confirm your email if requested.
3. In Supabase SQL Editor, replace the email below with the exact email used for that account and run:

    insert into public.admin_users(user_id)
    select id from auth.users where email='YOUR_ADMIN_EMAIL'
    on conflict (user_id) do nothing;

Only users listed in admin_users can use the admin portal. Keep your password private.

## 4. Portals
- /student.html: student registration, module progress and certificate requests.
- /admin.html: admin review and approval/rejection.
- Approval creates a unique TechBridge certificate ID.

Important: the current course catalogue has module outlines, not complete lesson materials or automated assessments. Until the actual lessons and assessments are built, module completion is learner self-attestation and the admin must check it before approval. TechBridge certificates are not NPTEL/SWAYAM certificates.

## Student data
Only the learner's certificate name, account email and optional college name are collected. Publish a privacy notice before inviting students. Never put a service-role/secret key in frontend code.
