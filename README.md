# 🚗 AIMS-Mobile (Smart Vehicle Plate Voice Recognition & Auditing)

نظام **AIMS-Mobile (رصد ذكي)** هو تطبيق جوال متقدم تم بناؤه باستخدام **Flutter** لرصد وتدقيق لوحات المركبات صوتياً ولحظياً بسرعة فائقة ودقة عالية، مع مطابقتها فورياً مع قوائم المركبات المطلوبة وتوثيق المواقع الجغرافية (GPS).

---

## ⚡ ميزات المحرك الصوتي الفائق (Ultra-Fast Voice Engine)

1. **معالجة محلية فورية (0ms Latency):**
   - محرك `ArabicVoiceNormalizer` المطور يدعم كافة صيغ العامية المصرية والسعودية التي يُخرجها محرك الصوت (مثل: "به" ⬅️ ب، "يه" ⬅️ ي، "طه" ⬅️ ط، "حا" ⬅️ ح، "لا" ⬅️ ل، "ده" ⬅️ د، "زيرو" ⬅️ 0).
   - يتم استخراج وتدقيق اللوحة في أجزاء من الثانية محلياً على الهاتف ودون الحاجة لاتصال بالإنترنت.

2. **الموديل الاحتياطي الذكي (Qwen2.5-1.5B-Instruct):**
   - موديل ذكاء اصطناعي فائق السرعة عبر Hugging Face Router / Groq.
   - يستجيب في أقل من **250ms** لاستخراج وتصحيح اللوحات المشوشة أو المعقدة.
   - تم ضبط الـ Debounce بزمن **250ms** لضمان استمرار الالتقاط دون أي تقطيع أثناء التحدث السريع.

3. **التدقيق والمطابقة الفورية (Instant Audit & Alerts):**
   - تنبيه صوتي وبصري فوري عند مطابقة اللوحة مع سيارة مطلوبة.
   - حفظ إحداثيات الموقع (GPS) وتصدير النتائج إلى ملفات Excel.
   - يدعم الوضع المتصل (Online) والوضع غير المتصل (Offline Speech Pack).

---

## 📁 هيكلية المشروع (Project Architecture)

```text
lib/
├── core/
│   ├── config/          # إعدادات التوكن والمفاتيح (secrets.dart)
│   ├── constants/       # الثوابت والألوان
│   ├── routing/         # التنقل بين الشاشات
│   ├── services/        # خدمات المعالجة الصوتية، الذكاء الاصطناعي، والـ Excel
│   │   ├── ai_plate_refiner.dart               # موديل Qwen2.5
│   │   ├── arabic_voice_normalizer.dart        # محرك الفرز المحلي اللحظي
│   │   ├── speech_to_text_service_mobile.dart  # محرك المايكروفون
│   │   └── location_service.dart               # خدمات الـ GPS
│   ├── theme/           # المظهر العام للتطبيق (Dark/Light)
│   └── widgets/         # العناصر المشتركة
├── data/
│   ├── datasources/     # قاعدة البيانات المحلية (SQLite DatabaseHelper)
│   ├── models/          # نماذج البيانات (CarRecord, VehicleModel)
│   └── repositories/    # مستودعات البيانات
└── presentation/
    ├── providers/       # إدارة الحالة (Provider / ChangeNotifier)
    │   ├── car_record_provider.dart
    │   └── excel_sort_audit_provider.dart
    └── screens/         # شاشات التطبيق الرئيسية
```

---

## 🚀 التشغيل والتثبيت (Getting Started)

### 1. المتطلبات:
* Flutter SDK (3.24+ أو أحدث).
* Dart SDK.
* Android Studio / VS Code.

### 2. التثبيت والتشغيل:
```bash
# تثبيت الحزم
flutter pub get

# تشغيل التطبيق في وضع التطوير
flutter run
```

### 3. ضبط مفتاح Hugging Face (اختياري للـ AI Fallback):
في ملف `lib/core/config/secrets.dart`:
```dart
const String kHuggingFaceToken = 'hf_your_token_here';
```

---

## 📄 الترخيص (License)
جميع الحقوق محفوظة للمطور.
