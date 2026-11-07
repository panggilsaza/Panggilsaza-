-- PANGGILSAZA initial production schema.
-- Run in Supabase SQL Editor. Review RLS policies before inviting real users.
create extension if not exists pgcrypto;

create type public.app_role as enum ('admin','tutor','parent','student');
create type public.class_type as enum ('private','group');
create type public.payment_status as enum ('draft','pending','paid','failed','expired','refunded');
create type public.attendance_status as enum ('scheduled','present','absent','permission','cancelled','make_up');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null,
 role public.app_role not null default 'student',
 phone text,
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.students (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid unique references public.profiles(id),
 full_name text not null,
 grade text,
 program text,
 parent_name text,
 parent_profile_id uuid references public.profiles(id),
 status text not null default 'active',
 created_at timestamptz not null default now()
);
create table public.tutors (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid unique not null references public.profiles(id),
 subjects text[] not null default '{}',
 active boolean not null default true
);
create table public.learning_packages (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 meeting_count int not null check(meeting_count in (4,8,12)),
 duration_minutes int not null check(duration_minutes in (60,90)),
 class_type public.class_type not null,
 price_idr bigint not null check(price_idr >= 0),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(meeting_count,duration_minutes,class_type,name)
);
create table public.enrollments (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id),
 package_id uuid not null references public.learning_packages(id),
 total_meetings int not null check(total_meetings in (4,8,12)),
 remaining_meetings int not null check(remaining_meetings between 0 and total_meetings),
 starts_on date,
 expires_on date,
 status text not null default 'active',
 created_at timestamptz not null default now()
);
create table public.classes (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 class_type public.class_type not null,
 tutor_id uuid references public.tutors(id),
 starts_at timestamptz not null,
 duration_minutes int not null check(duration_minutes in (60,90)),
 capacity int not null default 1 check(capacity > 0),
 status text not null default 'scheduled',
 created_at timestamptz not null default now()
);
create table public.class_students (
 class_id uuid references public.classes(id) on delete cascade,
 student_id uuid references public.students(id) on delete cascade,
 enrollment_id uuid references public.enrollments(id),
 primary key(class_id,student_id)
);
create table public.attendance (
 id uuid primary key default gen_random_uuid(),
 class_id uuid not null references public.classes(id),
 student_id uuid not null references public.students(id),
 status public.attendance_status not null default 'scheduled',
 marked_by uuid references public.profiles(id),
 marked_at timestamptz,
 balance_deducted_at timestamptz,
 unique(class_id,student_id)
);
create table public.invoices (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id),
 enrollment_id uuid references public.enrollments(id),
 amount_idr bigint not null check(amount_idr >= 0),
 status public.payment_status not null default 'pending',
 due_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.payments (
 id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.invoices(id),
 provider text not null check(provider in ('manual','midtrans')),
 provider_reference text unique,
 amount_idr bigint not null check(amount_idr >= 0),
 status public.payment_status not null default 'pending',
 paid_at timestamptz,
 raw_notification jsonb,
 created_at timestamptz not null default now()
);
create table public.worksheets (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 subject text not null,
 grade text,
 content jsonb not null default '{}'::jsonb,
 published boolean not null default false,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now()
);
create table public.worksheet_assignments (
 id uuid primary key default gen_random_uuid(),
 worksheet_id uuid not null references public.worksheets(id),
 student_id uuid not null references public.students(id),
 due_at timestamptz,
 submitted_at timestamptz,
 score numeric(5,2),
 answers jsonb,
 status text not null default 'assigned'
);
create table public.progress_reports (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id),
 tutor_id uuid references public.tutors(id),
 period_start date not null,
 period_end date not null,
 competencies jsonb not null default '{}'::jsonb,
 teacher_remarks text,
 created_at timestamptz not null default now()
);

create or replace function public.current_role()
returns public.app_role language sql stable security definer
set search_path = public
as $$ select role from public.profiles where id = auth.uid() and is_active = true $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$ select coalesce(public.current_role() = 'admin', false) $$;

-- Create profile on signup. Role is always student; admin assigns privileged roles separately.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
 insert into public.profiles(id,full_name,role)
 values(new.id, coalesce(new.raw_user_meta_data->>'full_name','New Student'), 'student');
 return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- RLS enabled on all tables.
do $$ declare t text; begin
 foreach t in array array['profiles','students','tutors','learning_packages','enrollments','classes','class_students','attendance','invoices','payments','worksheets','worksheet_assignments','progress_reports']
 loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

-- Profiles: self read/update only; admins can manage all.
create policy "profiles_read_self_or_admin" on public.profiles for select using (id=auth.uid() or public.is_admin());
create policy "profiles_update_self_or_admin" on public.profiles for update using (id=auth.uid() or public.is_admin()) with check (id=auth.uid() or public.is_admin());

-- Admin full control.
create policy "admin_all_students" on public.students for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_tutors" on public.tutors for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_packages" on public.learning_packages for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_enrollments" on public.enrollments for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_classes" on public.classes for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_class_students" on public.class_students for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_attendance" on public.attendance for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_invoices" on public.invoices for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_payments" on public.payments for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_worksheets" on public.worksheets for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_assignments" on public.worksheet_assignments for all using (public.is_admin()) with check (public.is_admin());
create policy "admin_all_reports" on public.progress_reports for all using (public.is_admin()) with check (public.is_admin());

-- Tutor can see assigned classes and related attendance; finer write policies should be expanded by tutor assignment.
create policy "tutor_read_classes" on public.classes for select using (
 exists(select 1 from public.tutors t where t.id=classes.tutor_id and t.profile_id=auth.uid())
);
create policy "tutor_read_attendance" on public.attendance for select using (
 exists(select 1 from public.classes c join public.tutors t on t.id=c.tutor_id where c.id=attendance.class_id and t.profile_id=auth.uid())
);
create policy "tutor_mark_attendance" on public.attendance for update using (
 exists(select 1 from public.classes c join public.tutors t on t.id=c.tutor_id where c.id=attendance.class_id and t.profile_id=auth.uid())
) with check (
 exists(select 1 from public.classes c join public.tutors t on t.id=c.tutor_id where c.id=attendance.class_id and t.profile_id=auth.uid())
);

-- Students and guardians can read their own student-linked records.
create policy "student_self_read" on public.students for select using (profile_id=auth.uid() or parent_profile_id=auth.uid());
create policy "student_class_read" on public.class_students for select using (
 exists(select 1 from public.students s where s.id=student_id and (s.profile_id=auth.uid() or s.parent_profile_id=auth.uid()))
);
create policy "student_attendance_read" on public.attendance for select using (
 exists(select 1 from public.students s where s.id=student_id and (s.profile_id=auth.uid() or s.parent_profile_id=auth.uid()))
);
create policy "student_invoice_read" on public.invoices for select using (
 exists(select 1 from public.students s where s.id=student_id and (s.profile_id=auth.uid() or s.parent_profile_id=auth.uid()))
);
create policy "student_worksheet_read" on public.worksheet_assignments for select using (
 exists(select 1 from public.students s where s.id=student_id and (s.profile_id=auth.uid() or s.parent_profile_id=auth.uid()))
);
create policy "student_report_read" on public.progress_reports for select using (
 exists(select 1 from public.students s where s.id=student_id and (s.profile_id=auth.uid() or s.parent_profile_id=auth.uid()))
);

-- Package catalog visible to signed-in users.
create policy "signedin_read_active_packages" on public.learning_packages for select using (auth.uid() is not null and active=true);

-- IMPORTANT: Do not expose service role key in browser. Add parent/tutor write policies only after
-- mapping guardian/tutor relationships and testing all role boundaries.


-- PACKAGE BILLING AND RESCHEDULING EXTENSION
create type public.reschedule_status as enum ('pending','approved','rejected','cancelled','completed');

-- A request changes an existing class time; it does not itself deduct a lesson balance.
create table public.reschedule_requests (
 id uuid primary key default gen_random_uuid(),
 class_id uuid not null references public.classes(id),
 requested_by uuid not null references public.profiles(id),
 reason text not null check (char_length(trim(reason)) between 5 and 1000),
 proposed_starts_at timestamptz not null,
 status public.reschedule_status not null default 'pending',
 reviewed_by uuid references public.profiles(id),
 reviewed_at timestamptz,
 review_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (proposed_starts_at > created_at)
);

create table public.reschedule_history (
 id uuid primary key default gen_random_uuid(),
 request_id uuid not null references public.reschedule_requests(id),
 class_id uuid not null references public.classes(id),
 old_starts_at timestamptz not null,
 new_starts_at timestamptz not null,
 changed_by uuid not null references public.profiles(id),
 reason text not null,
 changed_at timestamptz not null default now()
);

create table public.package_price_history (
 id uuid primary key default gen_random_uuid(),
 package_id uuid not null references public.learning_packages(id),
 old_price_idr bigint,
 new_price_idr bigint not null check(new_price_idr >= 0),
 changed_by uuid not null references public.profiles(id),
 changed_at timestamptz not null default now()
);

-- Package catalogue is 12 combinations: 2 class models x 3 meeting counts x 2 durations.
-- Admin supplies the actual price. No invented prices are inserted here.
insert into public.learning_packages(name,meeting_count,duration_minutes,class_type,price_idr,active)
select
  case when ct='private' then 'Privat' else 'Kelompok' end || ' ' || n || ' Pertemuan - ' || mins || ' Menit',
  n, mins, ct::public.class_type, 0, false
from (values ('private'),('group')) as types(ct)
cross join (values (4),(8),(12)) as counts(n)
cross join (values (60),(90)) as durations(mins)
on conflict (meeting_count,duration_minutes,class_type,name) do nothing;

alter table public.reschedule_requests enable row level security;
alter table public.reschedule_history enable row level security;
alter table public.package_price_history enable row level security;

create policy "admin_all_reschedules" on public.reschedule_requests
for all using (public.is_admin()) with check (public.is_admin());

create policy "requester_read_own_reschedules" on public.reschedule_requests
for select using (requested_by=auth.uid());

create policy "requester_create_own_reschedules" on public.reschedule_requests
for insert with check (requested_by=auth.uid());

create policy "admin_read_reschedule_history" on public.reschedule_history
for select using (public.is_admin());

create policy "admin_manage_price_history" on public.package_price_history
for all using (public.is_admin()) with check (public.is_admin());

-- Important production rule:
-- Approval must run through a server-side transaction that locks the class row,
-- checks tutor and group-capacity conflicts, records old/new schedule history,
-- updates classes.starts_at, and changes request status atomically.
-- Attendance balance deduction must be a separate idempotent transaction after
-- attendance is finalized as PRESENT; cancelled/rescheduled classes do not deduct.
