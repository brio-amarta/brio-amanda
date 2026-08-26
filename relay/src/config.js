// Everything BISA-specific lives here: hours, response time, resources, and
// every word the automated replies say. Edit this file to change wording —
// the flow logic in intake.js never needs to move.
//
// ── Resource accuracy ────────────────────────────────────────────────────
// The numbers below were checked against Into The Light Indonesia's hotline
// registry (last edited 3 April 2023) and bisahelpline.org (2026). Two things
// that are commonly got wrong and are deliberately NOT used here:
//
//   • 112 and 110 do not handle suicide prevention. 110 is police, 112 is
//     disaster reporting. Into The Light says so explicitly.
//   • 119 ext 8 (SEJIWA) is general psychological counselling and does NOT
//     cover suicide first aid. Plain 119, or the nearest IGD, is the right
//     number for immediate danger.
//
// Re-verify these before every deployment. A dead crisis number is worse
// than no number.

export const ORG = {
  name: 'BISA',
  hours: { id: '24 jam, setiap hari', en: '24 hours a day, every day' },
  responseTime: {
    id: 'Relawan biasanya membalas dalam 1–2 hari. Permintaan sesi bisa masuk daftar tunggu.',
    en: 'A volunteer usually replies within 1–2 days. Support sessions may be placed on a waiting list.',
  },
  resourcesURL: 'https://bisahelpline.org/resources/',
  servicesURL: 'https://bisahelpline.org/services/',
}

export const EMERGENCY = {
  // LISA Suicide Prevention Helpline — Bali Bersama Bisa collective, 24h.
  lisa: { id: '+62 811 3855 472', en: '+62 811 3815 472' },
  ambulance: '119',
}

// ─────────────────────────────────────────────────────────────────────────
// Step 3 — Automated Reply. Sets expectations before anyone enters a queue.
// ─────────────────────────────────────────────────────────────────────────

export const GREETING = {
  id: (name) =>
    `Halo${name ? ' ' + name : ''}, terima kasih sudah menghubungi ${ORG.name}. Pesanmu sudah kami terima.

• Kami hadir ${ORG.hours.id}.
• ${ORG.responseTime.id}
• ${ORG.name} memberikan dukungan emosional — kami bukan layanan darurat.

Kalau ada bahaya langsung terhadap keselamatanmu atau orang lain, jangan menunggu balasan kami:
• Telepon ${EMERGENCY.ambulance}, atau langsung ke IGD rumah sakit terdekat

Sambil menunggu, ada beberapa hal yang mungkin membantu: ${ORG.resourcesURL}`,

  en: (name) =>
    `Hi${name ? ' ' + name : ''}, thanks for reaching out to ${ORG.name}. We've received your message.

• We're here ${ORG.hours.en}.
• ${ORG.responseTime.en}
• ${ORG.name} offers emotional support — we are not an emergency service.

If you or someone else is in immediate danger, please don't wait for us:
• Call ${EMERGENCY.ambulance}, or go to the nearest hospital emergency department (IGD)

While you wait, some things that might help: ${ORG.resourcesURL}`,
}

// ─────────────────────────────────────────────────────────────────────────
// Step 4 — Automated Intake. Four questions, nothing more.
// ─────────────────────────────────────────────────────────────────────────

export const ASK_DANGER = {
  id: `Boleh kami tanya beberapa hal singkat, supaya bisa mengarahkanmu dengan tepat?

Apakah kamu saat ini dalam bahaya langsung?

Balas dengan angka:
1 — Ya
2 — Tidak
3 — Tidak yakin`,

  en: `May we ask a few short questions, so we can point you to the right support?

Are you currently in immediate danger?

Reply with a number:
1 — Yes
2 — No
3 — Not sure`,
}

export const ASK_CITY = {
  id: 'Kamu sedang berada di kota atau kabupaten mana? (misalnya: Denpasar, Gianyar, Buleleng)',
  en: 'Which city or regency are you in right now? (for example: Denpasar, Gianyar, Buleleng)',
}

export const ASK_LANGUAGE = {
  id: `Bahasa apa yang paling nyaman untukmu?

1 — Bahasa Indonesia
2 — English`,
  en: `Which language are you most comfortable in?

1 — Bahasa Indonesia
2 — English`,
}

export const ASK_NEED = {
  id: `Dukungan seperti apa yang kamu butuhkan hari ini?

1 — Seseorang untuk diajak bicara
2 — Cemas atau panik
3 — Kecanduan
4 — Menyakiti diri sendiri atau pikiran untuk bunuh diri
5 — Rujukan ke bantuan profesional
6 — Lainnya`,

  en: `What support do you need today?

1 — Someone to talk to
2 — Anxiety or panic
3 — Addiction
4 — Self-harm or suicidal thoughts
5 — Referral to professional help
6 — Other`,
}

export const DIDNT_UNDERSTAND = {
  id: 'Maaf, kami belum menangkap jawabannya. Balas dengan angka saja, ya.',
  en: "Sorry, we didn't catch that. Please reply with just the number.",
}

// ─────────────────────────────────────────────────────────────────────────
// The danger path. Intake stops here — nobody in immediate danger should
// have to fill in a form.
// ─────────────────────────────────────────────────────────────────────────

export const IN_DANGER = {
  id: `Terima kasih sudah memberi tahu kami. Keselamatanmu yang paling penting sekarang, jadi kami berhenti dengan pertanyaannya.

Tolong hubungi salah satu ini sekarang — semuanya buka 24 jam:

• ${EMERGENCY.ambulance} (ambulans / gawat darurat), atau langsung ke IGD rumah sakit terdekat

Kalau bisa, minta seseorang yang kamu percaya untuk menemanimu sekarang. Kalau ada obat atau benda yang bisa melukaimu di dekatmu, coba titipkan dulu ke orang lain.

Kamu tidak sendirian. Pesanmu sudah kami tandai sebagai prioritas tertinggi, dan relawan kami akan melihatnya.`,

  en: `Thank you for telling us. Your safety matters more than our questions right now, so we'll stop asking them.

Please contact one of these now — all are open 24 hours:

• ${EMERGENCY.ambulance} (ambulance / emergency), or go straight to the nearest hospital emergency department (IGD)

If you can, ask someone you trust to stay with you right now. If there are medicines or objects nearby that could hurt you, try to give them to someone else to hold.

You are not alone. We've marked your message as our highest priority and a volunteer will see it.`,
}

export const UNSURE_DANGER = {
  id: `Terima kasih sudah jujur. Kalau keadaannya berubah dan kamu merasa tidak aman, jangan menunggu kami — telepon ${EMERGENCY.ambulance}.

Beberapa pertanyaan lagi, ya.`,

  en: `Thank you for being honest. If things change and you feel unsafe, please don't wait for us — call ${EMERGENCY.ambulance}.

Just a couple more questions.`,
}

// ─────────────────────────────────────────────────────────────────────────
// Step 5 — Automated Waiting Message. Tailored to what they asked for.
// This must not read as a rejection.
// ─────────────────────────────────────────────────────────────────────────

export const WAITING_INTRO = {
  id: 'Terima kasih. Permintaanmu sudah masuk dan akan ditinjau oleh relawan kami.',
  en: "Thank you. Your request is in, and one of our volunteers will review it.",
}

export const WAITING_CLOSE = {
  id: `Kamu tidak harus menghadapi ini sendirian. Seorang relawan akan meninjau permintaanmu.

Yang bisa kamu harapkan dari ${ORG.name}: relawan terlatih yang mendengarkan tanpa menghakimi, dalam Bahasa Indonesia atau Inggris. Kami tidak memberi diagnosis atau resep, dan kami bukan layanan darurat — tapi kami bisa membantumu mencari rujukan kalau kamu membutuhkannya.`,

  en: `You do not have to deal with this alone. A volunteer will review your request.

What to expect from ${ORG.name}: a trained volunteer who listens without judging, in Indonesian or English. We don't diagnose or prescribe, and we're not an emergency service — but we can help you find a referral if you need one.`,
}

/** Grounding steps, for panic. */
export const RESOURCE_GROUNDING = {
  id: `Kalau panik datang, ini kadang membantu:
• Tarik napas 4 hitungan, tahan 4, hembuskan 6. Ulangi lima kali.
• Sebutkan dalam hati 5 hal yang kamu lihat, 4 yang bisa kamu sentuh, 3 yang kamu dengar, 2 yang kamu cium, 1 yang kamu rasakan.
• Pegang sesuatu yang dingin — segelas air, keran, atau kipas angin.

Panik terasa menakutkan, tapi biasanya memuncak lalu mereda sendiri dalam beberapa menit.`,

  en: `When panic hits, these sometimes help:
• Breathe in for 4, hold for 4, out for 6. Repeat five times.
• Name 5 things you can see, 4 you can touch, 3 you can hear, 2 you can smell, 1 you can taste.
• Hold something cold — a glass of water, a tap, a fan.

Panic feels frightening, but it usually peaks and then eases on its own within a few minutes.`,
}

/** Safety-plan starter. Offered, never demanded. */
export const RESOURCE_SAFETY_PLAN = {
  id: `Sambil menunggu, mungkin membantu untuk menuliskan tiga hal di HP-mu:
• 3 tanda kamu mulai merasa tidak aman
• 2 hal yang pernah menolongmu melewatinya
• 1 orang yang bisa kamu hubungi kapan saja`,

  en: `While you wait, it can help to write three things down in your phone:
• 3 signs that you're starting to feel unsafe
• 2 things that have helped you through it before
• 1 person you could contact at any hour`,
}

/** Recovery and addiction community programmes. */
export const RESOURCE_RECOVERY = {
  id: `Untuk pemulihan dan kecanduan, ada beberapa program komunitas di jaringan Bali Bersama Bisa:
• Movement of Recovery — https://movementofrecovery.org
• Direktori layanan lainnya — ${ORG.servicesURL}`,

  en: `For recovery and addiction, there are community programmes in the Bali Bersama Bisa network:
• Movement of Recovery — https://movementofrecovery.org
• Directory of other services — ${ORG.servicesURL}`,
}

/** How to support someone else. */
export const RESOURCE_SUPPORT_FRIEND = {
  id: `Kalau kamu sedang mendampingi orang lain: dengarkan tanpa buru-buru memberi solusi, tanya langsung dan tenang apa yang mereka rasakan, dan jangan tinggalkan mereka sendirian kalau kamu merasa mereka dalam bahaya. Kamu tidak harus punya jawabannya — hadir saja sudah berarti.

Panduan lebih lengkap: https://bisahelpline.org/resources/`,

  en: `If you're supporting someone else: listen without rushing to fix it, ask them directly and calmly how they're doing, and don't leave them alone if you think they're in danger. You don't need to have the answers — being there already matters.

A fuller guide: https://bisahelpline.org/resources/`,
}

/** Local referrals, in and out of Bali. */
export const RESOURCE_REFERRAL_BALI = {
  id: `Untuk bantuan profesional di Bali, direktori layanan kami ada di sini: ${ORG.servicesURL}`,
  en: `For professional help in Bali, our directory of services is here: ${ORG.servicesURL}`,
}

export const RESOURCE_REFERRAL_OUTSIDE = {
  id: `Karena kamu berada di luar Bali, kami tidak bisa bertemu langsung — tapi kamu tetap bisa mendapat bantuan di dekatmu. Puskesmas dan rumah sakit umum punya layanan kesehatan jiwa, dan daftar penyedia layanan per kota ada di sini: https://www.intothelightid.org/tentang-bunuh-diri/daftar-penyedia-layanan-kesehatan-mental/`,

  en: `Since you're outside Bali we can't meet in person — but there is help closer to you. Puskesmas and public hospitals have mental health services, and a directory by city is here: https://www.intothelightid.org/tentang-bunuh-diri/daftar-penyedia-layanan-kesehatan-mental/`,
}

/** Sent once if they message again after being queued. Not a re-intake. */
export const ALREADY_QUEUED = {
  id: `Kami masih menyimpan permintaanmu dan relawan kami akan menghubungimu.`,
  en: `We still have your request and a volunteer will be in touch.`,
}
