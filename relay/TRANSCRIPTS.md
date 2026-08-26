# Automated reply — sample transcripts

**Generated file — do not edit by hand.** Run `npm run transcripts` after
changing `src/config.js`; every line below is produced by running the real
state machine in `src/intake.js`, so it cannot drift from what actually gets
sent.

The language question comes first and on its own. Every message after it is in
whichever language the person chose.

## Path A — no immediate danger, anxiety, in Bali

The ordinary case. Language first, then everything in Indonesian.

**Them:** Halo

**BISA:**

> Halo, terima kasih sudah menghubungi BISA. / Hi, thanks for reaching out to BISA.
>
> Bahasa apa yang paling nyaman untukmu?
> Which language are you most comfortable in?
>
> 1 — Bahasa Indonesia
> 2 — English

**Them:** 1

**BISA:**

> Halo Kadek, terima kasih sudah menghubungi BISA. Pesanmu sudah kami terima.
>
> • Kami hadir 24 jam, setiap hari.
> • Relawan biasanya membalas dalam 1–2 hari. Permintaan sesi bisa masuk daftar tunggu.
> • BISA memberikan dukungan emosional — kami bukan layanan darurat.
>
> Kalau ada bahaya langsung terhadap keselamatanmu atau orang lain, jangan menunggu balasan kami:
> • Telepon 119, atau langsung ke IGD rumah sakit terdekat
>
> Sambil menunggu, ada beberapa hal yang mungkin membantu: https://bisahelpline.org/resources/

**BISA:**

> Boleh kami tanya beberapa hal singkat, supaya bisa mengarahkanmu dengan tepat?
>
> Apakah kamu saat ini dalam bahaya langsung?
>
> Balas dengan angka:
> 1 — Ya
> 2 — Tidak
> 3 — Tidak yakin

**Them:** 2

**BISA:**

> Kamu sedang berada di kota atau kabupaten mana? (misalnya: Denpasar, Gianyar, Buleleng)

**Them:** Denpasar

**BISA:**

> Dukungan seperti apa yang kamu butuhkan hari ini?
>
> 1 — Seseorang untuk diajak bicara
> 2 — Cemas atau panik
> 3 — Kecanduan
> 4 — Menyakiti diri sendiri atau pikiran untuk bunuh diri
> 5 — Rujukan ke bantuan profesional
> 6 — Lainnya

**Them:** 2

**BISA:**

> Terima kasih. Permintaanmu sudah masuk dan akan ditinjau oleh relawan kami.
>
> Kalau panik datang, ini kadang membantu:
> • Tarik napas 4 hitungan, tahan 4, hembuskan 6. Ulangi lima kali.
> • Sebutkan dalam hati 5 hal yang kamu lihat, 4 yang bisa kamu sentuh, 3 yang kamu dengar, 2 yang kamu cium, 1 yang kamu rasakan.
> • Pegang sesuatu yang dingin — segelas air, keran, atau kipas angin.
>
> Panik terasa menakutkan, tapi biasanya memuncak lalu mereda sendiri dalam beberapa menit.
>
> Untuk bantuan profesional di Bali, direktori layanan kami ada di sini: https://bisahelpline.org/services/
>
> Kamu tidak harus menghadapi ini sendirian. Seorang relawan akan meninjau permintaanmu.
>
> Yang bisa kamu harapkan dari BISA: relawan terlatih yang mendengarkan tanpa menghakimi, dalam Bahasa Indonesia atau Inggris. Kami tidak memberi diagnosis atau resep, dan kami bukan layanan darurat — tapi kami bisa membantumu mencari rujukan kalau kamu membutuhkannya.

**Into Kunang** (never sent over WhatsApp):

```
[Intake] Priority: High Priority — danger: no — city: Denpasar (Bali) — language: id — need: anxiety/panic
```

**Priority:** High Priority

---

## Path B — English speaker, referral, outside Bali

Choosing English at Q1 switches every later message, including the out-of-Bali referral.

**Them:** Hello

**BISA:**

> Halo, terima kasih sudah menghubungi BISA. / Hi, thanks for reaching out to BISA.
>
> Bahasa apa yang paling nyaman untukmu?
> Which language are you most comfortable in?
>
> 1 — Bahasa Indonesia
> 2 — English

**Them:** 2

**BISA:**

> Hi Sarah, thanks for reaching out to BISA. We've received your message.
>
> • We're here 24 hours a day, every day.
> • A volunteer usually replies within 1–2 days. Support sessions may be placed on a waiting list.
> • BISA offers emotional support — we are not an emergency service.
>
> If you or someone else is in immediate danger, please don't wait for us:
> • Call 119, or go to the nearest hospital emergency department (IGD)
>
> While you wait, some things that might help: https://bisahelpline.org/resources/

**BISA:**

> May we ask a few short questions, so we can point you to the right support?
>
> Are you currently in immediate danger?
>
> Reply with a number:
> 1 — Yes
> 2 — No
> 3 — Not sure

**Them:** 2

**BISA:**

> Which city or regency are you in right now? (for example: Denpasar, Gianyar, Buleleng)

**Them:** Surabaya

**BISA:**

> What support do you need today?
>
> 1 — Someone to talk to
> 2 — Anxiety or panic
> 3 — Addiction
> 4 — Self-harm or suicidal thoughts
> 5 — Referral to professional help
> 6 — Other

**Them:** 5

**BISA:**

> Thank you. Your request is in, and one of our volunteers will review it.
>
> Since you're outside Bali we can't meet in person — but there is help closer to you. Puskesmas and public hospitals have mental health services, and a directory by city is here: https://www.intothelightid.org/tentang-bunuh-diri/daftar-penyedia-layanan-kesehatan-mental/
>
> You do not have to deal with this alone. A volunteer will review your request.
>
> What to expect from BISA: a trained volunteer who listens without judging, in Indonesian or English. We don't diagnose or prescribe, and we're not an emergency service — but we can help you find a referral if you need one.

**Into Kunang** (never sent over WhatsApp):

```
[Intake] Priority: Referral Required — danger: no — city: Surabaya (outside Bali) — language: en — need: referral to professional help
```

**Priority:** Referral Required

---

## Path C — immediate danger

Answering yes stops the intake. No city question, no need question, no queue form.

**Them:** Halo

**BISA:**

> Halo, terima kasih sudah menghubungi BISA. / Hi, thanks for reaching out to BISA.
>
> Bahasa apa yang paling nyaman untukmu?
> Which language are you most comfortable in?
>
> 1 — Bahasa Indonesia
> 2 — English

**Them:** 1

**BISA:**

> Halo Wayan, terima kasih sudah menghubungi BISA. Pesanmu sudah kami terima.
>
> • Kami hadir 24 jam, setiap hari.
> • Relawan biasanya membalas dalam 1–2 hari. Permintaan sesi bisa masuk daftar tunggu.
> • BISA memberikan dukungan emosional — kami bukan layanan darurat.
>
> Kalau ada bahaya langsung terhadap keselamatanmu atau orang lain, jangan menunggu balasan kami:
> • Telepon 119, atau langsung ke IGD rumah sakit terdekat
>
> Sambil menunggu, ada beberapa hal yang mungkin membantu: https://bisahelpline.org/resources/

**BISA:**

> Boleh kami tanya beberapa hal singkat, supaya bisa mengarahkanmu dengan tepat?
>
> Apakah kamu saat ini dalam bahaya langsung?
>
> Balas dengan angka:
> 1 — Ya
> 2 — Tidak
> 3 — Tidak yakin

**Them:** 1

**BISA:**

> Terima kasih sudah memberi tahu kami. Keselamatanmu yang paling penting sekarang, jadi kami berhenti dengan pertanyaannya.
>
> Tolong hubungi salah satu ini sekarang — semuanya buka 24 jam:
>
> • 119 (ambulans / gawat darurat), atau langsung ke IGD rumah sakit terdekat
>
> Kalau bisa, minta seseorang yang kamu percaya untuk menemanimu sekarang. Kalau ada obat atau benda yang bisa melukaimu di dekatmu, coba titipkan dulu ke orang lain.
>
> Kamu tidak sendirian. Pesanmu sudah kami tandai sebagai prioritas tertinggi, dan relawan kami akan melihatnya.

**Into Kunang** (never sent over WhatsApp):

```
[Intake] Priority: Crisis — danger: yes — language: id — triggered by: answered yes to immediate danger
```

**Priority:** Crisis

---

## Path D — crisis language before the language question

The safety net runs before every step, including Q1. Someone opening with distress is never asked to pick from a menu first — the language is detected from their words instead.

**Them:** aku ingin mati saja

**BISA:**

> Terima kasih sudah memberi tahu kami. Keselamatanmu yang paling penting sekarang, jadi kami berhenti dengan pertanyaannya.
>
> Tolong hubungi salah satu ini sekarang — semuanya buka 24 jam:
>
> • 119 (ambulans / gawat darurat), atau langsung ke IGD rumah sakit terdekat
>
> Kalau bisa, minta seseorang yang kamu percaya untuk menemanimu sekarang. Kalau ada obat atau benda yang bisa melukaimu di dekatmu, coba titipkan dulu ke orang lain.
>
> Kamu tidak sendirian. Pesanmu sudah kami tandai sebagai prioritas tertinggi, dan relawan kami akan melihatnya.

**Into Kunang** (never sent over WhatsApp):

```
[Intake] Priority: Crisis — danger: unknown — triggered by: crisis language
```

**Priority:** Crisis

---

## Path E — self-harm need, but not in immediate danger

Not an emergency, so intake continues — but the safety-plan starter goes out anyway.

**Them:** Halo

**BISA:**

> Halo, terima kasih sudah menghubungi BISA. / Hi, thanks for reaching out to BISA.
>
> Bahasa apa yang paling nyaman untukmu?
> Which language are you most comfortable in?
>
> 1 — Bahasa Indonesia
> 2 — English

**Them:** 1

**BISA:**

> Halo Putu, terima kasih sudah menghubungi BISA. Pesanmu sudah kami terima.
>
> • Kami hadir 24 jam, setiap hari.
> • Relawan biasanya membalas dalam 1–2 hari. Permintaan sesi bisa masuk daftar tunggu.
> • BISA memberikan dukungan emosional — kami bukan layanan darurat.
>
> Kalau ada bahaya langsung terhadap keselamatanmu atau orang lain, jangan menunggu balasan kami:
> • Telepon 119, atau langsung ke IGD rumah sakit terdekat
>
> Sambil menunggu, ada beberapa hal yang mungkin membantu: https://bisahelpline.org/resources/

**BISA:**

> Boleh kami tanya beberapa hal singkat, supaya bisa mengarahkanmu dengan tepat?
>
> Apakah kamu saat ini dalam bahaya langsung?
>
> Balas dengan angka:
> 1 — Ya
> 2 — Tidak
> 3 — Tidak yakin

**Them:** 2

**BISA:**

> Kamu sedang berada di kota atau kabupaten mana? (misalnya: Denpasar, Gianyar, Buleleng)

**Them:** Ubud

**BISA:**

> Dukungan seperti apa yang kamu butuhkan hari ini?
>
> 1 — Seseorang untuk diajak bicara
> 2 — Cemas atau panik
> 3 — Kecanduan
> 4 — Menyakiti diri sendiri atau pikiran untuk bunuh diri
> 5 — Rujukan ke bantuan profesional
> 6 — Lainnya

**Them:** 4

**BISA:**

> Sambil menunggu, mungkin membantu untuk menuliskan tiga hal di HP-mu:
> • 3 tanda kamu mulai merasa tidak aman
> • 2 hal yang pernah menolongmu melewatinya
> • 1 orang yang bisa kamu hubungi kapan saja

**BISA:**

> Terima kasih. Permintaanmu sudah masuk dan akan ditinjau oleh relawan kami.
>
> Sambil menunggu, mungkin membantu untuk menuliskan tiga hal di HP-mu:
> • 3 tanda kamu mulai merasa tidak aman
> • 2 hal yang pernah menolongmu melewatinya
> • 1 orang yang bisa kamu hubungi kapan saja
>
> Untuk bantuan profesional di Bali, direktori layanan kami ada di sini: https://bisahelpline.org/services/
>
> Kamu tidak harus menghadapi ini sendirian. Seorang relawan akan meninjau permintaanmu.
>
> Yang bisa kamu harapkan dari BISA: relawan terlatih yang mendengarkan tanpa menghakimi, dalam Bahasa Indonesia atau Inggris. Kami tidak memberi diagnosis atau resep, dan kami bukan layanan darurat — tapi kami bisa membantumu mencari rujukan kalau kamu membutuhkannya.

**Into Kunang** (never sent over WhatsApp):

```
[Intake] Priority: Crisis — danger: no — city: Ubud (Bali) — language: id — need: self-harm or suicidal thoughts
```

**Priority:** Crisis

---

## Path F — an answer we could not read

Anything unparseable re-asks rather than guessing. At Q1 the re-ask is bilingual too.

**Them:** Halo

**BISA:**

> Halo, terima kasih sudah menghubungi BISA. / Hi, thanks for reaching out to BISA.
>
> Bahasa apa yang paling nyaman untukmu?
> Which language are you most comfortable in?
>
> 1 — Bahasa Indonesia
> 2 — English

**Them:** apa ya

**BISA:**

> Balas dengan angka saja, ya — 1 atau 2. / Please reply with just the number — 1 or 2.

**BISA:**

> Halo, terima kasih sudah menghubungi BISA. / Hi, thanks for reaching out to BISA.
>
> Bahasa apa yang paling nyaman untukmu?
> Which language are you most comfortable in?
>
> 1 — Bahasa Indonesia
> 2 — English

**Them:** 1

**BISA:**

> Halo, terima kasih sudah menghubungi BISA. Pesanmu sudah kami terima.
>
> • Kami hadir 24 jam, setiap hari.
> • Relawan biasanya membalas dalam 1–2 hari. Permintaan sesi bisa masuk daftar tunggu.
> • BISA memberikan dukungan emosional — kami bukan layanan darurat.
>
> Kalau ada bahaya langsung terhadap keselamatanmu atau orang lain, jangan menunggu balasan kami:
> • Telepon 119, atau langsung ke IGD rumah sakit terdekat
>
> Sambil menunggu, ada beberapa hal yang mungkin membantu: https://bisahelpline.org/resources/

**BISA:**

> Boleh kami tanya beberapa hal singkat, supaya bisa mengarahkanmu dengan tepat?
>
> Apakah kamu saat ini dalam bahaya langsung?
>
> Balas dengan angka:
> 1 — Ya
> 2 — Tidak
> 3 — Tidak yakin

**Them:** hmm gimana

**BISA:**

> Maaf, kami belum menangkap jawabannya. Balas dengan angka saja, ya.

**BISA:**

> Boleh kami tanya beberapa hal singkat, supaya bisa mengarahkanmu dengan tepat?
>
> Apakah kamu saat ini dalam bahaya langsung?
>
> Balas dengan angka:
> 1 — Ya
> 2 — Tidak
> 3 — Tidak yakin

