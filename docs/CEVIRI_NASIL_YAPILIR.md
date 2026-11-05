# Çeviri nasıl yapılır

Çeviri, ekrandan yazı okumak yerine oyun paketlerindeki İngilizce metin kayıtlarına uygulanır. Her karşılık bir metin kimliğine bağlıdır. Bu kimlikler korunarak çevrilen dizeler kopya tabloda değiştirilir; kurulum için gerekli paket alanları yeniden üretilir.

## Metnin kaynağını bulma

Bu projede incelenen Epic PC kurulumunda Unity ve IL2CPP yapısı bulunur. `StreamingAssets/VFS` temel verileri, `Persistent/VFS` ise güncellenmiş verileri taşır. Mantıksal dosyalar fiziksel `.chk` parçalarına yerleştirilir; `.blc` indeksleri bunların konum ve bütünlük bilgilerini içerir.

| İçerik | Mantıksal kaynak |
|---|---|
| İngilizce metinler | `I18nTextTable_EN` |
| Genel arayüz ve görev anahtarları | `TextTable` |
| Hikâye konuşmaları | `DialogTextTable` |
| Diyalog seçenekleri | `DialogOptionTable` |
| Öğretici sayfaları | `WikiTutorialPageTable` |
| Karakter öğreticileri | `DungeonCharTutorialStepTable` |
| Görev akışı ve hedef bağlantıları | `MissionRuntimeAsset` |

Bir görev kaydındaki anahtar, `TextTable` üzerinden 64 bit kimliğe; kimlik de İngilizce dil tablosundaki metne bağlanabilir. Bağlam olarak tablo, satır anahtarı ve alan yolu saklanır. Aynı metin kimliği birden fazla ekranda kullanılabilir.

Kaynakta bulunmak, bir konuşmanın o anda oyunda erişilebilir olduğunu veya sahne numarasının oynatma sırasını belirlediğini kanıtlamaz. Anlatım sırası için yalnız dosya adı veya hash sıralaması kullanılmaz.

## Çeviri kaydını hazırlama

Özel çalışma kataloğu, özgün İngilizce metinle birlikte kaynak SHA-256 özeti, bağlam, korunan işaretler ve Türkçe karşılığı taşır. Tam özgün İngilizce ana tablo yerel çalışma verisidir; herkese açık depoya eklenmez. Dağıtım kataloğundaki kaynak özetleri, bilgisayarda çıkarılan özgün metinle karşılaştırılır.

64 bit kimlikleri JSON'da dize olarak sakla. JavaScript `Number` türüne çevirmek kimlikleri bozabilir. Kaynak metni, kaynak özetini veya bağlamı çeviriye uydurmak için değiştirme. Çalışma dosyalarında yalnız `translation_tr` alanını düzenle.

## İşaretleri koruma

Görünen kelimeler çevrilirken değişkenler ve biçim işaretleri korunur:

```text
Talk to <@qu.key>Vera</>
<@qu.key>Vera</> ile konuş
```

`{0}`, `%s`, `%1$s`, `{F}`, `{M}`, `<action=...>`, `<color=...>`, `<@...>` ve `</>` gibi işaretler oyun tarafından yorumlanır. Cinsiyet dallarını birleştirme; iki dalın metnini ayrı tut. Satır sonları, sekmeler ve baştaki/sondaki boşluklar da kayıt biçiminin parçası olabilir.

Bu projenin doğrulayıcısı korunan işaretlerin sırasını da karşılaştırır. Literal yüzde ifadelerinde bilinen üç yanlış eşleşme, yalnız ilgili kimlik ve tam özgün kaynak eşleştiğinde ele alınır; gerçek yer tutucu kontrolü genel olarak gevşetilmez.

## Dil ve terim kontrolü

Karakter adlarını ve yerleşik özel adları koru. Aynı kavramı mevcut sözlükle tutarlı kullan; bağlam değiştiğinde tek bir kelimeyi körlemesine her yere uygulama. Kısa düğme etiketlerini kısa tut. Uzun açıklamalarda anlamı ve doğal Türkçeyi önceliklendir.

Bir kaydın kaynakla aynı bırakılması onu çevrilmiş yapmaz. Özel adlar, kodlar, boş kayıtlar ve simgeler ayrı sayılır. Bağlamı çözülemeyen kayıtlar tahminle tamamlandı işaretlenmez.

## Yeniden paketleme ve kurulum

Yerel araç, güncel özgün SparkBuffer tablosunu okur. Türkçe dizeleri kopyada oluşturup ilgili metin işaretçilerini günceller; kimlikleri korur. Veri parçası ve blok indeksi için gerekli boyut, konum ve özet alanları yeniden hesaplanır. Çevirili tablo bağımsız okuyucuyla açılarak yalnız beklenen değerlerin değiştiği kontrol edilir.

Kaynak ve çıktı özetleri, uygulanan katalog özeti ve oyun sürümü kurulum kaydında birlikte tutulur. Bu kayıt, aynı yamayı tekrar tekrar eklemek yerine durumu tanımayı ve güncelleme sonrası yeni özgün kaynaktan derlemeyi sağlar. Uygulama ve geri alma aşamaları [manuel kurulum rehberinde](MANUEL_KURULUM.md) açıklanır.

## İki ayrı doğrulama

Dosya denetimi; kimlik, kaynak, bağlam, işaret, değişmez alan ve paket bütünlüğünü sınar. Oyun içi denetim ise Türkçe harfleri, yazı taşmalarını, dinamik metin birleşimlerini, seçenekleri ve anlatım bağlamını sınar. Dosya denetiminin geçmesi tek başına bütün ekranların dil ve yerleşim açısından doğru olduğu anlamına gelmez.
