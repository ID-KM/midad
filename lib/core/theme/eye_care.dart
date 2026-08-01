import 'dart:ui';

/// فلتر "حماية العين" — طبقة دافئة (Sepia Tint) فوق كامل التطبيق.
///
/// عند الشدة 0 → لا تأثير (هوية). عند 1 → sepia كامل.
/// المصفوفة تمزج مصفوفة sepia القياسية مع مصفوفة الهوية حسب الشدة.
ColorFilter sepiaColorFilter(double intensity) {
  final i = intensity.clamp(0.0, 1.0);

  // مصفوفة sepia القياسية (معاملات معروفة لتدرج بني دافئ)
  const sr = 0.393, sg = 0.769, sb = 0.189;
  const dr = 0.349, dg = 0.686, db = 0.168;
  const er = 0.272, eg = 0.534, eb = 0.131;

  // مزج خطي: identity + (sepia - identity) * i
  final r0 = 1 + (sr - 1) * i, r1 = sg * i, r2 = sb * i;
  final g0 = dr * i, g1 = 1 + (dg - 1) * i, g2 = db * i;
  final b0 = er * i, b1 = eg * i, b2 = 1 + (eb - 1) * i;

  return ColorFilter.matrix([
    r0, r1, r2, 0, 0, //
    g0, g1, g2, 0, 0, //
    b0, b1, b2, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}
