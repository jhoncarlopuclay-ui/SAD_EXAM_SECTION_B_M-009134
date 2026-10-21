# ScholarTrack — Section B laboratory activity

The app is connected to the supplied Supabase project URL and publishable key in `app.js`. It now includes email/password sign-in, Scholar self-registration, RLS-backed scholar/program assignment, semester submissions and corrections, evidence verification, program-based evaluation, explicit renewal decisions, and audit history.

## One-time Supabase setup

1. Open the Supabase project SQL Editor and run [`supabase/schema.sql`](supabase/schema.sql) once. It creates the tables, two policy records, constraints, signup profile trigger, audit trigger, and RLS policies. Do not run it a second time as a migration; the examination schema is intended for a fresh project.
2. In Supabase **Authentication → URL Configuration**, add the URL where this app will run to the allowed redirect/site URLs. For a simple local run, use `http://localhost:8000`.
3. Open the app and choose **Create a scholar account** to create the Scholarship Office staff login too. New accounts are always created as `scholar` for safety. Confirm the email if Supabase email confirmation is enabled.
4. In SQL Editor, promote only the staff account, replacing the email:

   ```sql
   update public.profiles
   set role = 'staff'
   where id = (select id from auth.users where email = 'staff@example.com');
   ```

5. Sign in again as staff. Register each synthetic student through **Create a scholar account**. As staff, open **Scholars → Assign scholar** and assign a program to each registered account. A scholar can only submit once their assignment exists.
6. To load the examination's six fixed test cases, run [`supabase/seed_test_records.sql`](supabase/seed_test_records.sql) after B01–B06 have accounts and assignments. It does not overwrite existing semester submissions. Their compliance status begins unevaluated; staff evaluates after verifying evidence.
7. To add CHED CSP, DOST-SEI, TES, LGU, and Private Scholarship options to an existing project, run [`supabase/add_scholarship_programs.sql`](supabase/add_scholarship_programs.sql). Review the default thresholds before using them for a real policy.

The app uses the publishable/anon key in the browser. **Never put a Supabase service-role key or a user's password in source code.** Database RLS enforces ownership and staff access; UI visibility is not the security boundary.

## Run the app

From this folder, run `python -m http.server 8000` and visit `http://localhost:8000`. The page loads Supabase JS from jsDelivr, so browser internet access is needed. Sign in with the account created above. The **Open local demo** button opens a non-secure sample snapshot; it is not an authenticated fallback and changes there are not written to Supabase.

## Role and workflow

- **Scholar:** sign up, sign in, see only own records, submit a summary and evidence reference, see status and history, correct a returned record, then resubmit to Pending.
- **Staff:** see all records under RLS; assign registered scholars to Excellence or Access; verify or return evidence with a reason; evaluate verified records using the program thresholds fetched from Supabase; record Approved or Held with a note; search/filter and export the list.
- **Data history:** database triggers record submissions, verification, correction, evaluations, and renewal decisions with actor, timestamp, and event details.
- **Rules:** GWA boundaries are inclusive; deadline comparisons use timezone-aware persisted program deadlines; compliant status and award decision are separate. The database blocks approval unless compliance is Compliant.

## Included files and known limits

- `index.html`, `styles.css`, `app.js`: browser client and workflows.
- `supabase/schema.sql`: schema, trigger functions, audit log, and RLS.
- `supabase/seed_test_records.sql`: B01–B06 fixture rows after account provisioning.
- `docs/analysis-and-design.md`: A1–A6 analysis baseline, UML, detailed use cases, ERD, traceability, and TC01–TC10 expected results.

This MVP does not connect to Registrar systems, send SMS, process payments, or implement appeals/policy exceptions. The program policy page is read-only; change thresholds in `public.programs` using trusted staff/admin tooling. Browser-to-Supabase execution still needs to be exercised with the provisioned accounts before claiming TC01–TC10 passed. Test accounts should be supplied privately to the instructor.
