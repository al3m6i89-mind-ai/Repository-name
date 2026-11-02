# لوحة تطبيقاتي 🛡️

تطبيق أندرويد تدخل فيه بإيميلك وكلمة المرور، وتشوف تطبيقاتك ومستخدمي كل تطبيق، وتقدر:

- **تحذف** حساب مستخدم نهائياً
- **تحظر** المستخدم (مع سبب) أو تفك الحظر
- **تحجب** المستخدم فترة مؤقتة (ساعة، يوم، 3 أيام، أسبوع، شهر، أو عدد أيام تختاره) أو ترفع الحجب
- **تضيف** تطبيقاتك من زر «إضافة تطبيق»، وتبحث وتفلتر المستخدمين حسب الحالة

## تحميل الـ APK
كل دفعة على `main` تبني التطبيق تلقائياً: **Actions** ← آخر تشغيل ← **Artifacts** ← `admin-hub-apk`.

## الوضع التجريبي
بدون أي إعداد: اختر «تجريبي» وادخل بـ `admin@demo.com` وكلمة المرور `123456`. البيانات وهمية وترجع لأصلها عند إعادة فتح التطبيق.

## التشغيل الحقيقي مع Firebase (مجاني)
1. افتح [console.firebase.google.com](https://console.firebase.google.com) وأنشئ مشروع.
2. **Authentication** ← Sign-in method: فعّل **Email/Password** و **Anonymous**.
3. **Authentication** ← Users ← Add user: أضف إيميلك وكلمة مرور (هذا حساب المشرف). انسخ الـ **User UID**.
4. **Firestore Database** ← Create database. ثم أنشئ مجموعة `admins` وفيها مستند معرّفه هو الـ UID اللي نسخته (أي حقل، مثل `email`).
5. **Firestore** ← Rules: الصق محتوى [`firebase/firestore.rules`](firebase/firestore.rules) واضغط Publish.
6. ⚙️ Project settings: انسخ **Project ID** و **Web API Key** (إذا ما ظهر المفتاح، أضف تطبيق ويب للمشروع).
7. في اللوحة اختر «Firebase»، الصق المعرّف والمفتاح، وادخل بإيميلك وكلمة المرور.

## ربط تطبيقاتك باللوحة
لكل تطبيق Flutter:
1. انسخ [`client/admin_hub_client.dart`](client/admin_hub_client.dart) إلى مشروعك (يحتاج `http` و `shared_preferences`).
2. عند فتح التطبيق أو بعد تسجيل الدخول:
   ```dart
   final hub = AdminHubClient(apiKey: 'AIza…', projectId: 'my-apps-12345', appId: 'my-app');
   final s = await hub.check(name: name, email: email);
   if (!s.allowed) {
     // اعرض s.message وامنع استخدام التطبيق
   }
   ```
3. في اللوحة اضغط «إضافة تطبيق» واكتب نفس المعرّف (`my-app`).

المستخدم يظهر في اللوحة أول ما يفتح التطبيق. ما يقدر يفك حظره بنفسه لأن قواعد Firestore تمنعه من تعديل حقول الحظر.

## شكل البيانات
```
admins/{uid}
apps/{appId}                 name, icon, description
apps/{appId}/users/{userId}  name, email, createdAt, lastSeen, banned, suspendedUntil, banReason, …
```
أي حقل إضافي تحفظه في مستند المستخدم (مثل الخطة أو النقاط) يظهر تلقائياً في تفاصيله.

## إضافة خادم غير Firebase
الواجهة تتكلم مع `AdminBackend` في `lib/backend/backend.dart` فقط. لربط Supabase أو خادمك الخاص اكتب كلاس جديد ينفّذها.
