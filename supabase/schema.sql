create extension if not exists pgcrypto;

create table if not exists public.courses (
 id uuid primary key default gen_random_uuid(), slug text unique not null, title text not null, created_at timestamptz default now()
);
create table if not exists public.course_modules (
 id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade,
 module_number integer not null, title text not null, unique(course_id,module_number)
);
create table if not exists public.module_completions (
 user_id uuid not null references auth.users(id) on delete cascade,
 module_id uuid not null references public.course_modules(id) on delete cascade,
 completed_at timestamptz not null default now(), primary key(user_id,module_id)
);
create table if not exists public.admin_users (
 user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz default now()
);
create table if not exists public.certificate_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 course_id uuid not null references public.courses(id), learner_name text not null check(char_length(learner_name) between 2 and 100),
 email text not null, college_name text check(college_name is null or char_length(college_name)<=160),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 admin_notes text, created_at timestamptz not null default now(), reviewed_at timestamptz
);
create unique index if not exists one_pending_certificate_request_per_course
on public.certificate_requests(user_id,course_id) where status='pending';
create table if not exists public.certificates (
 id uuid primary key default gen_random_uuid(), request_id uuid not null unique references public.certificate_requests(id) on delete cascade,
 certificate_code text not null unique, issued_at timestamptz not null default now()
);

create or replace function public.is_techbridge_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.admin_users where user_id=auth.uid());
$$;

alter table public.courses enable row level security;
alter table public.course_modules enable row level security;
alter table public.module_completions enable row level security;
alter table public.admin_users enable row level security;
alter table public.certificate_requests enable row level security;
alter table public.certificates enable row level security;

drop policy if exists "Public read courses" on public.courses;
create policy "Public read courses" on public.courses for select using(true);
drop policy if exists "Public read modules" on public.course_modules;
create policy "Public read modules" on public.course_modules for select using(true);
drop policy if exists "Read own completions" on public.module_completions;
create policy "Read own completions" on public.module_completions for select to authenticated using(user_id=auth.uid());
drop policy if exists "Add own completions" on public.module_completions;
create policy "Add own completions" on public.module_completions for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "Remove own completions" on public.module_completions;
create policy "Remove own completions" on public.module_completions for delete to authenticated using(user_id=auth.uid());
drop policy if exists "Read own admin role" on public.admin_users;
create policy "Read own admin role" on public.admin_users for select to authenticated using(user_id=auth.uid());
drop policy if exists "Read own or admin requests" on public.certificate_requests;
create policy "Read own or admin requests" on public.certificate_requests for select to authenticated using(user_id=auth.uid() or public.is_techbridge_admin());
drop policy if exists "Read owned or admin certificates" on public.certificates;
create policy "Read owned or admin certificates" on public.certificates for select to authenticated using(
 public.is_techbridge_admin() or exists(select 1 from public.certificate_requests r where r.id=request_id and r.user_id=auth.uid())
);

create or replace function public.request_techbridge_certificate(p_course_slug text,p_learner_name text,p_college_name text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_course uuid; v_total integer; v_done integer; v_id uuid; v_email text;
begin
 if auth.uid() is null then raise exception 'Sign in before requesting a certificate.'; end if;
 if length(trim(coalesce(p_learner_name,'')))<2 or length(trim(p_learner_name))>100 then raise exception 'Enter a certificate name between 2 and 100 characters.'; end if;
 v_email:=auth.jwt()->>'email';
 if v_email is null then raise exception 'Account email could not be verified.'; end if;
 select id into v_course from public.courses where slug=p_course_slug;
 if v_course is null then raise exception 'Course not found.'; end if;
 select count(*) into v_total from public.course_modules where course_id=v_course;
 select count(*) into v_done from public.module_completions mc join public.course_modules cm on cm.id=mc.module_id where cm.course_id=v_course and mc.user_id=auth.uid();
 if v_total=0 or v_done<>v_total then raise exception 'Complete every listed module before requesting a certificate.'; end if;
 insert into public.certificate_requests(user_id,course_id,learner_name,email,college_name)
 values(auth.uid(),v_course,trim(p_learner_name),v_email,nullif(trim(coalesce(p_college_name,'')),'')) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.review_techbridge_certificate_request(p_request_id uuid,p_approve boolean,p_admin_notes text default null)
returns text language plpgsql security definer set search_path=public as $$
declare v_status text; v_code text;
begin
 if not public.is_techbridge_admin() then raise exception 'Administrator access required.'; end if;
 select status into v_status from public.certificate_requests where id=p_request_id for update;
 if v_status is null then raise exception 'Request not found.'; end if;
 if v_status='approved' then select certificate_code into v_code from public.certificates where request_id=p_request_id; return v_code; end if;
 if v_status<>'pending' then raise exception 'This request has already been reviewed.'; end if;
 update public.certificate_requests set status=case when p_approve then 'approved' else 'rejected' end,
 admin_notes=nullif(left(coalesce(p_admin_notes,''),1000),''),reviewed_at=now() where id=p_request_id;
 if p_approve then
  v_code:='TB-'||to_char(now(),'YYYY')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.certificates(request_id,certificate_code) values(p_request_id,v_code);
  return v_code;
 end if;
 return null;
end; $$;

grant execute on function public.request_techbridge_certificate(text,text,text) to authenticated;
grant execute on function public.review_techbridge_certificate_request(uuid,boolean,text) to authenticated;

insert into public.courses(slug,title) values
('embedded-systems-foundations','Embedded Systems Foundations'),
('introduction-to-iot','Introduction to Internet of Things'),
('arduino-esp32-starter-lab','Arduino & ESP32 Starter Lab'),
('embedded-c-programming-basics','Embedded C Programming Basics'),
('sensors-interfacing-essentials','Sensors and Interfacing Essentials'),
('digital-electronics-refresher','Digital Electronics Refresher')
on conflict(slug) do update set title=excluded.title;

insert into public.course_modules(course_id,module_number,title)
select c.id,m.n,m.t from (values
('embedded-systems-foundations',1,'Introduction to embedded systems'),('embedded-systems-foundations',2,'Processor and controller fundamentals'),('embedded-systems-foundations',3,'Memory and input/output interfaces'),('embedded-systems-foundations',4,'Embedded system design concepts'),('embedded-systems-foundations',5,'Applications and case studies'),
('introduction-to-iot',1,'IoT overview and architecture'),('introduction-to-iot',2,'Sensors and actuators'),('introduction-to-iot',3,'Connectivity and communication'),('introduction-to-iot',4,'IoT platforms and data'),('introduction-to-iot',5,'Applications and challenges'),
('arduino-esp32-starter-lab',1,'Getting to know Arduino and ESP32'),('arduino-esp32-starter-lab',2,'Digital input and output'),('arduino-esp32-starter-lab',3,'Reading sensors'),('arduino-esp32-starter-lab',4,'Serial communication'),('arduino-esp32-starter-lab',5,'Planning a mini project'),
('embedded-c-programming-basics',1,'C language refresher'),('embedded-c-programming-basics',2,'Data types and operators'),('embedded-c-programming-basics',3,'Conditions and loops'),('embedded-c-programming-basics',4,'Functions and arrays'),('embedded-c-programming-basics',5,'Working with hardware concepts'),
('sensors-interfacing-essentials',1,'Sensor fundamentals'),('sensors-interfacing-essentials',2,'Analog and digital signals'),('sensors-interfacing-essentials',3,'Interfacing concepts'),('sensors-interfacing-essentials',4,'Choosing sensors for projects'),
('digital-electronics-refresher',1,'Number systems and codes'),('digital-electronics-refresher',2,'Logic gates'),('digital-electronics-refresher',3,'Boolean algebra'),('digital-electronics-refresher',4,'Combinational circuits'),('digital-electronics-refresher',5,'Sequential logic overview')
) as m(slug,n,t) join public.courses c on c.slug=m.slug
on conflict(course_id,module_number) do update set title=excluded.title;

-- After creating your own account in student.html, run this once using your login email:
-- insert into public.admin_users(user_id) select id from auth.users where email='YOUR_ADMIN_EMAIL' on conflict do nothing;
