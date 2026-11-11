-- Account-owned PetPal data. This version intentionally does not include
-- household invitations or cross-account sharing.

create table if not exists public.petpal_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.petpal_accounts enable row level security;

drop policy if exists petpal_accounts_owner_access on public.petpal_accounts;
create policy petpal_accounts_owner_access
  on public.petpal_accounts
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update on public.petpal_accounts to authenticated;
