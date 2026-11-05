# Manuel kurulum ve güncelleme

Bu yol, her aşamayı görerek çeviriyi hazırlayıp kurmak içindir. Yama klasörü oyun klasörünün dışında kalır. Böylece resmi oyun güncellemesi çeviri kataloğunu ve yerel yedekleri kaldırmaz.

## Hazırlık

Epic Games, Steam veya doğrudan resmî PC kurulumunu kullan. Resmi başlatıcıda bekleyen güncellemeyi tamamladıktan sonra Endfield'i ve oyuna ait başlatıcıyı kapat. Epic Games Launcher'ın arka planda açık olması tek başına oyunun güncelleme yaptığı anlamına gelmez; araç uygulamadan önce dosyaları ayrıca denetler.

Paket klasöründe PowerShell aç. Komutlarda `pwsh`, PowerShell 7.5+ sürümünü çalıştırır. Python 3.9 veya üzeri erişilebilir olmalıdır.

## Kurulumu kontrol et

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Check
```

Oyun otomatik bulunamazsa `Endfield_Data` klasörünü belirt:

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Check -GameData 'D:\Oyunlar\Arknights Endfield\Endfield_Data'
```

Sonraki komutlarda da aynı `-GameData` seçeneğini kullan. Oyunun üst kurulum klasörünü veya başlatıcının sürüm klasörünü bu değer yerine verme.

## Çalışma kopyasını hazırla

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Prepare
```

Bu aşama güncel indekslerden İngilizce metnin yerini belirler. Katalog kayıtlarını yeni özgün kaynakla karşılaştırır; kaynağı veya bağlamı değişmiş olanları inceleme listesine ayırır. Uygun karşılıkları kopyalarda derleyip paket bütünlüğünü denetler. Oyun hedefleri değiştirilmez.

Hazırlık raporundaki oyun sürümünü, uygulanabilir kayıt sayısını ve inceleme gerektiren kayıtları kontrol et. Yalnız hazır bir `id → Türkçe` dosyası, kaynak kimliği ve özeti doğrulanmadan farklı oyun sürümüne uygulanmaz.

## Yedekli kurulumu uygula

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Apply
```

`Apply` hazırlığı ve doğrulamayı kendi akışında yeniden denetler. Güncel sürümün özgün dosyalarını yedekler; dosyalar incelemeden sonra değişmişse yazmadan durur. Kurulumdan sonra kurulu paket yeniden okunur ve beklenen içerikle karşılaştırılır. Başarılı sonuç ve dosya özetleri yerel uygulama kaydına yazılır.

Fiziksel `.chk` ve `.blc` dosyalarını Explorer ile tek tek kopyalamak bu akışın yerine geçmez. Aynı sürüm numarası görünse bile kaynak özeti, dosya konumu veya paket içeriği değişebilir. Özellikle eski sürümün blok indeksini yeni kurulumun üzerine kopyalama.

## Oyunda kontrol et

Otomatik sürüm kontrolü için `Turkce-Ile-Baslat.cmd` girişini kullan; bu giriş resmî başlatıcıyı açar. Metin dili English / İngilizce olarak kalsın. Menüleri, Türkçe harfleri, satır taşmalarını ve değişkenli bildirimleri kontrol et. Hikâyede sorun bildirirken görev veya konuşma bağlamını da ekle.

Başlatıcı arada yeni bir içerik güncellemesi yaparsa önce bu güncellemenin bitmesini bekle; oyunu ve oyuna ait başlatıcıyı kapattıktan sonra `Check` ve `Apply` adımlarını tekrarla.

## Aynı sürümün özgün dosyalarına dön

```powershell
pwsh -NoProfile -File .\Yenile-Ceviri.ps1 -Mode Restore
```

Geri alma, yerel uygulama kaydındaki sürüm ve dosya özetlerini esas alır. Hedefler sonradan değişmişse durur. Bu durumda eski yedeği elle zorlamak yerine resmi başlatıcıdaki doğrulama veya onarım yolunu kullan; ardından yama durumunu yeniden kontrol et.

## Sorunu bildir

Komutun `Check`, `Prepare`, `Apply` veya `Restore` aşamasında olduğunu, oyun sürümünü ve hata metnini belirt. Paylaşmadan önce rapordaki kullanıcı adını ve kişisel klasör yollarını kaldır. Hesap bilgisi, giriş kodu veya oyun ikilileri ekleme.

## Platformu açıkça seç

Birden fazla kurulum bulunduysa:

```powershell
pwsh -NoProfile -File .\Kur.ps1 -Platform Steam -GameData 'D:\SteamLibrary\steamapps\common\Arknights Endfield\Endfield_Data' -CreateShortcut
```

Epic için `-Platform Epic`, doğrudan indirme için `-Platform Direct` kullanılır. Örnek yollar sabit zorunluluk değildir; kendi `Endfield_Data` konumunu belirt. Doğrudan kurulumda resmî başlatıcı otomatik bulunmazsa yerel `config.json` içindeki `OfficialLauncher` alanını doğru resmî yürütülebilir dosyaya ayarla.

Kurucu yürütme politikasını veya güvenlik yazılımını değiştirmez. Betik sistem politikan tarafından engellenirse hata metnini esas al; kurum politikasını aşma. [PowerShell resmî kurulum bilgisi](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows), [Python resmî indirme](https://www.python.org/downloads/windows/).
