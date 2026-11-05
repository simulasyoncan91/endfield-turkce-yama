# Arknights Endfield Türkçe Yama

Windows PC için OCR kullanmadan hazırlanan topluluk çevirisi ve yerel kurulum aracı. Epic Games, Steam ve doğrudan resmî kurulum konumları tespit edilir; dosya biçimi her kurulumda yeniden doğrulanır. Türkçe karşılıklar metin kimlikleriyle eşleştirilir; oyun güncellendiğinde uyumlu kayıtlar yeni özgün kaynaklardan yeniden paketlenir.

Çalışma devam ediyor. 27533267 kaynak sürümü için bu yayında **11.284 Türkçe karşılık** bulunur; 5.217 boş/ad/kod/simge kaydı aynen korunmuş, 150.765 kayıt henüz çevrilmemiştir. Bu sayılar tam İngilizce kaynak envanterine aittir; her kaydın oyunda kullanıldığı varsayılmaz. Güncel kapsam [ilerleme kaydında](translations/progress.json) tutulur.

## Amaç ve dosya değişikliği hakkında

Bu proje, dil engelini aşarak Arknights: Endfield’in hikâyesini ve oyun içi metinlerini Türkçe okuyabilmek için geliştirilen bir topluluk çeviri aracıdır. Ekrandaki yazıyı OCR ile okuyup üzerine çeviri yerleştirmek yerine, çeviri metinlerini oyunun yerel dil tablosuna uygular. Amaç oynanışta avantaj sağlamak değildir.

Araç oyun dosyalarını değiştirir. Projenin çeviri amacı taşıması, yapımcının bu değişikliğe resmî izin verdiği anlamına gelmez. Yapımcının bunu nasıl sınıflandıracağına veya hesap yaptırımı uygulanmayacağına ilişkin garanti verilmez. Oyunun yayımladığı kurallar ve yapımcının kararları geçerlidir.

Paketleri okumak ve yeniden hazırlamak için kullanılan iki açık kaynak VFS dosyasının görevleri, sabit değerlerin niteliği ve yapılan değişikliğin sınırları [teknik açıklamada](docs/AMAC_VE_TEKNIK_ACIKLAMA.md) anlatılır.

## Kurulum

**Epic Games aracılığıyla indirilen sürümde çalıştı. Steam ve doğrudan kurulum sürümlerinde henüz denenmedi.** Şimdilik gerçek oyun testleri Epic sürümüne odaklanır. Steam ve doğrudan kurulum için konum bulma desteği vardır; bu destek oyun içi uyumluluğun doğrulandığı anlamına gelmez.

Windows, **PowerShell 7.5+ (.NET 9+)** ve **Python 3.9+** gerekir. Geniş paketin bütün ekranlarında görünüm ve metin taşması kontrolü henüz tamamlanmadı.

1. GitHub'dan paketi indirip oyun klasörünün dışında bir klasöre çıkar. Güncellemelerde aynı yama klasörünü ve `state/` alanını koru.
2. Resmî oyun güncellemesini tamamla; oyunu ve oyuna ait başlatıcıyı kapat.
3. **`Kur.cmd`** dosyasını çalıştır. Masaüstü kısayolu için: `pwsh -NoProfile -File .\Kur.ps1 -CreateShortcut`.
4. Sonraki açılışlarda **`Turkce-Ile-Baslat.cmd`** veya oluşturduğun kısayolu kullan. Metin dili **English / İngilizce** olarak kalsın.

Bu giriş, her açılışta hem GitHub'daki çeviri sürümünü hem kurulu oyun verisini denetler. Yeni çeviri varsa yalnız veri kataloğunu indirir; SHA-256/boyut kontrolünden sonra uyumlu kayıtları yeni özgün kaynaktan derler. Ağ yoksa doğrulanmış yerel katalogla devam eder. Kod veya kurucu betiği uzaktan indirilip çalıştırılmaz.

Oyun klasörü otomatik bulunamazsa veri klasörünü belirt:

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Apply -GameData 'D:\Oyunlar\Arknights Endfield\Endfield_Data'
```

[Adım adım manuel kurulum](docs/MANUEL_KURULUM.md), [çevirinin nasıl yapıldığı](docs/CEVIRI_NASIL_YAPILIR.md) ve [katkı rehberi](docs/KATKI.md) ayrı belgelerde açıklanır.

## Oyun güncellendiğinde

Çeviri kataloğu ve özgün sürüm yedekleri oyun klasörünün dışında kalır. Başlatma girişindeki otomatik kontrol, yeni paket adını ve metin konumlarını gerçek indekslerden belirler. Kaynak özeti ve bağlamı değişmeyen çeviriler yeniden uygulanır; değişen kayıtlar İngilizce kalıp `needs_review.json` raporuna ayrılır. Tanınmayan biçimde dosyaya yazılmadan durulur.

Resmî başlatıcı, bu kontrolden **sonra** da içerik güncelleyebilir. Böyle bir ilk oturumda bazı metinler İngilizce görünebilir. Sarmalayıcı açık oyuna yazmaz; oyun/başlatıcı oturumu tamamen kapandıktan sonra tekrar denetleyerek sonraki açılış için onarır. Her gelecekteki sürümde ilk oturumun yüzde yüz Türkçe olacağı sözü verilmez.

Steam sürümü güncellemelerini Steam'den alır; GRYPHLINK ile güncellenmez. [GRYPHLINE Steam SSS](https://steamcommunity.com/app/4732690/discussions/0/525387344813142877/). Epic ve doğrudan kurulumlarda kendi resmî başlatıcının güncellemesini kullan. Her platformun özgün paketleri ayrı ele alınır; bir mağazanın `.chk/.blc` dosyası diğerine kopyalanmaz.

## Kontrol ve geri alma

| Komut | İşlem |
|---|---|
| `-Mode Check` | Kurulu sürümü ve yama durumunu kontrol eder. |
| `-Mode Prepare` | Çeviriyi çalışma kopyasında hazırlar; oyuna kurmaz. |
| `-Mode Apply` | Hazırlama, doğrulama ve yedekli kurulumu yürütür. |
| `-Mode Restore` | Aynı sürüm için kayıtlı özgün dosyalara döner. |

Yedekler, özgün kaynaklar ve uygulama kayıtları yerel `state/` alanında tutulur. Oyun güncellemesiyle dosyalar değişmişse eski sürüm yedeği yeni sürümün üzerine yazılmaz. Kurulum bir dosya değişikliği tespit ederse durur; raporu incele.

## Kapsam ve test durumu

Metinler oyunun İngilizce dil tablosunun üzerine uygulanır. Yeni bir Türkçe dil seçeneği eklenmez. İkili tablo okuması, kimlik ve işaret koruması ile paket bütünlüğü kontrolleri, oyun içi yazı taşması ve anlatım kontrolünden ayrıdır. İlk küçük denemedeki “Karakterler” metni oyun ekranında görüldü; geniş sürümlerin ekran kontrolleri katkı ve hata bildirimleriyle sürdürülür.

Görsellere veya videolara gömülü yazıların ve kod içindeki olası sabit metinlerin tamamı bu kapsamda sayılmaz. `Arayüz hazır` ifadesi, kaynakta arayüz olarak sınıflandırılan kayıtların hazırlanmış olduğunu belirtir; bütün ekranların oyun içinde incelendiği anlamına gelmez.

## Proje dosyaları

- `translations/`: Türkçe karşılıklar ve sürüm eşleştirme bilgileri.
- `bin/`: yerel çıkarma, kontrol ve yeniden paketleme desteği.
- `docs/`: kurulum, çeviri ve katkı belgeleri.
- `state/`: yalnız yerel özgün kaynaklar, yedekler ve kayıtlar; Git'e eklenmez.

Depoda oyunun `.chk`, `.blc`, `.dll`, `.bytes` dosyaları, tam özgün İngilizce ana tablo ve yerel yedekler yayımlanmaz. Proje bağımsız bir topluluk çalışmasıdır; Hypergryph veya GRYPHLINE tarafından yayımlanmış resmi bir yerelleştirme değildir.

## Kaynak araçlar

VFS ve SparkBuffer okuma desteği [Variante AnimeStudio](https://github.com/Variante/AnimeStudio/tree/19ae4808c23069bd901e17f962e60a5fb87475c5) kaynaklarından uyarlanmıştır. [Endfield Research Kit](https://github.com/Variante/endfield_research_kit) veri yapılarının incelenmesinde kullanılmıştır. Üçüncü taraf kaynak ve lisans bildirimleri [bildirimler dosyasında](docs/THIRD_PARTY_NOTICES.md) korunur.
