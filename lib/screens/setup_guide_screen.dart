import 'package:flutter/material.dart';

import '../ui/theme.dart';

class SetupGuideScreen extends StatelessWidget {
  final bool serviceAccount;
  const SetupGuideScreen({super.key, this.serviceAccount = true});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: serviceAccount ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('شرح الإعداد'),
          bottom: const TabBar(
            labelStyle: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
            tabs: [Tab(text: 'حساب الخدمة'), Tab(text: 'إيميل ومرور'), Tab(text: 'وش يشتغل؟')],
          ),
        ),
        body: const TabBarView(children: [_SaGuide(), _HubGuide(), _WhatWorks()]),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String body;
  const _Step(this.n, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: cs.onSurfaceVariant, height: 1.6)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _Note(this.text, {this.color = Brand.info, this.icon = Icons.info_outline_rounded});

  @override
  Widget build(BuildContext context) => Card(
        color: color.withValues(alpha: .08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.6))),
          ]),
        ),
      );
}

class _SaGuide extends StatelessWidget {
  const _SaGuide();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: const [
        _Note('هذي الطريقة تعطيك تحكم كامل بمستخدمي أي مشروع Firebase عندك، وتقدر تكررها لكل مشروع (كل حساب Google).'),
        SizedBox(height: 12),
        _Step(1, 'افتح Firebase', 'من متصفح الجوال أو الكمبيوتر افتح console.firebase.google.com وادخل بحساب Google اللي فيه التطبيق.'),
        _Step(2, 'اختر المشروع', 'اضغط على مشروع التطبيق اللي تبي تتحكم بمستخدميه.'),
        _Step(3, 'إعدادات المشروع', 'اضغط رمز الترس ⚙️ بجانب «Project Overview» ثم «Project settings».'),
        _Step(4, 'حسابات الخدمة', 'افتح تبويب «Service accounts». (في الجوال حرّك شريط التبويبات لليسار لين يظهر.)'),
        _Step(5, 'نزّل المفتاح', 'اضغط «Generate new private key» ثم «Generate key». بينزل ملف ينتهي بـ .json على جهازك.'),
        _Step(6, 'اربطه باللوحة', 'في اللوحة: التطبيقات ← «ربط حساب» ← «ملف حساب الخدمة» ← «اختر ملف المفتاح» واختر الملف، اكتب اسم للحساب واضغط «ربط الحساب».'),
        _Step(7, 'كرر لكل مشروع', 'لو عندك تطبيقات في حسابات Firebase ثانية، سجّل خروج من Firebase وادخل بالحساب الثاني وكرر الخطوات. كل الحسابات تظهر في نفس اللوحة.'),
        SizedBox(height: 4),
        _Note('الملف هذا مثل المفتاح الرئيسي لمشروعك: لا ترسله لأحد ولا ترفعه على GitHub. إذا ضاع جوالك احذف المفتاح من نفس الصفحة في Firebase.',
            color: Brand.danger, icon: Icons.shield_outlined),
      ]);
}

class _HubGuide extends StatelessWidget {
  const _HubGuide();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: const [
        _Note('هذي الطريقة للتطبيقات الجديدة اللي تضيف لها ملف الربط admin_hub_client.dart. تدخل فيها بإيميل وكلمة مرور.'),
        SizedBox(height: 12),
        _Step(1, 'أنشئ مشروع', 'من console.firebase.google.com اضغط «Create project».'),
        _Step(2, 'فعّل الدخول', 'Authentication ← Get started ← فعّل «Email/Password» و«Anonymous».'),
        _Step(3, 'حساب المشرف', 'Authentication ← Users ← Add user: اكتب إيميلك وكلمة مرور. انسخ الـ User UID.'),
        _Step(4, 'قاعدة البيانات', 'Firestore Database ← Create database. ثم Start collection باسم admins، والـ Document ID هو الـ UID، وأضف حقل email.'),
        _Step(5, 'القواعد', 'Firestore ← Rules: الصق محتوى الملف firebase/firestore.rules من المستودع واضغط Publish.'),
        _Step(6, 'المعرّف والمفتاح', 'Project settings ← General: انسخ «Project ID» و«Web API Key».'),
        _Step(7, 'اربط', 'في اللوحة: ربط حساب ← «إيميل وكلمة مرور»، الصق المعرّف والمفتاح واكتب إيميلك وكلمة المرور.'),
      ]);
}

class _WhatWorks extends StatelessWidget {
  const _WhatWorks();

  @override
  Widget build(BuildContext context) {
    Widget row(String t, bool now) => ListTile(
          dense: true,
          leading: Icon(now ? Icons.check_circle_rounded : Icons.code_rounded, color: now ? Brand.success : Brand.warning),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(now ? 'يشتغل فوراً بدون تعديل تطبيقك' : 'يحتاج تطبيقك يقرأه (سطرين كود)'),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      const _Note('مع ملف حساب الخدمة، هذي الإجراءات وكيف تأثر على تطبيقاتك الحالية:'),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          row('الحظر الدائم (يتعطل الحساب ويمنع دخوله)', true),
          row('الحجب المؤقت (يتعطل لين تنتهي المدة)', true),
          row('حذف الحساب', true),
          row('تسجيل خروج إجباري من كل الأجهزة', true),
          row('تعديل الاسم والإيميل والجوال والتوثيق', true),
          row('عرض كل التفاصيل والمحتوى وحذف المنشورات والقصص', true),
          row('الرسائل والتحذيرات', false),
          row('تقييد الميزات والدور والخطة والنقاط', false),
        ]),
      ),
      const SizedBox(height: 12),
      const _Note(
        'الإجراءات اللي تحتاج كود تنحفظ في «custom claims» للمستخدم. تطبيقك يقرأها من getIdTokenResult().claims '
        'مثل: claims["restrictions"] أو claims["adminMessage"]. أقدر أضيفها لتطبيقك إذا عطيتني كوده.',
        color: Brand.warning,
        icon: Icons.lightbulb_outline_rounded,
      ),
      const SizedBox(height: 8),
      const _Note('الحجب المؤقت: لما تنتهي المدة، الحساب يرجع يشتغل تلقائياً أول ما تفتح اللوحة.'),
    ]);
  }
}
