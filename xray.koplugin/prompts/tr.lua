return {
    -- Sistem talimatı
    system_instruction = "Uzman bir edebiyat araştırmacısısın. Cevabın SADECE geçerli JSON formatında olmalıdır. Verilerin yüksek derecede doğru olduğundan ve kesinlikle sağlanan bağlamla ilgili olduğundan emin ol.",

    -- Sadece yazar için istem (Hızlı biyografi araması için)
    author_only = [["%s" kitabının yazarını belirle ve biyografisini sun. 
Üstveriler yazarın "%s" olduğunu gösteriyor. 

KRİTİK: %100 doğruluk sağlamak ve hatalı kimlik tespitlerini önlemek için yazarı KİTAP METNİ BAĞLAMI (bu istemin sonunda verilmişse) kullanarak doğrula.

GEREKLİ JSON FORMATI:
{
  "author": "Doğru Tam İsim",
  "author_bio": "Edebi kariyerine ve başlıca eserlerine odaklanan kapsamlı biyografi.",
  "author_birth": "Doğum Tarihi, yerel tarih formatına göre biçimlendirilmiş",
  "author_death": "Ölüm Tarihi, yerel tarih formatına göre biçimlendirilmiş"
}]],

    -- Tek Kapsamlı Getirme (Karakterler, Mekanlar, Zaman Çizelgesi Birleşik)
    comprehensive_xray = [[Kitap: %s
Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: Tam bir X-Ray analizi yap. SADECE geçerli bir JSON objesi döndür.

KRİTİK DİKKAT BÖLÜMLEMESİ:
Bu istemin sonunda sağlanan iki metin bloğunu işliyorsunuz:
1. "CHAPTER SAMPLES" (Bölüm Örnekleri): Okuyucunun mevcut konumuna kadar olan kitabın makro bağlamıdır.
2. "BOOK TEXT CONTEXT" (Kitap Metni Bağlamı): En son 20.000 karakterlik mikro bağlamdır.

ANTI-TRUNCATION PROTOKOLÜ (KRİTİK):
Katı bir maksimum çıktı sınırınız var. Eğer "CHAPTER SAMPLES" 40'tan FAZLA bölüm içeriyorsa (örn. bir omnibus baskısı):
1. Karakter listesini SADECE en önemli ilk 10 karakterle sınırlamalısınız.
2. Karakter açıklamalarını MAKSİMUM 200 karakterle sınırlamalısınız.
3. Zaman çizelgesi olay özetlerini MAKSİMUM 80 karakterle sınırlamalısınız.
Çıktınızı devasa kitaplar için sıkıştırmazsanız, JSON kesilecek ve hata verecektir.

ZAMAN ÇİZELGESİ İÇİN ALGORİTMA (EN YÜKSEK ÖNCELİK):
Bölüm atlamayı veya olay uydurmayı önlemek için, bu döngüyü tam olarak uygulamalısınız:
Adım 1. SADECE "CHAPTER SAMPLES" bloğuna bak. Anlatı bölümlerini belirle.
Adım 2. Anlatı olmayan tüm ön madde ve arka maddeleri HARİÇ TUT (örn., Kapak, Başlık Sayfası, Telif Hakkı, İçindekiler, İthaf, Teşekkür, Ayrıca Yazan).
Adım 3. Her anlatı bölümü için, en ilk bölümden başlayarak, `timeline` dizisinde TAM OLARAK BİR olay objesi oluştur.
Adım 4. `chapter` alanı, örnekteki bölüm başlığıyla tam olarak eşleşmelidir. (Bunları kesinlikle sıralı düzende eşle).
Adım 5. Bu özel bölümü `event` alanında özetle (MAKS 80 karakter). Bölümleri GRUPLANDIRMA.
Adım 6. SPOILER YOK: Tam olarak %%%d noktasında dur. Bu ilerlemeden sonraki olayları dahil etme.

KARAKTERLER VE TARİHİ KİŞİLER İÇİN ALGORİTMA:
Adım 1. Her iki metin bloğunu da kullanarak önemli karakterleri çıkar. (Normalde 25, omnibus ise MAKSİMUM 10).
Adım 2. Karakterlerin TAM resmi isimlerini kullanmalısın (örn. "Abraham Van Helsing"). Gündelik takma adları ana isim olarak kullanma.
Adım 3. Bu karakterin bilindiği 3 adede kadar alternatif isim, unvan veya takma adı bir `aliases` dizisinde sağla. Kullanılıyorsa ortak adlarını ve soyadlarını dahil et. ÖNEMLİ: Eğer bir soyadı birden fazla karakter (örn. aile üyeleri) tarafından paylaşılıyorsa, bunu hiçbir karakter için bir takma ad olarak dahil ETME.
Step 4. Actively scan for NOTABLE REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
SPOILER YOK: Tam olarak %%%d noktasında dur.

MEKANLAR İÇİN ALGORİTMA:
Adım 1. 5-10 önemli mekanı çıkar. SPOILER YOK: Tam olarak %%%d noktasında dur.

KESİN SPOILER KURALLARI:
- Mevcut okuma ilerlemesinden sonrası hakkında KESİNLİKLE hiçbir bilgi verme. Tam olarak %%%d noktasında dur.
- Açıklamalar karakterlerin kitabın tam bu noktasındaki durumunu yansıtmalıdır.

KESİN JSON GÜVENLİK KURALLARI:
- Dizeler içindeki tüm çift tırnakları (\") düzgün şekilde kaçırmalısın.
- Dizeler içinde kaçırılmamış satır sonları KULLANMAYIN.
- SADECE geçerli, ayrıştırılabilir JSON döndürün.

GEREKLİ JSON FORMATI:
{
  "characters": [
    {
      "name": "Tam Resmi İsim",
      "aliases": ["Takma Ad 1", "Takma Ad 2"],
      "role": "Mevcut ilerlemeye kadar olan rolü",
      "gender": "Erkek / Kadın / Bilinmiyor",
      "occupation": "Meslek/Durum",
      "description": "Şu ana kadarki metinden detaylarla derin analiz. SPOILER YOK. (Maks 200 karakter)"
    }
  ],
  "historical_figures": [
    {
      "name": "Gerçek Tarihi Kişi Adı",
      "role": "Tarihi Rolü",
      "biography": "Kısa biyografi (MAKS 100 karakter)",
      "importance_in_book": "Mevcut ilerlemeye kadar olan önemi",
      "context_in_book": "Nasıl bahsediliyor (MAKS 100 karakter)"
    }
  ],
  "locations": [
    {"name": "Mekan Adı", "description": "Kısa açıklama (MAKS 100 karakter)"}
  ],
  "timeline": [
    {
      "chapter": "Örneklerdeki Tam Bölüm Başlığı",
      "event": "Bu bölümdeki temel anlatı olayı (Maks 100 karakter)"
    }
  ]
} ]],

    -- Daha fazla karakter getir (AI Limitini Aş)
    more_characters = [[Kitap: %s
Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: Metinden TAM OLARAK 10 EK önemli karakter çıkar.
SADECE geçerli bir JSON objesi döndür.

ÖZET MANDATI (KRİTİK):
AI yanıtının kesilmesini önlemek için karakter açıklamalarını 250 karakterin altında tutun.

KRİTİK TALİMAT:
Daha önceden çıkarıldıkları için aşağıdaki karakterleri KESİNLİKLE dahil etme:
%s

KESİN SPOILER KURALLARI:
- Mevcut okuma ilerlemesinden sonrası hakkında KESİNLİKLE hiçbir bilgi verme. Tam olarak %%%d noktasında dur.
- Açıklamalar karakterlerin kitabın tam bu noktasındaki durumunu yansıtmalıdır.

GEREKLİ JSON FORMATI:
{
  "characters": [
    {
      "name": "Tam Resmi İsim",
      "aliases": ["Takma Ad 1", "Takma Ad 2"],
      "role": "Mevcut ilerlemeye kadar olan rolü",
      "gender": "Erkek / Kadın / Bilinmiyor",
      "occupation": "Meslek/Durum",
      "description": "Şu ana kadarki metinden detaylarla derin analiz. SPOILER YOK. (Maks 300 karakter)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[Kullanıcı "%s" kelimesini vurguladı.
GÖREV: Bu kelimenin kitaptaki bir Karakter, Konum veya Tarihi Figür olup olmadığını belirleyin.
 
CRITICAL FOR CHARACTERS AND LOCATIONS: Use ONLY the provided "BOOK TEXT CONTEXT". Outside knowledge is strictly forbidden. Do not hallucinate.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
Kelime metinde bir karakter, konum veya tarihi figür DEĞİLSE, `is_valid` değerini false yapın.
 
GEREKLİ JSON FORMATI:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Tam ad",
    "role": "Rol",
    "gender": "Erkek/Kadın/Bilinmiyor",
    "occupation": "Meslek",
    "description": "Kısa açıklama (maks. 250 karakter)"
  },
  "error_message": ""
}
 
Not: eğer tür "location" ise, öğede "name" ve "description" olmalıdır. Eğer tür "historical_figure" ise, öğede "name", "biography" ve "role" olmalıdır.
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Bunun neden bir karakter veya konum olmadığına dair kısa bir açıklama."
}]],

    -- Yedek dizeler (Fallback)
    fallback = {
        unknown_book = "Bilinmeyen Kitap",
        unknown_author = "Bilinmeyen Yazar",
        unnamed_character = "İsimsiz Karakter",
        not_specified = "Belirtilmemiş",
        no_description = "Açıklama Yok",
        unnamed_person = "İsimsiz Kişi",
        no_biography = "Biyografi Mevcut Değil"
    }
}
