# Amaç ve teknik açıklama

Bu araç, Arknights: Endfield’in hikâyesine ve oyun içi metinlerine Türkçe erişim sağlamayı amaçlayan bağımsız bir topluluk çeviri projesidir. OCR kullanmaz: çevirileri metin kimlikleri üzerinden eşleştirerek oyunun İngilizce dil tablosuna yerel olarak uygular. Bu tercih ekran okuma hatalarını önlemeyi ve çeviriyi oyunun kendi metin gösteriminde sunmayı amaçlar. Çevirinin doğruluğu ve bütün ekranlardaki görünümü ayrıca kontrol edilmelidir.

## İki VFS kaynak dosyası ne yapar?

- `bin/reader/EndfieldVfsCrypto.cs`: Oyunun kullandığı VFS paket biçimi için şifreleme ve şifre çözme işlemlerini sağlar. Metin verisini okuyabilmek ve hazırlanan Türkçe tabloyu uygun paket biçimine dönüştürebilmek için kullanılır.
- `bin/reader/EndfieldVfsHash.cs`: VFS paket adları ve konumlarıyla ilgili kimlik/karma hesaplarını yapar. Kaynak tablonun gerçek konumunu belirleyen okuyucunun bir parçasıdır.

Bu dosyalardaki sabit değerler, kişisel hesap şifresi, oturum anahtarı veya kullanıcıdan toplanmış kimlik bilgileri değildir. Kullanılan VFS biçiminin işlemleri için kaynak kodunda bulunan sabitlerdir. İki dosya, aşağıdaki kamuya açık kaynak sürümüyle bayt bayt aynıdır:

- [AnimeStudio Crypto kaynağı](https://github.com/Variante/AnimeStudio/blob/19ae4808c23069bd901e17f962e60a5fb87475c5/AnimeStudio/Endfield/Vfs/EndfieldVfsCrypto.cs)
- [AnimeStudio Hash kaynağı](https://github.com/Variante/AnimeStudio/blob/19ae4808c23069bd901e17f962e60a5fb87475c5/AnimeStudio/Endfield/Vfs/EndfieldVfsHash.cs)

Kaynağın MIT lisansı ve özgün telif bildirimleri [lisans dosyasında](third-party/AnimeStudio-LICENSE.txt) korunmuştur. Bu kaynakların açık olması, oyunun yapımcısının çeviri aracına onay verdiği anlamına gelmez.

## Oyunda ne değiştirilir?

Kurucu, eşleşmesi doğrulanmış İngilizce metin kayıtlarını Türkçe karşılıklarıyla değiştirir; etkilenen veri paketi ile paket indeksindeki uzunluk/konum/bütünlük bilgilerini yeniden hazırlar. Metin kimlikleri, değişkenler ve biçim işaretleri korunur. Özgün dosyalar yerel olarak yedeklenir. Kaynak metni değişmiş kayıtlar otomatik uygulanmaz; bilinmeyen biçimde yazma işlemi durur. Oyun veya ilgili başlatıcı açıkken kurulum yapılmaz.

Bu sürüm süreç içine kod enjekte etmez; bellek düzenleme, savaş otomasyonu veya hile önleme sistemini devre dışı bırakma özelliği içermez. Bu sınırlamalar, dosya değişikliğinin yapımcı tarafından kabul edildiğini göstermez.

## Yapımcı onayı ve hesap riski

Projenin amacı dil engelini aşmaktır; oynanış avantajı sağlamak değildir. Yine de araç oyun dosyalarını değiştirir. Yapımcının dosya bütünlüğü denetimleri veya kullanım kuralları bu değişikliği uygun görmeyebilir. Proje, resmî onay aldığını, hile olarak değerlendirilmeyeceğini ya da yaptırım uygulanmayacağını garanti etmez. Burada yapımcının bu projeyi hile olarak sınıflandırdığına dair bir iddia da yer almaz.

Epic Games aracılığıyla indirilen sürümde çevirinin çalıştığı görüldü. Steam ve doğrudan kurulum sürümlerinde henüz denenmedi. Bu gözlem, gelecekteki güncellemelere veya hesap politikasına ilişkin bir güvence değildir.
