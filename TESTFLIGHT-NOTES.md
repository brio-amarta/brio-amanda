# Kunang — TestFlight "What to Test"

Paste the block below into App Store Connect → TestFlight → Build → What to Test.
(Field limit is 4000 characters; this is ~2,400.)

---

First TestFlight build of Kunang. Best on iPad — iPhone works but the app is
built for the larger layout. Requires iOS 26.

SETUP (nothing works until you do this)

1. Open Handlers and add at least one person. The app will not schedule anyone
   until a handler exists.
2. Open Upload, choose the sample CSV, tap "Triage & build schedule".

Please use the sample data only. Do not import real client information.

WHAT I MOST NEED CHECKED

1. Import → triage → schedule, end to end. Does every row from the sheet come
   through, and does each person land in a sensible category?

2. Triage with Apple Intelligence OFF. Settings → Apple Intelligence, turn it
   off, then re-import. Import should still work using score-based rules
   instead of the model. This fallback path matters and is easy to break.

3. Anyone whose location is outside Bali should always end up in "Referral
   Required", even if their score looks urgent. Try a few non-Bali cities.

4. Scheduling limits. Settings → change opening hours, session length, break
   and slots per day. The slot preview should update as you type, and you
   should get a warning when you ask for more sessions than a day can hold.
   Changing settings should NOT move anyone already booked — only "Rebuild
   schedule" does that.

5. Calendar, Day and Week. Sessions drawn at the right time and height,
   overlapping ones sharing the column, red now-line on today. Tap a block and
   confirm it opens the right client.

6. Demo chat. Open a client with no history — the composer should pre-fill with
   a draft opener. Send it, wait a few seconds for the reply, tap the sparkle
   to redraft. Everything here is fiction generated on device.

7. Client states. Mark a session completed and confirm the finish time stamps
   and the block dims with a tick.

8. Messy spreadsheets. Indonesian headers (nama, usia, kota, skor, catatan),
   missing columns, blank rows, quoted commas, extra columns you invented.
   Nothing should crash or silently drop a person.

PLEASE LEAVE ALONE

Settings → Messaging → "Relay server" and the Live chat tab. Those send real
WhatsApp messages to real phone numbers. Stay on the Demo tab.

ALREADY KNOWN — no need to report

- No push notifications; inbound messages poll every few seconds
- Session links are placeholders and go nowhere
- Sample data is invented

REPORTING

Screenshot plus what you tapped just before. Device model and iOS version help.
Crashes are the top priority, then anything that loses or misfiles a person.
