-- Zemi : schéma initial (PostgreSQL + PostGIS, Supabase)
-- Prix en FCFA (XOF), entiers. Coordonnées WGS84.

create extension if not exists postgis;

create type user_role as enum ('client', 'driver');
create type ride_status as enum ('requested', 'assigned', 'in_progress', 'completed', 'cancelled');

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  role user_role not null,
  full_name text not null,
  phone text not null,
  created_at timestamptz not null default now()
);

create table drivers (
  id uuid primary key references profiles on delete cascade,
  plate text not null,
  is_online boolean not null default false,
  is_busy boolean not null default false,
  location geography(Point, 4326),
  location_updated_at timestamptz,
  base_fare integer not null default 200 check (base_fare >= 0),
  price_per_km integer not null default 100 check (price_per_km >= 0)
);
create index drivers_location_idx on drivers using gist (location);

create table rides (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references profiles,
  driver_id uuid references drivers,
  pickup geography(Point, 4326) not null,
  dropoff geography(Point, 4326) not null,
  pickup_label text,
  dropoff_label text,
  distance_km numeric(6, 2) not null,
  offered_price integer not null check (offered_price > 0),
  agreed_price integer,
  status ride_status not null default 'requested',
  created_at timestamptz not null default now()
);
create index rides_pickup_idx on rides using gist (pickup);
create index rides_status_idx on rides (status, created_at);

create table ride_offers (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references rides on delete cascade,
  driver_id uuid not null references drivers,
  price integer not null check (price > 0),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  unique (ride_id, driver_id)
);

-- Sécurité (RLS) -------------------------------------------------------------

alter table profiles enable row level security;
alter table drivers enable row level security;
alter table rides enable row level security;
alter table ride_offers enable row level security;

-- Un utilisateur voit son profil et celui de l'autre partie d'une course commune.
create policy profiles_select on profiles for select using (
  id = auth.uid()
  or exists (
    select 1 from rides r
    where (r.client_id = auth.uid() and r.driver_id = profiles.id)
       or (r.driver_id = auth.uid() and r.client_id = profiles.id)
  )
);
create policy profiles_insert on profiles for insert with check (id = auth.uid());
create policy profiles_update on profiles for update using (id = auth.uid());

-- Les clients obtiennent les conducteurs proches via nearby_drivers() uniquement.
create policy drivers_select on drivers for select using (
  id = auth.uid()
  or exists (select 1 from rides r where r.driver_id = drivers.id and r.client_id = auth.uid())
);
create policy drivers_insert on drivers for insert with check (id = auth.uid());
create policy drivers_update on drivers for update using (id = auth.uid());

create policy rides_select on rides for select using (client_id = auth.uid() or driver_id = auth.uid());
create policy rides_insert on rides for insert with check (client_id = auth.uid() and status = 'requested');
-- Les changements d'état passent par les fonctions ci-dessous (security definer).

create policy offers_select on ride_offers for select using (
  driver_id = auth.uid()
  or exists (select 1 from rides r where r.id = ride_offers.ride_id and r.client_id = auth.uid())
);

-- Fonctions ------------------------------------------------------------------

-- Conducteurs libres autour d'un point (rayon par défaut : 1 km).
create or replace function nearby_drivers(p_lat double precision, p_lng double precision, p_radius_m integer default 1000)
returns table (
  driver_id uuid, full_name text, plate text,
  lat double precision, lng double precision, distance_m double precision,
  base_fare integer, price_per_km integer
)
language sql security definer set search_path = public as $$
  select d.id, p.full_name, d.plate,
         st_y(d.location::geometry), st_x(d.location::geometry),
         st_distance(d.location, st_point(p_lng, p_lat)::geography),
         d.base_fare, d.price_per_km
  from drivers d
  join profiles p on p.id = d.id
  where auth.uid() is not null
    and d.is_online and not d.is_busy
    and d.location_updated_at > now() - interval '2 minutes'
    and st_dwithin(d.location, st_point(p_lng, p_lat)::geography, least(p_radius_m, 5000))
  order by 6
  limit 30;
$$;

-- Demandes ouvertes autour du conducteur connecté.
create or replace function open_rides_near(p_radius_m integer default 1500)
returns table (
  ride_id uuid, client_name text, pickup_label text, dropoff_label text,
  pickup_lat double precision, pickup_lng double precision,
  dropoff_lat double precision, dropoff_lng double precision,
  distance_km numeric, offered_price integer, distance_m double precision,
  my_offer_price integer
)
language sql security definer set search_path = public as $$
  select r.id, p.full_name, r.pickup_label, r.dropoff_label,
         st_y(r.pickup::geometry), st_x(r.pickup::geometry),
         st_y(r.dropoff::geometry), st_x(r.dropoff::geometry),
         r.distance_km, r.offered_price,
         st_distance(r.pickup, d.location),
         (select o.price from ride_offers o where o.ride_id = r.id and o.driver_id = d.id)
  from drivers d
  join rides r on r.status = 'requested' and r.created_at > now() - interval '15 minutes'
  join profiles p on p.id = r.client_id
  where d.id = auth.uid() and d.is_online and not d.is_busy and d.location is not null
    and st_dwithin(r.pickup, d.location, least(p_radius_m, 5000))
  order by 11
  limit 20;
$$;

-- Contre-propositions reçues pour une course du client connecté.
create or replace function ride_offers_for_client(p_ride_id uuid)
returns table (offer_id uuid, price integer, driver_name text, plate text)
language sql security definer set search_path = public as $$
  select o.id, o.price, p.full_name, d.plate
  from ride_offers o
  join rides r on r.id = o.ride_id
  join drivers d on d.id = o.driver_id
  join profiles p on p.id = o.driver_id
  where o.ride_id = p_ride_id and r.client_id = auth.uid() and o.status = 'pending'
  order by o.price;
$$;

create or replace function _assign_ride(p_ride uuid, p_driver uuid, p_price integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  update rides set driver_id = p_driver, agreed_price = p_price, status = 'assigned'
  where id = p_ride and status = 'requested';
  if not found then
    raise exception 'ride_unavailable';
  end if;
  update drivers set is_busy = true where id = p_driver;
  update ride_offers set status = case when driver_id = p_driver then 'accepted' else 'rejected' end
  where ride_id = p_ride;
end $$;

-- Le conducteur accepte le prix du client (attribution immédiate) ou contre-propose.
create or replace function make_offer(p_ride_id uuid, p_price integer)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_ride rides;
begin
  if p_price is null or p_price <= 0 then raise exception 'invalid_price'; end if;
  if not exists (select 1 from drivers where id = auth.uid() and is_online and not is_busy) then
    raise exception 'driver_unavailable';
  end if;
  select * into v_ride from rides where id = p_ride_id and status = 'requested' for update;
  if not found then raise exception 'ride_unavailable'; end if;

  if p_price = v_ride.offered_price then
    perform _assign_ride(p_ride_id, auth.uid(), p_price);
    return 'assigned';
  end if;

  insert into ride_offers (ride_id, driver_id, price) values (p_ride_id, auth.uid(), p_price)
  on conflict (ride_id, driver_id) do update set price = excluded.price, status = 'pending';
  return 'pending';
end $$;

-- Le client choisit une contre-proposition.
create or replace function accept_offer(p_offer_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_offer ride_offers;
begin
  select o.* into v_offer from ride_offers o
  join rides r on r.id = o.ride_id
  where o.id = p_offer_id and r.client_id = auth.uid() and r.status = 'requested' and o.status = 'pending';
  if not found then raise exception 'offer_unavailable'; end if;
  if not exists (select 1 from drivers where id = v_offer.driver_id and not is_busy) then
    raise exception 'driver_unavailable';
  end if;
  perform _assign_ride(v_offer.ride_id, v_offer.driver_id, v_offer.price);
end $$;

create or replace function start_ride(p_ride_id uuid)
returns void language sql security definer set search_path = public as $$
  update rides set status = 'in_progress'
  where id = p_ride_id and driver_id = auth.uid() and status = 'assigned';
$$;

create or replace function complete_ride(p_ride_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update rides set status = 'completed'
  where id = p_ride_id and driver_id = auth.uid() and status = 'in_progress';
  if found then update drivers set is_busy = false where id = auth.uid(); end if;
end $$;

-- Annulation par le client (avant le départ) ou par le conducteur assigné.
create or replace function cancel_ride(p_ride_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_driver uuid;
begin
  update rides set status = 'cancelled'
  where id = p_ride_id
    and ((client_id = auth.uid() and status in ('requested', 'assigned'))
      or (driver_id = auth.uid() and status = 'assigned'))
  returning driver_id into v_driver;
  if found and v_driver is not null then
    update drivers set is_busy = false where id = v_driver;
  end if;
end $$;

grant execute on function nearby_drivers, open_rides_near, ride_offers_for_client, make_offer, accept_offer,
  start_ride, complete_ride, cancel_ride to authenticated;
revoke execute on function _assign_ride from public, anon, authenticated;

-- Temps réel pour le suivi des courses et des offres.
alter publication supabase_realtime add table rides, ride_offers;
