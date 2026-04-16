return {
    -- Specialized section for Characters and Historical Figures
    character_section = [[Kitap: "%s" - Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: En önemli 15-25 karakteri ve %%%d noktasına kadar adı geçen 3-7 gerçek dünya tarihi kişisini listeleyin.

KURALLAR:
1. KARAKTER DERİNLİĞİ: Her karakter için, %%%d noktasına kadar olan tüm geçmişini ve rolünü kapsayan kapsamlı bir analiz (250-300 karakter) sağlayın.
2. SPOILER KONTROLÜ: Kesinlikle %%%d noktasından sonrası hakkında bilgi vermeyin.
3. KALİTE: Anlatıdaki öneme odaklanın.

GEREKLİ JSON FORMATI:
{
  "characters": [
    {
      "name": "Tam Adı",
      "role": "%%%d noktasındaki rolü",
      "gender": "Cinsiyet",
      "occupation": "Meslek",
      "description": "Kapsamlı geçmiş/analiz (250-300 karakter). SPOILER İÇERMEZ."
    }
  ],
  "historical_figures": [
    {
      "name": "Adı",
      "role": "Rolü",
      "biography": "Kısa biyografi (MAKS 150 karakter)",
      "importance_in_book": "%%%d noktasındaki önemi",
      "context_in_book": "Bağlam"
    }
  ]
}]],

    -- Specialized section for Locations
    location_section = [[Kitap: "%s" - Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: %%%d noktasına kadar ziyaret edilen veya adı geçen 5-10 önemli mekanı listeleyin.

KURALLAR:
1. SPOILER YOK: %%%d noktasından sonra gerçekleşen mekanları veya olayları belirtmeyin.
2. ÖZET: Açıklamalar MAKSİMUM 150 karakter olmalıdır.

GEREKLİ JSON FORMATI:
{
  "locations": [
    {"name": "Mekan", "description": "Kısa açıklama (MAKS 150 karakter)", "importance": "%%%d noktasındaki önemi"}
  ]
}]],

    -- Specialized section for Timeline
    timeline_section = [[Kitap: "%s" - Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: %%%d noktasına kadar olan temel anlatı olaylarının kronolojik bir zaman çizelgesini oluşturun.

KURALLAR:
1. KAPSAM: %%%d noktasına kadar olan HER anlatı bölümü için 1 temel vurgu sağlayın.
2. HARİÇ TUTMA: İçindekiler, İthaf veya Önsöz kısımlarını YOK SAYIN.
3. KISALIK: Her olay açıklaması MAKSİMUM 120 karakter OLMALIDIR.
4. SPOILER YOK: Tam olarak %%%d noktasında durun.

GEREKLİ JSON FORMATI:
{
  "timeline": [
    {"event": "Temel anlatı olayı (MAKS 120 karakter)", "chapter": "Bölüm Adı/Numarası", "importance": "Yüksek/Düşük"}
  ]
}]],
}
