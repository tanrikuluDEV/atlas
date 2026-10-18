// Ziyaretçinin bağlandığı ülkeyi (ISO kodu) döndürür; arayüz dili ilk açılışta buna göre seçilir.
// Vercel bu başlığı isteğin IP adresinden ekler; IP'nin kendisi saklanmaz ya da döndürülmez.
module.exports = (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ country: req.headers['x-vercel-ip-country'] || null }));
};
