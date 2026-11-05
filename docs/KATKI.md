# Çeviriye katkı

Katkı için önce ilgili görev veya ekran grubunu seç. Aynı kayıt üzerinde birden fazla kişinin çalışmaması için bir issue açıp kapsamı belirt. Çevrilen dosyaların ve bekleyen kayıtların durumu sürüm kayıtlarında tutulur.

## Metin katkısı

1. Güncel kaynak sürümünü ve sözlüğü kontrol et.
2. Sana ayrılan küçük kayıt grubunda yalnız `translation_tr` değerlerini değiştir.
3. Kimlikleri dize olarak koru; kaynak, özet, bağlam ve korunan işaretleri değiştirme.
4. İşaret, satır sonu ve kenar boşluğu kontrollerini çalıştır.
5. Çeviriyi bağlamıyla birlikte oku; belirsizlikleri not et.
6. Pull request içinde işlenen grup, kayıt sayısı ve kalan belirsizlikleri belirt.

Kişi adları ve özel terimler için mevcut sözlüğü kullan. Terim değişikliği öneriyorsan ilgili kullanımları ve gerekçeyi göster; yalnız bir satırı değiştirerek tutarsızlık oluşturma. Boş metin, kod, simge veya aynen korunan özel adı yeni çeviri sayısına dahil etme.

## Oyun içi kontrol

Sorunu gösteren ekran görüntüsünü, metnin geçtiği ekranı ve varsa görev/konuşma bağlamını ekle. Metin kimliği biliniyorsa belirt. Oyuncu kimliği, e-posta, sohbet içeriği veya kişisel yol gibi bilgileri görüntüden kaldır.

Yazı taşması, yanlış karakter, eksik değişken ve anlam hatası ayrı sorunlar olabilir. Beklenen Türkçe karşılığı ve görünen sonucu kısa bir örnekle açıkla. Oyun sürümü ve kullanılan yama sürümü aynı raporda yer alsın.

## Kod katkısı

Kurucu değişiklikleri, özellikle güncelleme ve geri alma yolunu korumalıdır. Aynı kurulu yamanın tekrar çalıştırılmasında dosyalara yeniden metin eklenmemesi; yeni sürümde özgün kaynaktan derleme; kaynak/bağlam değişiminde inceleme kaydı; dosyalar hazırlık sırasında değişirse durma ve kesintide doğrulanmış geri dönüş davranışları kontrol edilmelidir.

Sentetik test verilerini kullan. Oyun ikililerini, tam özgün İngilizce ana tabloyu, yerel `state/` alanını veya kullanıcı yedeklerini pull request'e ekleme. Üçüncü taraf dosyalarında kaynak ve lisans bildirimlerini koru.

## Pull request açıklaması

Açıklama, değişen davranışı ve nedenini anlatmalı. Çeviri katkısında kayıt grubu ve doğrulama sonucu; kurucu katkısında somut önce/sonra davranışı ve ilgili test sonucu yeterlidir. İncelenmemiş oyun içi davranışı doğrulanmış diye yazma.
