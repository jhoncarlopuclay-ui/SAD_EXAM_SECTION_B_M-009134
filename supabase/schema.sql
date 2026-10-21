-- Run in Supabase SQL editor. Requires Supabase Auth and PostgreSQL.
create extension if not exists pgcrypto;
create type public.app_role as enum ('staff','scholar');
create type public.verification_state as enum ('Pending','Verified','Returned');
create type public.compliance_state as enum ('Compliant','With Deficiency');
create type public.renewal_state as enum ('Approved','Held');
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  student_id text unique,
  full_name text not null,
  role public.app_role not null default 'scholar',
  created_at timestamptz not null default now(),
  constraint scholar_has_student_id check (role='staff' or student_id is not null)
);
create table public.programs (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  max_gwa numeric(3,2) not null check(max_gwa between 1 and 5),
  min_units integer not null check(min_units>=0), max_failed integer not null default 0 check(max_failed>=0),
  max_incomplete integer not null default 0 check(max_incomplete>=0), max_dropped integer not null default 0 check(max_dropped>=0),
  deadline timestamptz not null, active boolean not null default true
);
create table public.assignments (
  id uuid primary key default gen_random_uuid(), scholar_id uuid not null references public.profiles(id),
  program_id uuid not null references public.programs(id), assigned_at timestamptz not null default now(),
  active boolean not null default true, unique(scholar_id,program_id)
);
create unique index assignments_one_active_program on public.assignments(scholar_id) where active;
create table public.submissions (
  id uuid primary key default gen_random_uuid(), scholar_id uuid not null references public.profiles(id),
  program_id uuid not null references public.programs(id), academic_year text not null,
  semester smallint not null check(semester in (1,2)), gwa numeric(3,2) not null check(gwa between 1 and 5),
  enrolled_units integer not null check(enrolled_units>=0), failed_count integer not null check(failed_count>=0),
  incomplete_count integer not null check(incomplete_count>=0), dropped_count integer not null check(dropped_count>=0),
  evidence_reference text not null check(length(trim(evidence_reference))>0), submitted_at timestamptz not null default now(),
  verification_status public.verification_state not null default 'Pending', verification_reason text,
  compliance_status public.compliance_state, compliance_reasons jsonb not null default '[]'::jsonb,
  renewal_decision public.renewal_state, decision_note text, evaluated_at timestamptz, evaluated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(scholar_id,academic_year,semester),
  constraint approval_requires_compliant check(renewal_decision is distinct from 'Approved' or compliance_status='Compliant')
);
create table public.audit_logs (
  id bigint generated always as identity primary key, submission_id uuid not null references public.submissions(id) on delete cascade,
  actor_id uuid not null references public.profiles(id), action text not null,
  details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index submissions_semester_idx on public.submissions(academic_year,semester);
create index submissions_program_idx on public.submissions(program_id);
create index audit_submission_idx on public.audit_logs(submission_id,created_at desc);
insert into public.programs(name,max_gwa,min_units,max_failed,max_incomplete,max_dropped,deadline) values
('Excellence Scholar',2.00,18,0,0,0,'2026-11-06 17:00:00 Asia/Manila'),
('Access Scholar',2.50,15,0,0,1,'2026-11-06 17:00:00 Asia/Manila'),
('CHED Scholarship Program (CSP)',2.50,15,0,0,1,'2026-11-06 17:00:00 Asia/Manila'),
('DOST-SEI Scholarship',2.50,15,0,0,1,'2026-11-06 17:00:00 Asia/Manila'),
('TES (Tertiary Education Subsidy)',3.00,12,0,0,1,'2026-11-06 17:00:00 Asia/Manila'),
('LGU Scholarship',2.75,15,0,0,1,'2026-11-06 17:00:00 Asia/Manila'),
('Private Scholarship',2.75,15,0,0,1,'2026-11-06 17:00:00 Asia/Manila')
on conflict(name) do update set max_gwa=excluded.max_gwa,min_units=excluded.min_units,max_failed=excluded.max_failed,max_incomplete=excluded.max_incomplete,max_dropped=excluded.max_dropped,deadline=excluded.deadline;

create or replace function public.is_staff() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='staff'); $$;
create or replace function public.has_program(p uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.assignments where scholar_id=auth.uid() and program_id=p and active); $$;
create or replace function public.guard_submission_write() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null and session_user in ('postgres','supabase_admin') then return new; end if;
 if not public.is_staff() then
   if tg_op='INSERT' then
     if new.scholar_id<>auth.uid() or not public.has_program(new.program_id) then raise exception 'Scholar may submit only for self and assigned program'; end if;
     new.verification_status:='Pending'; new.compliance_status:=null; new.renewal_decision:=null;
   elsif tg_op='UPDATE' then
     if old.scholar_id<>auth.uid() or old.verification_status<>'Returned' then raise exception 'Only a returned own submission can be corrected'; end if;
     if (new.scholar_id,new.program_id,new.academic_year,new.semester) is distinct from (old.scholar_id,old.program_id,old.academic_year,old.semester) then raise exception 'Submission identity cannot be changed'; end if;
     new.verification_status:='Pending'; new.verification_reason:=null; new.compliance_status:=null; new.compliance_reasons:='[]'; new.renewal_decision:=null;
   end if;
 else
   if tg_op='UPDATE' and old.verification_status='Pending' and new.verification_status not in ('Verified','Returned') then raise exception 'Invalid verification transition'; end if;
   if new.renewal_decision='Approved' and new.compliance_status is distinct from 'Compliant' then raise exception 'Only compliant submissions can be approved'; end if;
 end if;
 new.updated_at:=now(); return new;
end $$;
create trigger submissions_guard before insert or update on public.submissions for each row execute function public.guard_submission_write();
create or replace function public.audit_submission_change() returns trigger language plpgsql security definer set search_path=public as $$
declare event_name text; event_details jsonb:='{}'::jsonb;
begin
 if auth.uid() is null then return new; end if;
 if tg_op='INSERT' then event_name:='Submitted';
 elsif old.verification_status is distinct from new.verification_status then
   event_name:=case when new.verification_status='Returned' then 'Returned' when new.verification_status='Verified' then 'Verified' else 'Corrected and resubmitted' end;
   event_details:=jsonb_build_object('reason',new.verification_reason);
 elsif old.compliance_status is distinct from new.compliance_status then
   event_name:='Evaluated'; event_details:=jsonb_build_object('result',new.compliance_status,'reasons',new.compliance_reasons);
 elsif old.renewal_decision is distinct from new.renewal_decision then
   event_name:=new.renewal_decision::text; event_details:=jsonb_build_object('note',new.decision_note);
 else event_name:='Updated'; end if;
 insert into public.audit_logs(submission_id,actor_id,action,details) values(new.id,auth.uid(),event_name,event_details);
 return new;
end $$;
create trigger submissions_audit after insert or update on public.submissions for each row execute function public.audit_submission_change();
alter table public.profiles enable row level security;
alter table public.programs enable row level security;
alter table public.assignments enable row level security;
alter table public.submissions enable row level security;
alter table public.audit_logs enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_staff());
create policy profiles_staff_write on public.profiles for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy programs_read on public.programs for select to authenticated using(active or public.is_staff());
create policy programs_staff_write on public.programs for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy assignments_read on public.assignments for select to authenticated using(scholar_id=auth.uid() or public.is_staff());
create policy assignments_staff_write on public.assignments for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy submissions_read on public.submissions for select to authenticated using(scholar_id=auth.uid() or public.is_staff());
create policy submissions_scholar_insert on public.submissions for insert to authenticated with check(scholar_id=auth.uid() and public.has_program(program_id));
create policy submissions_scholar_correct on public.submissions for update to authenticated using(scholar_id=auth.uid() and verification_status='Returned') with check(scholar_id=auth.uid());
create policy submissions_staff_update on public.submissions for update to authenticated using(public.is_staff()) with check(public.is_staff());
create policy audit_read on public.audit_logs for select to authenticated using(public.is_staff() or exists(select 1 from public.submissions s where s.id=submission_id and s.scholar_id=auth.uid()));
create policy audit_insert on public.audit_logs for insert to authenticated with check(actor_id=auth.uid() and (public.is_staff() or exists(select 1 from public.submissions s where s.id=submission_id and s.scholar_id=auth.uid())));

-- Create Scholar profiles automatically after email sign-up. Role is always scholar;
-- staff privilege must be granted manually by a trusted project owner.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,student_id,full_name,role)
 values(new.id,nullif(trim(new.raw_user_meta_data->>'student_id'),''),coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1)),'scholar');
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Optional: use this after registering the staff account and scholar accounts.
-- update public.profiles set role='staff' where id=(select id from auth.users where email='staff@example.com');
-- Never expose service-role credentials in a browser client.
