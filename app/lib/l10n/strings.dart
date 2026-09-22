import 'package:flutter/widgets.dart';

enum AppLang { ckb, ar, en }

/// Lightweight three-language table.
///
/// Sorani leads because that is what most users in the region read, and both
/// Sorani and Arabic run right-to-left. A full ARB/gen-l10n setup buys little
/// here - the string count is small and staying in one file makes it easy for
/// a native speaker to review every line at once.
class Strings {
  const Strings(this.lang);

  final AppLang lang;

  static Strings of(BuildContext context) =>
      LangScope.of(context) ?? const Strings(AppLang.ckb);

  bool get isRtl => lang != AppLang.en;
  TextDirection get direction =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  String _pick(String ckb, String ar, String en) => switch (lang) {
        AppLang.ckb => ckb,
        AppLang.ar => ar,
        AppLang.en => en,
      };

  String get langName => _pick('کوردی', 'العربية', 'English');

  // -- app shell -----------------------------------------------------------
  String get appTitle =>
      _pick('دۆزەرەوەی ATM', 'دليل الصراف الآلي', 'Kurdistan ATM');
  String get home => _pick('سەرەکی', 'الرئيسية', 'Home');
  String get nearby => _pick('نزیکەکان', 'الأقرب', 'Nearby');
  String get map => _pick('نەخشە', 'الخريطة', 'Map');
  String get more => _pick('زیاتر', 'المزيد', 'More');
  String get list => _pick('لیست', 'القائمة', 'List');

  // -- home ----------------------------------------------------------------
  String get chooseBank =>
      _pick('بانکەکەت هەڵبژێرە', 'اختر مصرفك', 'Choose your bank');
  String get mainBanks =>
      _pick('بانکە سەرەکییەکان', 'المصارف الرئيسية', 'Main banks');
  String get otherBanks => _pick('بانکەکانی تر', 'مصارف أخرى', 'Other banks');
  String get nearestAtm =>
      _pick('نزیکترین ئەی تی ئێم', 'أقرب صراف آلي', 'Nearest ATM');
  String machines(int n) => _pick('$n ئامێر', '$n جهاز', '$n machines');
  String get seeAll => _pick('هەمووی ببینە', 'عرض الكل', 'See all');
  String get findingNearest => _pick(
        'گەڕان بەدوای نزیکترین...',
        'جارٍ البحث عن الأقرب...',
        'Finding the nearest...',
      );
  String get turnOnLocationForNearest => _pick(
        'خزمەتگوزاری شوێن چالاک بکە بۆ بینینی نزیکترین ئامێر',
        'فعّل خدمة الموقع لرؤية أقرب جهاز',
        'Turn on location to see the nearest machine',
      );

  // -- counts caveat -------------------------------------------------------
  String get countsCaveat => _pick(
        'ژمارەکان ئەو ئامێرانەن کە تا ئێستا تۆمارکراون، نەک تەواوی تۆڕی بانکەکە',
        'الأرقام تمثل الأجهزة المسجلة حتى الآن، وليس كامل شبكة المصرف',
        'Counts are machines recorded so far, not the bank\'s full network',
      );

  // -- more / settings -----------------------------------------------------
  String get language => _pick('زمان', 'اللغة', 'Language');
  String get howItWorks => _pick('چۆنیەتی کارکردن', 'كيف يعمل التطبيق', 'How it works');
  String get howItWorksBody => _pick(
        'شوێنی ئەی تی ئێمەکان لە ناو ئەپەکەدا پاشەکەوت کراون، بۆیە بەبێ ئینتەرنێتیش دەیانبینیت. '
            'بەڵام وێنەی نەخشەکە پێویستی بە ئینتەرنێتە. '
            'زانیاریی بوونی پارە لە ڕاپۆرتی بەکارهێنەرانەوە وەردەگیرێت: تەنها کاتێک دەتوانیت ڕاپۆرت بنێریت '
            'کە لە نزیک ئامێرەکە بیت. هەر ڕاپۆرتێک دوای ١٢ کاتژمێر بەسەردەچێت.',
        'مواقع أجهزة الصراف مدمجة داخل التطبيق فتراها بدون إنترنت. '
            'لكن صور الخريطة نفسها تحتاج إلى اتصال. '
            'حالة توفر النقد تأتي من تقارير المستخدمين: يمكنك الإبلاغ فقط عندما تكون '
            'بجانب الجهاز. صلاحية كل تقرير تنتهي بعد ١٢ ساعة.',
        'ATM locations are bundled inside the app, so you can see them without '
            'internet. The map images themselves still need a connection. '
            'Cash status comes from people: you can only report when you are at '
            'the machine. Every report expires after 12 hours.',
      );
  String get privacy => _pick('پاراستنی نهێنی', 'الخصوصية', 'Privacy');
  String get privacyBody => _pick(
        'پێویست بە دروستکردنی هیچ هەژمارێک ناکات و هیچ زانیارییەکی کەسیت کۆناکرێتەوە. '
            'ئێمە شوێنەکەت پاشەکەوت ناکەین. تەنها کاتێک «دەستپێکردنی ڕێگا» دەکەیت، '
            'شوێنت بۆ سێرڤەری ڕێگای OpenStreetMap دەنێردرێت بۆ دروستکردنی ڕێگاکە.',
        'لا يتطلب التطبيق أي حساب ولا يجمع أي بيانات شخصية. نحن لا نخزّن موقعك. '
            'فقط عند الضغط على «ابدأ المسار» يُرسل موقعك إلى خادم المسارات التابع '
            'لـ OpenStreetMap لرسم الطريق.',
        'There are no accounts and no personal data is collected. We do not '
            'store your location. Only when you start a route is it sent to '
            'OpenStreetMap\'s routing server, so the route can be drawn.',
      );
  String get dataSources => _pick('سەرچاوەکانی داتا', 'مصادر البيانات', 'Data sources');
  String get totalMachines =>
      _pick('کۆی گشتی ئامێرەکان', 'إجمالي الأجهزة', 'Total machines');
  String get citiesCovered =>
      _pick('شار و ناوچەکان', 'المدن والمناطق', 'Cities covered');
  String get freeForever => _pick(
        'ئەم ئەپە بەتەواوی بێبەرامبەرە و هیچ ڕیکلامێکی تێدا نییە',
        'هذا التطبيق مجاني بالكامل وبدون أي إعلانات',
        'This app is free and has no adverts',
      );

  // -- who made it ---------------------------------------------------------
  String get developer => _pick('گەشەپێدەر', 'المطور', 'Developer');

  /// Left in Latin script deliberately: it is how the developer writes his own
  /// name, and transliterating someone's name on their behalf is not ours to
  /// do. Rendered as an isolated left-to-right run so the bidi algorithm does
  /// not reorder it inside a Sorani or Arabic paragraph.
  String get developerName => 'Mahmud Ali';

  String get contactPhone => '07722149070';

  String get anonymousIdLabel =>
      _pick('ناسنامەی نەناسراو', 'المعرّف المجهول', 'Anonymous ID');

  String get anonymousIdNote => _pick(
        'بۆ داواکردنی سڕینەوەی ڕاپۆرتەکانت ئەمە بنێرە. لەخوارەوە کۆپی بکە.',
        'أرسل هذا لطلب حذف تقاريرك. اضغط للنسخ.',
        'Send this to request deletion of your reports. Tap to copy.',
      );

  String get copied => _pick('کۆپی کرا', 'تم النسخ', 'Copied');

  String get privacyPolicy =>
      _pick('سیاسەتی نهێنی', 'سياسة الخصوصية', 'Privacy policy');

  String get deleteMyData =>
      _pick('سڕینەوەی داتاکانم', 'حذف بياناتي', 'Delete my data');

  String get reportAnIssue => _pick(
        'ئەگەر هەر کێشەیەکت لەم ئەپەدا بینی، تکایە پەیوەندی بکە',
        'إذا واجهت أي مشكلة في التطبيق، يرجى التواصل',
        'Please contact me if you find any issue in this app',
      );
  String get allBanks => _pick('هەموو بانکەکان', 'جميع المصارف', 'All banks');
  String get filterByBank =>
      _pick('فلتەرکردن بەپێی بانک', 'تصفية حسب المصرف', 'Filter by bank');
  String get bank => _pick('بانک', 'المصرف', 'Bank');
  String get city => _pick('شار', 'المدينة', 'City');
  String get allCities => _pick('هەموو شارەکان', 'جميع المدن', 'All cities');
  String get chooseCity => _pick('شارێک هەڵبژێرە', 'اختر المدينة', 'Choose city');
  String get aroundMe => _pick('لە دەوروبەرم', 'بالقرب مني', 'Around me');
  String get nothingMatches => _pick(
        'هیچ ئامێرێک بەم فلتەرە نەدۆزرایەوە',
        'لا توجد أجهزة تطابق هذا الفلتر',
        'No machines match this filter',
      );
  String get clearFilters =>
      _pick('سڕینەوەی فلتەرەکان', 'إزالة التصفية', 'Clear filters');
  String get bankNotRecorded => _pick(
        'ئامێرەکانی تر ـ ناوی بانک تۆمارنەکراوە',
        'أجهزة أخرى ـ المصرف غير مسجّل',
        'Other machines - bank not recorded',
      );
  String get mightBeYourBank => _pick(
        'لەوانەیە سەر بە بانکەکەی تۆ بن',
        'قد تكون تابعة لمصرفك',
        'These might still be your bank',
      );
  String get clear => _pick('سڕینەوە', 'مسح', 'Clear');
  String get done => _pick('تەواو', 'تم', 'Done');
  String get cancel => _pick('پاشگەزبوونەوە', 'إلغاء', 'Cancel');
  String get retry => _pick('دووبارە هەوڵبدەرەوە', 'إعادة المحاولة', 'Retry');

  // -- where a machine is --------------------------------------------------

  /// A landmark is a building a short walk away, so "near" is honest.
  String nearPlace(String place) => _pick('نزیک $place', 'بالقرب من $place', 'near $place');

  /// An area is a centroid, not an address - 472 machines share 165 labels -
  /// so this says "in X area" and never "at X", and shows no distance.
  String inArea(String place) =>
      _pick('لە گەڕەکی $place', 'في منطقة $place', 'in $place area');

  /// Title for an unlabelled machine that at least has a location.
  String atmAt(String place) =>
      _pick('ئەی تی ئێم لە $place', 'صراف آلي في $place', 'ATM at $place');

  // -- machine details -----------------------------------------------------
  String get unknownBank => _pick('بانکی دیارینەکراو', 'مصرف غير معروف', 'Unknown bank');
  String get atm => _pick('ئەی تی ئێم', 'صراف آلي', 'ATM');
  String get cardAgent => _pick('بریکاری کارت', 'وكيل بطاقات', 'Card agent');
  String get atBranch => _pick('لە ناو لقدا', 'في الفرع', 'At branch');
  String get open24h => _pick('٢٤ کاتژمێر کراوەیە', 'مفتوح ٢٤ ساعة', 'Open 24h');
  String get driveThrough => _pick('لە ناو ئۆتۆمبێلەوە', 'خدمة السيارات', 'Drive-through');
  String get indoor => _pick('لە ناو باڵەخانەدا', 'داخلي', 'Indoor');
  String get cashIn => _pick('دانانی پارە', 'إيداع نقدي', 'Cash deposit');
  String get currencies => _pick('دراوەکان', 'العملات', 'Currencies');
  String get directions => _pick('ڕێگەپێشاندان', 'الاتجاهات', 'Directions');
  String get share => _pick('هاوبەشکردن', 'مشاركة', 'Share');

  // -- in-app navigation ---------------------------------------------------
  String get startRoute => _pick('دەستپێکردنی ڕێگا', 'بدء المسار', 'Start route');
  String get stopRoute => _pick('وەستاندن', 'إيقاف', 'Stop');
  String get openInMapsApp => _pick(
        'کردنەوە لە Google Maps',
        'فتح في خرائط Google',
        'Open in Google Maps',
      );
  String get findingRoute =>
      _pick('دۆزینەوەی ڕێگا...', 'جارٍ تحديد المسار...', 'Finding route...');
  String get arrived => _pick(
        'گەیشتیتە شوێنی مەبەست ـ ئامێرەکە لێرەیە',
        'لقد وصلت ـ الجهاز هنا',
        'You have arrived',
      );
  String minutesAway(int m) =>
      _pick('$m خولەک', '$m دقيقة', '$m min');

  /// Shown when no road route could be fetched and the line is direct.
  String get straightLineRoute => _pick(
        'هێڵی ڕاستەوخۆ ـ ڕێگای شەقام نەدۆزرایەوە',
        'خط مباشر ـ تعذر العثور على مسار طرق',
        'Direct line - no road route available',
      );

  // -- cash status ---------------------------------------------------------
  String get hasCash => _pick('پارەی تێدایە', 'متوفر نقد', 'Has cash');
  String get noCash => _pick('پارەی تێدا نییە', 'لا يتوفر نقد', 'No cash');
  String get outOfService => _pick('لەکارکەوتووە', 'خارج الخدمة', 'Out of service');
  String get longQueue => _pick('سەرەی درێژ', 'طابور طويل', 'Long queue');
  String get noReports =>
      _pick('هیچ ڕاپۆرتێکی نوێ نییە', 'لا توجد تقارير حديثة', 'No recent reports');

  String get howIsThisAtm =>
      _pick('دۆخی ئەم ئەی تی ئێمە چۆنە؟', 'ما هي حالة هذا الصراف؟', 'How is this ATM?');
  String get reportHelps => _pick(
        'ڕاپۆرتەکەت یارمەتی کەسانی تر دەدات',
        'تقريرك يساعد المستخدمين الآخرين',
        'Your report helps other people',
      );
  String get reportNotSent => _pick(
        'ڕاپۆرتەکە نەنێردرا ـ ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵبدەرەوە',
        'لم يتم إرسال التقرير ـ تحقق من اتصالك وحاول مرة أخرى',
        'Report not sent - check your connection and try again',
      );

  String get thanksForReport =>
      _pick('سوپاس بۆ ڕاپۆرتەکەت', 'شكراً على مشاركتك', 'Thanks for reporting');

  /// Confirms the proximity gate is open. Deliberately not the same sentence as
  /// [reportHelps], which sits directly above it in the sheet.
  String get youAreHere => _pick(
        'تۆ لە نزیک ئەم ئەی تی ئێمەیت',
        'أنت بالقرب من هذا الصراف',
        "You're at this ATM",
      );

  /// Proximity gate - the rule that makes the crowd data trustworthy.
  String get mustBeCloser => _pick(
        'بۆ ناردنی ڕاپۆرت دەبێت لە نزیک ئامێرەکە بیت',
        'يجب أن تكون قرب الصراف لتتمكن من الإبلاغ',
        'You must be at the ATM to report',
      );
  String tooFarAway(int metres) => _pick(
        'تۆ $metres مەتر دووریت',
        'أنت على بعد $metres متر',
        "You're $metres m away",
      );
  String reportCooldown(int minutes) => _pick(
        'تازە ڕاپۆرتت کردووە، دوای $minutes خولەکی تر هەوڵبدەرەوە',
        'لقد أرسلت تقريراً للتو، يمكنك المحاولة بعد $minutes دقيقة',
        'You just reported - try again in $minutes min',
      );

  // -- freshness -----------------------------------------------------------
  String minutesAgo(int m) =>
      _pick('$m خولەک لەمەوبەر', 'منذ $m دقيقة', '$m min ago');
  String hoursAgo(int h) =>
      _pick('$h کاتژمێر لەمەوبەر', 'منذ $h ساعة', '$h h ago');
  String get justNow => _pick('هەر ئێستا', 'الآن', 'Just now');
  String peopleReported(int n) => _pick(
        '$n کەس ڕاپۆرتیان کردووە',
        n == 1 ? 'أبلغ شخص واحد' : 'أبلغ $n أشخاص',
        n == 1 ? '1 person reported' : '$n people reported',
      );

  // -- distance ------------------------------------------------------------
  String metres(int m) => _pick('$m م', '$m م', '$m m');
  String kilometres(String km) => _pick('$km کم', '$km كم', '$km km');

  // -- location disclosure -------------------------------------------------

  /// Shown before the system permission dialog, because Play requires the use
  /// of precise location to be explained in the app's own words first.
  String get whyLocationTitle =>
      _pick('بۆچی شوێنت پێویستە', 'لماذا نحتاج موقعك', 'Why location is needed');

  String get whyLocationBody => _pick(
        'شوێنت بۆ دوو شت بەکاردێت: پیشاندانی نزیکترین ئامێرەکان، و دڵنیابوونەوە '
            'لەوەی لە ماوەی ١٠٠ مەتری ئامێرەکەدایت پێش ڕاپۆرتکردن. ئێمە شوێنت '
            'پاشەکەوت ناکەین.',
        'يُستخدم موقعك لأمرين: عرض أقرب الأجهزة، والتأكد من أنك ضمن ١٠٠ متر من '
            'الجهاز قبل الإبلاغ. نحن لا نخزّن موقعك.',
        'Your location is used for two things: showing the machines nearest to '
            'you, and confirming you are within 100 m of a machine before you '
            'report on it. We do not store your location.',
      );

  String get continueLabel => _pick('بەردەوام بە', 'متابعة', 'Continue');
  String get notNow => _pick('ئێستا نا', 'ليس الآن', 'Not now');

  /// Shown when the user is outside every city in the dataset.
  String get outsideCoverage => _pick(
        'تۆ لە دەرەوەی ناوچەی داپۆشراویت ـ هەولێر پیشان دەدرێت',
        'أنت خارج المنطقة المغطاة ـ يتم عرض أربيل',
        "You're outside the covered area - showing Erbil",
      );

  // -- location ------------------------------------------------------------
  String get findingYou =>
      _pick('دۆزینەوەی شوێنەکەت...', 'جارٍ تحديد موقعك...', 'Finding you...');
  String get locationOff =>
      _pick('خزمەتگوزاری شوێن (GPS) کوژاوەتەوە', 'خدمة الموقع معطلة', 'Location is off');
  String get locationDenied => _pick(
        'مۆڵەتی دەستپێگەیشتن بە شوێن ڕەتکرایەوە',
        'تم رفض إذن الوصول للموقع',
        'Location permission denied',
      );
  String get enableLocation =>
      _pick('چالاککردنی شوێن', 'تفعيل خدمة الموقع', 'Enable location');
  String get noAtmsHere => _pick(
        'هیچ ئامێرێکی ATM لێرە نییە',
        'لا توجد أجهزة صراف آلي هنا',
        'No ATMs here',
      );
  String get showUnlabelled => _pick(
        'ئەو ئامێرانە نیشان بدە کە بانکیان تۆمار نەکراوە',
        'إظهار الأجهزة غير محددة المصرف',
        'Show machines with no bank recorded',
      );

  /// A bare number - no '+' or '?' in the label. Both are bidi-neutral and
  /// would jump to the wrong side of the count inside Sorani or Arabic.
  String hiddenUnlabelled(int n) => _pick(
        '$n ئامێری دیارینەکراو شاراوەتەوە',
        '$n جهاز غير مسجل مخفي',
        '$n unlabelled hidden',
      );

  String get onlyUnlabelledHere => _pick(
        'لێرە تەنها ئامێری دیارینەکراو هەیە ـ دابگرە بۆ پیشاندان',
        'توجد أجهزة غير مسجلة فقط هنا ـ اضغط للإظهار',
        'Only unlabelled machines here - tap to show',
      );

  String get zoomInToSeeAtms => _pick(
        'نەخشەکە نزیک بکەرەوە بۆ بینینی ئامێرەکان',
        'قرّب الخريطة لرؤية الأجهزة',
        'Zoom in to see the machines',
      );

  // -- data provenance -----------------------------------------------------
  /// ODbL requires the licence to be named, not just the project.
  String get dataCredit => _pick(
        'داتاکان لە OpenStreetMap (ODbL) و ماڵپەڕی فەرمیی بانکەکانەوەیە',
        'البيانات من OpenStreetMap (ODbL) ومواقع المصارف الرسمية',
        'Data from OpenStreetMap contributors (ODbL) and bank websites',
      );

  /// Shown while a route is on screen: the route geometry is OSM-derived too,
  /// and the licence requires credit wherever the data appears.
  String get routingCredit => _pick(
        'ڕێگا: OSRM · OpenStreetMap',
        'المسار: OSRM · OpenStreetMap',
        'Routing: OSRM · OpenStreetMap',
      );
  String get reportWrongInfo => _pick(
        'زانیاری هەڵەیە؟',
        'معلومات غير صحيحة؟',
        'Wrong info?',
      );
}

/// Makes the active language available to the whole tree.
class LangScope extends InheritedWidget {
  const LangScope({
    super.key,
    required this.strings,
    required this.onChange,
    required super.child,
  });

  final Strings strings;
  final ValueChanged<AppLang> onChange;

  static Strings? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LangScope>()?.strings;

  static ValueChanged<AppLang>? changerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LangScope>()?.onChange;

  @override
  bool updateShouldNotify(LangScope old) => old.strings.lang != strings.lang;
}
