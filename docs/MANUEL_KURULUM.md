# Manuel kurulum ve güncelleme

Bu yol, her aşamayı görerek çeviriyi hazırlayıp kurmak içindir. Yama klasörü oyun klasörünün dışında kalır. Böylece resmi oyun güncellemesi çeviri kataloğunu ve yerel yedekleri kaldırmaz.

## Hazırlık

Epic Games, Steam veya doğrudan resmî PC kurulumunu kullan. Resmi başlatıcıda bekleyen güncellemeyi tamamladıktan sonra Endfield'i ve oyuna ait başlatıcıyı kapat. Epic Games Launcher'ın arka planda açık olması tek başına oyunun güncelleme yaptığı anlamına gelmez; araç uygulamadan önce dosyaları ayrıca denetler.

Paket ZIP'ini oyun klasörünün dışına çıkar. Önceki sürümden güncelliyorsan aynı yama klasörünü ve özgün dosyaların yedeklerini içeren `state/` alanını koru. İki kopyayı da yamalayacaksan her biri için ayrı bir yama klasörü kullan. Dosya Gezgini'nde çıkarılan yama klasörünü aç, adres çubuğuna `powershell` yazıp Enter'a bas. Açılan pencerede `pwsh --version` en az **7.5**, `python --version` en az **3.9** göstermeli. `python` komutu yoksa `py -3 --version` kullan. Eksik aracı kurduktan sonra yeni bir pencere aç. [PowerShell kurulumu](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) · [Python kurulumu](https://www.python.org/downloads/windows/)

## Oyun klasörünü seç ve durumu kontrol et

Aşağıdaki örnek yolu kendi kurulumundaki **Endfield_Data** klasörüne göre değiştir. Diğer komutları aynı pencerede çalıştır. Böylece Epic ve Steam birlikte kurulu olsa da her adım aynı kopyayı kullanır.

```powershell
$oyunVerisi = 'D:\Oyunlar\Arknights Endfield\Endfield_Data'
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Check -GameData $oyunVerisi
```

Temiz v0.2.0 kurulumunda `translations/current/catalog.json` pakette hazır gelir. Menüde Türkçe görünmesi için oyunun metin dili **English / İngilizce** olmalı.

## Çalışma kopyasını hazırla

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Prepare -GameData $oyunVerisi
```

Bu aşama güncel indekslerden İngilizce metnin yerini belirler. Katalog kayıtlarını yeni özgün kaynakla karşılaştırır; kaynağı veya bağlamı değişmiş olanları inceleme listesine ayırır. Uygun karşılıkları kopyalarda derleyip paket bütünlüğünü denetler. Oyun hedefleri değiştirilmez.

Hazırlık raporundaki oyun sürümünü, uygulanabilir kayıt sayısını ve inceleme gerektiren kayıtları kontrol et. Yalnız hazır bir `id → Türkçe` dosyası, kaynak kimliği ve özeti doğrulanmadan farklı oyun sürümüne uygulanmaz.

## Yedekli kurulumu uygula

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Apply -GameData $oyunVerisi
```

`Apply` hazırlığı ve doğrulamayı kendi akışında yeniden denetler. Güncel sürümün özgün dosyalarını yedekler; dosyalar incelemeden sonra değişmişse yazmadan durur. Kurulumdan sonra kurulu paket yeniden okunur ve beklenen içerikle karşılaştırılır. Başarılı sonuç ve dosya özetleri yerel uygulama kaydına yazılır.

Fiziksel `.chk` ve `.blc` dosyalarını Explorer ile tek tek kopyalamak bu akışın yerine geçmez. Aynı sürüm numarası görünse bile kaynak özeti, dosya konumu veya paket içeriği değişebilir. Özellikle eski sürümün blok indeksini yeni kurulumun üzerine kopyalama.

## Oyunda kontrol et

Kurulumu doğruladıktan sonra oyunu normal resmî başlatıcından açabilirsin. Çeviri sürümünü de kontrol eden başlatıcıyı kullanmak için aşağıdaki komutu çalıştır. `-GameData` manuel kurulumda seçtiğin kopyayı belirtir. Gerekirse sonuna `-Platform Epic`, `-Platform Steam` veya `-Platform Direct` ekle.

```powershell
.\Turkce-Ile-Baslat.cmd -GameData $oyunVerisi
```

Oyunu açmadan başlatıcıyı denemek için aynı komuta `-NoLaunch` ekle. Bu seçenek gerektiğinde yamayı uygular. Yalnız durumu görmek için `-Mode Check` kullan.

Başlatıcı arada yeni bir içerik güncellemesi yaparsa önce bu güncellemenin bitmesini bekle; oyunu ve oyuna ait başlatıcıyı kapattıktan sonra `Check` ve `Apply` adımlarını tekrarla.

## Aynı sürümün özgün dosyalarına dön

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Restore -GameData $oyunVerisi
```

Geri alma, yerel uygulama kaydındaki sürüm ve dosya özetlerini esas alır. Hedefler sonradan değişmişse durur. Bu durumda eski yedeği elle zorlamak yerine resmi başlatıcıdaki doğrulama veya onarım yolunu kullan; ardından yama durumunu yeniden kontrol et.

Özgün dosyalarla oynamaya devam edeceksen oyunu normal resmî başlatıcından aç. Türkçe başlatıcı bir sonraki açılışta yamayı yeniden uygular.

## Sorunu bildir

Komutun `Check`, `Prepare`, `Apply` veya `Restore` aşamasında olduğunu, oyun sürümünü ve hata metnini belirt. Paylaşmadan önce rapordaki kullanıcı adını ve kişisel klasör yollarını kaldır. Hesap bilgisi, giriş kodu veya oyun ikilileri ekleme.

## Platformu açıkça seç

Türkçe başlatıcıya her seferinde yol vermek istemiyorsan aşağıdaki örnekle kurulum seçimini bir kez kaydet. Bu işlem de yamayı uygular. Epic yerine Steam veya Direct kullanıyorsan platform adını ona göre değiştir. Masaüstü kısayolu istiyorsan komuta `-CreateShortcut` ekle.

```powershell
.\Kur.cmd -Platform Epic -GameData $oyunVerisi
```

Doğrudan kurulumda resmî başlatıcı otomatik bulunmazsa yerel `config.json` içindeki `OfficialLauncher` alanına doğru resmî yürütülebilir dosyayı gir.

## Windows indirilen betiği engellerse

“Betik dijital olarak imzalanmamış” hatası görürsen önce [sürüm sayfasından](https://github.com/simulasyoncan91/endfield-turkce-yama/releases/tag/v0.2.0) ZIP'in yanındaki aynı adlı `.sha256` dosyasını indir. ZIP'in bulunduğu klasörde PowerShell açıp aşağıdaki komutu çalıştır. Çıkan değeri `.sha256` dosyasındaki değerle karşılaştır.

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '.\endfield-turkce-yama-v0.2.0.zip'
```

Değerler eşleşiyorsa Windows Dosya Gezgini'nde ZIP'e sağ tıkla, **Özellikler → Genel** altında **Engellemeyi kaldır** görünüyorsa seç ve **Uygula**'ya bas. ZIP'i tekrar çıkarıp kurulumu çalıştır. Bu işlem yalnızca seçtiğin indirmeyi etkiler. Kurumsal cihazında imzalı betik politikası uygulanıyorsa yöneticine başvur.
