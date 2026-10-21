-- Run this in Supabase SQL Editor to add the scholarship programs to an
-- existing ScholarTrack database. Adjust these default thresholds if your
-- school has different official requirements.
insert into public.programs
  (name, max_gwa, min_units, max_failed, max_incomplete, max_dropped, deadline, active)
values
  ('CHED Scholarship Program (CSP)', 2.50, 15, 0, 0, 1, '2026-11-06 17:00:00 Asia/Manila', true),
  ('DOST-SEI Scholarship', 2.50, 15, 0, 0, 1, '2026-11-06 17:00:00 Asia/Manila', true),
  ('TES (Tertiary Education Subsidy)', 3.00, 12, 0, 0, 1, '2026-11-06 17:00:00 Asia/Manila', true),
  ('LGU Scholarship', 2.75, 15, 0, 0, 1, '2026-11-06 17:00:00 Asia/Manila', true),
  ('Private Scholarship', 2.75, 15, 0, 0, 1, '2026-11-06 17:00:00 Asia/Manila', true)
on conflict (name) do update set
  max_gwa = excluded.max_gwa,
  min_units = excluded.min_units,
  max_failed = excluded.max_failed,
  max_incomplete = excluded.max_incomplete,
  max_dropped = excluded.max_dropped,
  deadline = excluded.deadline,
  active = true;

select name, max_gwa, min_units, max_failed, max_incomplete, max_dropped, deadline
from public.programs
where active = true
order by name;
