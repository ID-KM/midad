import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';

/// غلاف افتراضي بتدرج بني/ذهبي — يُستخدم عند غياب صورة الغلاف.
/// سيكون أيضاً بديل الاستخراج التلقائي في Step 3.
class BookCoverPlaceholder extends StatelessWidget {
  final String title;
  final Color accent;
  final double width;
  final double height;

  const BookCoverPlaceholder({
    super.key,
    required this.title,
    required this.accent,
    this.width = 64,
    this.height = 92,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, AppColors.darkBrown],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkBrown.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // أيقونة كتاب خفيفة في الخلفية
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.bookOpen,
                size: width * 0.42,
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
          ),
          // الحرف الأول من العنوان أسفل الغلاف
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: Text(
              title.characters.first,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.warmYellow,
                fontSize: height * 0.2,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
