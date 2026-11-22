# Sürüm notları

## v0.2.0

Epic PC'nin 27950529 numaralı oyun verisinde **135.729 Türkçe karşılık** doğrulandı. 167.300 metin kaydından 31.571'i özgün haliyle kaldı. Önceki çalışma kataloğundan yedi metin, oyun güncellemesiyle kullanıldıkları bağlam değiştiği için ayrıldı. Yeni 34 kayıtta da özgün metin korunur.

Kurulum için bu sürümün ZIP dosyasını açıp `Kur.cmd` çalıştırın. Oyunda metin dili **English** olmalıdır. 0.1.x kurucularının sınırı 32 MiB olduğu için onların veri yolu v0.1.2'de tutulur. Yeni kurucu, geniş kataloğu paketle birlikte getirir ve sonraki açılışlarda güncellemeleri `translations/current/latest.json` üzerinden denetler. Eski kurulumun aynı klasörüne açarken kişisel `state/` ve `config.json` dosyalarınızı koruyun.

Yeni katalogda yalnızca çeviriler, kayıt kimlikleri, kaynak özetleri, bağlam tanımları ve korunması gereken biçim işaretleri yayımlanır. İki yüzde ifadesinin denetimi yalnızca doğrulanmış metin çiftlerine uygulanır. Güncel Epic kurulumunda 167.300 kayıt geri okunup karşılaştırıldı. Dağıtımdaki katalog ve kurucu aynı kaynaktan oyuna kurulmuş dil tablosunu bayt bayt yeniden üretti. Tüm oyun ekranlarında görünüm ve metin taşması denetimi sürmektedir. Steam ve doğrudan kurulumların oyun içi uyumluluğu ayrıca doğrulanmalıdır.

## v0.1.2

27533267 kaynak sürümü için kamu kataloğu 11.312 karşılıktan **17.648 Türkçe karşılığa** yükseldi. c33m2 grubu tamamlandı; c31m3 **Savaşçının Azmi** açılışındaki dört sahne ile görev başlığı ve açıklaması için 105 kayıt işlendi: 67 çeviri, 38 korunan özel ad. c31m3 grubunun tamamı henüz bitmedi.

Hazır çalışma kataloğunda 17.649 çeviri bulunur. Bunlardan tek bir yüzde ifadesi, mevcut v0.1.0 ve v0.1.1 kurucularının biçim doğrulamasıyla uyum için kamu veri kanalına eklenmedi. Bu kayıt oyunda İngilizce kalır. Kamu sayıları: 17.648 Türkçe, 7.983 korunan, 141.635 bekleyen kayıt.

Yeni kurucu, düz yüzde ifadesi için tam kimlik ve kaynak eşleşmesine bağlı dar doğrulama desteği içerir; gerçek etiket ve değişken kaybı yine reddedilir. Açıkça yerel katalog seçildiğinde eski indirme önbelleğinin bu seçimi geçersiz kılması düzeltildi. Ağ denetimi açıkken doğrulanmış çevrimdışı önbellek davranışı korunur.

Mevcut kurucular kamu veri güncellemesini alabilir. Yeni kurucu kodunu kullanmak için sürüm ZIP'ini oyun klasörü dışındaki yama klasörüne çıkarın; kendi `config.json` ve `state/` alanınızı koruyun. Kurulum adımları README içindedir.

Bu yayın sırasında oyun dosyalarına kurulum yapılmadı ve oyun başlatılmadı. Metin verisi, kaynak eşleşmesi ve kurucu testleri oyun içindeki görünüm ve taşma testlerinden ayrıdır. Geniş oyun içi yerleşim kontrolü devam ediyor; bu sürüm ön yayın olarak sunulur.
