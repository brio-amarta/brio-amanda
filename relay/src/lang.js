// Which language did they write in?
//
// Sam's rule: reply in the sender's language, Indonesian or English, never
// both. This is a heuristic on function words, not a classifier — it only has
// to separate two languages, and it fails toward Indonesian because that is
// the community's default.

const ID_MARKERS = new Set([
  'yang', 'tidak', 'ya', 'iya', 'saya', 'aku', 'kamu', 'anda', 'kami', 'kita',
  'dan', 'atau', 'tapi', 'tetapi', 'dengan', 'untuk', 'dari', 'ke', 'di',
  'pada', 'ini', 'itu', 'apa', 'siapa', 'kapan', 'dimana', 'bagaimana',
  'kenapa', 'mengapa', 'bisa', 'boleh', 'mau', 'ingin', 'sudah', 'belum',
  'akan', 'jangan', 'terima', 'kasih', 'makasih', 'terimakasih', 'tolong',
  'maaf', 'halo', 'hai', 'selamat', 'pagi', 'siang', 'sore', 'malam',
  'jadwal', 'sesi', 'daftar', 'butuh', 'perlu', 'ada', 'adalah', 'juga',
  'lagi', 'saja', 'aja', 'nggak', 'gak', 'ga', 'engga', 'banget', 'bang',
  'mbak', 'mas', 'kak', 'bu', 'pak', 'oke', 'baik', 'sehat', 'hari',
])

const EN_MARKERS = new Set([
  'the', 'is', 'are', 'am', 'was', 'were', 'a', 'an', 'and', 'or', 'but',
  'with', 'for', 'from', 'to', 'in', 'on', 'at', 'this', 'that', 'what',
  'who', 'when', 'where', 'how', 'why', 'can', 'could', 'would', 'should',
  'want', 'need', 'have', 'has', 'will', 'please', 'thanks', 'thank',
  'sorry', 'hello', 'hi', 'hey', 'good', 'morning', 'afternoon', 'evening',
  'schedule', 'session', 'appointment', 'help', 'yes', 'no', 'okay', 'ok',
  'my', 'your', 'me', 'you', 'i', 'we', 'it', 'not', 'do', 'does', 'did',
])

/**
 * @param {string} text
 * @param {'id'|'en'} fallback  what to use when the text carries no signal
 * @returns {'id'|'en'}
 */
export function detectLanguage(text, fallback = 'id') {
  if (!text) return fallback

  const words = text
    .toLowerCase()
    .replace(/[^\p{L}\s']/gu, ' ')
    .split(/\s+/)
    .filter(Boolean)

  if (words.length === 0) return fallback

  let id = 0
  let en = 0
  for (const word of words) {
    if (ID_MARKERS.has(word)) id++
    if (EN_MARKERS.has(word)) en++
  }

  // Indonesian affixes English never produces — strong signal on their own.
  const affixed = words.filter((w) =>
    /^(meng|meny|mem|men|ber|ter|pe|di)[a-z]{3,}/.test(w) ||
    /[a-z]{3,}(kan|nya|lah|ku|mu)$/.test(w)
  ).length
  id += affixed

  if (id === en) return fallback
  return id > en ? 'id' : 'en'
}

/**
 * Picks the right string from a {id, en} pair.
 * @param {{id: string, en: string}} pair
 * @param {'id'|'en'} lang
 */
export function say(pair, lang) {
  return pair[lang] ?? pair.id
}
