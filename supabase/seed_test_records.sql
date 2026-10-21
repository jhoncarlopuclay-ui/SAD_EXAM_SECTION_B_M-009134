-- Run only after the six synthetic users have registered in the app and staff
-- has assigned their programs. student_id values must be B01 through B06.
-- Creates the exam's AY 2026-2027 Semester 1 test submissions.
with test_rows(student_id,academic_year,semester,gwa,units,failed,inc_count,dropped,submitted_at,verification_status) as (
 values
 ('B01','2026-2027',1,2.00,18,0,0,0,'2026-11-06 17:00:00 Asia/Manila'::timestamptz,'Verified'::public.verification_state),
 ('B02','2026-2027',1,2.01,18,0,0,0,'2026-11-05 10:00:00 Asia/Manila'::timestamptz,'Verified'::public.verification_state),
 ('B03','2026-2027',1,2.50,15,0,0,1,'2026-11-05 11:00:00 Asia/Manila'::timestamptz,'Verified'::public.verification_state),
 ('B04','2026-2027',1,2.50,14,0,1,0,'2026-11-05 12:00:00 Asia/Manila'::timestamptz,'Verified'::public.verification_state),
 ('B05','2026-2027',1,1.75,18,1,0,0,'2026-11-06 17:01:00 Asia/Manila'::timestamptz,'Verified'::public.verification_state),
 ('B06','2026-2027',1,2.25,15,0,0,0,'2026-11-05 13:00:00 Asia/Manila'::timestamptz,'Pending'::public.verification_state)
)
insert into public.submissions(scholar_id,program_id,academic_year,semester,gwa,enrolled_units,failed_count,incomplete_count,dropped_count,evidence_reference,submitted_at,verification_status)
select p.id,pr.id,t.academic_year,t.semester,t.gwa,t.units,t.failed,t.inc_count,t.dropped,
       'Synthetic grade reference '||t.student_id,t.submitted_at,t.verification_status
from test_rows t
join public.profiles p on p.student_id=t.student_id and p.role='scholar'
join public.assignments a on a.scholar_id=p.id and a.active
join public.programs pr on pr.id=a.program_id
on conflict(scholar_id,academic_year,semester) do nothing;
