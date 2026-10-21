-- PetPal online household foundation.
-- Run this file in the Supabase SQL editor before enabling remote data.

create extension if not exists pgcrypto;

create table if not exists public.households (
  id text primary key,
  name text not null check (char_length(trim(name)) > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.household_members (
  household_id text not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'member' check (role in ('admin', 'member', 'caregiver')),
  status text not null default 'active' check (status in ('active', 'inactive')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table if not exists public.household_invitations (
  id uuid primary key default gen_random_uuid(),
  household_id text not null references public.households(id) on delete cascade,
  email text not null,
  role text not null default 'member' check (role in ('member', 'caregiver')),
  token_hash text not null unique,
  invited_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now()
);

create table if not exists public.pets (
  id text primary key,
  household_id text not null references public.households(id) on delete cascade,
  name text not null,
  species text not null default '',
  breed text not null default '',
  birthday date,
  weight text not null default '',
  notes text not null default '',
  photo text not null default '',
  created_at timestamptz not null default now()
);

-- Safe migration for databases where the original schema was already applied.
alter table public.pets add column if not exists photo text not null default '';

create table if not exists public.tasks (
  id text primary key,
  household_id text not null references public.households(id) on delete cascade,
  pet_id text not null references public.pets(id) on delete cascade,
  title text not null,
  category text not null default 'Other',
  care_notes text not null default '',
  scheduled_time time not null default '00:00',
  scheduled_date date not null default current_date,
  repeats_daily boolean not null default false,
  assigned_to uuid references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.task_completions (
  id text primary key,
  household_id text not null references public.households(id) on delete cascade,
  task_id text not null references public.tasks(id) on delete cascade,
  pet_id text not null references public.pets(id) on delete cascade,
  care_day date not null,
  completed_by uuid not null references auth.users(id) on delete restrict,
  completed_by_name text not null,
  completed_at timestamptz not null default now(),
  unique (task_id, care_day)
);

create table if not exists public.health_records (
  id text primary key,
  household_id text not null references public.households(id) on delete cascade,
  pet_id text not null references public.pets(id) on delete cascade,
  title text not null,
  record_type text not null default 'Other',
  record_date date not null default current_date,
  provider text not null default '',
  notes text not null default '',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.household_updates (
  id text primary key,
  household_id text not null references public.households(id) on delete cascade,
  pet_id text not null references public.pets(id) on delete cascade,
  message text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_by_name text not null,
  created_at timestamptz not null default now()
);

create index if not exists household_members_user_idx
  on public.household_members(user_id);
create index if not exists pets_household_idx
  on public.pets(household_id);
create index if not exists tasks_household_idx
  on public.tasks(household_id);
create index if not exists task_completions_task_day_idx
  on public.task_completions(task_id, care_day);

create or replace function public.is_household_member(target_household_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members
    where household_id = target_household_id
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

create or replace function public.is_household_admin(target_household_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members
    where household_id = target_household_id
      and user_id = auth.uid()
      and role = 'admin'
      and status = 'active'
  );
$$;

-- Create the household and its first admin membership as one trusted operation.
-- Calling two separate client inserts would leave the creator without access
-- because the membership policies are intentionally admin-protected.
create or replace function public.create_household_with_owner(
  household_id text,
  household_name text,
  owner_display_name text
)
returns public.households
language plpgsql
security definer
set search_path = public
as $$
declare
  created_household public.households;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to create a household';
  end if;

  insert into public.households (id, name, created_by)
  values (household_id, trim(household_name), auth.uid())
  returning * into created_household;

  insert into public.household_members
    (household_id, user_id, display_name, role)
  values
    (household_id, auth.uid(), trim(owner_display_name), 'admin');

  return created_household;
end;
$$;

grant execute on function public.create_household_with_owner(text, text, text)
  to authenticated;

create or replace function public.create_household_invitation(
  target_household_id text,
  invited_email text,
  invited_role text default 'member'
)
returns table (invitation_id uuid, invite_token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  token text;
  invitation_expiry timestamptz := now() + interval '7 days';
begin
  if not public.is_household_admin(target_household_id) then
    raise exception 'Only a household admin can invite members';
  end if;
  if lower(trim(invited_email)) = '' then
    raise exception 'An email address is required';
  end if;
  if invited_role not in ('member', 'caregiver') then
    raise exception 'Invalid household role';
  end if;

  token := encode(gen_random_bytes(24), 'hex');
  return query
  insert into public.household_invitations
    (household_id, email, role, token_hash, invited_by, expires_at)
  values
    (
      target_household_id,
      lower(trim(invited_email)),
      invited_role,
      encode(digest(token, 'sha256'), 'hex'),
      auth.uid(),
      invitation_expiry
    )
  returning id, token, invitation_expiry;
end;
$$;

grant execute on function public.create_household_invitation(text, text, text)
  to authenticated;

create or replace function public.accept_household_invitation(
  invitation_token text,
  member_display_name text default ''
)
returns public.households
language plpgsql
security definer
set search_path = public
as $$
declare
  invitation public.household_invitations;
  accepted_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  accepted_name text;
  accepted_household public.households;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to accept an invitation';
  end if;

  select * into invitation
  from public.household_invitations
  where token_hash = encode(digest(trim(invitation_token), 'sha256'), 'hex')
    and status = 'pending'
    and expires_at > now()
  for update;

  if invitation.id is null then
    raise exception 'This invitation is invalid, expired, or already used';
  end if;
  if accepted_email = '' or accepted_email <> lower(invitation.email) then
    raise exception 'Sign in with the email address that received this invitation';
  end if;

  accepted_name := nullif(trim(member_display_name), '');
  if accepted_name is null then
    accepted_name := split_part(accepted_email, '@', 1);
  end if;

  insert into public.household_members
    (household_id, user_id, display_name, role, status)
  values
    (invitation.household_id, auth.uid(), accepted_name, invitation.role, 'active')
  on conflict (household_id, user_id) do update
    set display_name = excluded.display_name,
        role = excluded.role,
        status = 'active';

  update public.household_invitations
  set status = 'accepted'
  where id = invitation.id;

  select * into accepted_household
  from public.households
  where id = invitation.household_id;
  return accepted_household;
end;
$$;

grant execute on function public.accept_household_invitation(text, text)
  to authenticated;

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invitations enable row level security;
alter table public.pets enable row level security;
alter table public.tasks enable row level security;
alter table public.task_completions enable row level security;
alter table public.health_records enable row level security;
alter table public.household_updates enable row level security;

drop policy if exists households_member_select on public.households;
create policy households_member_select on public.households
  for select using (public.is_household_member(id));

drop policy if exists households_admin_insert on public.households;
create policy households_admin_insert on public.households
  for insert with check (created_by = auth.uid());

drop policy if exists households_admin_update on public.households;
create policy households_admin_update on public.households
  for update using (public.is_household_admin(id))
  with check (public.is_household_admin(id));

drop policy if exists household_members_member_select on public.household_members;
create policy household_members_member_select on public.household_members
  for select using (public.is_household_member(household_id));

drop policy if exists household_members_admin_manage on public.household_members;
create policy household_members_admin_manage on public.household_members
  for all using (public.is_household_admin(household_id))
  with check (public.is_household_admin(household_id));

drop policy if exists household_invitations_admin_manage on public.household_invitations;
create policy household_invitations_admin_manage on public.household_invitations
  for all using (public.is_household_admin(household_id))
  with check (public.is_household_admin(household_id));

-- Members can read household data. Writes are limited to members for the
-- prototype; admin-only membership and invitation changes remain protected.
drop policy if exists pets_member_access on public.pets;
create policy pets_member_access on public.pets
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

drop policy if exists tasks_member_access on public.tasks;
create policy tasks_member_access on public.tasks
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

drop policy if exists completions_member_access on public.task_completions;
create policy completions_member_access on public.task_completions
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

drop policy if exists health_records_member_access on public.health_records;
create policy health_records_member_access on public.health_records
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

drop policy if exists updates_member_access on public.household_updates;
create policy updates_member_access on public.household_updates
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
