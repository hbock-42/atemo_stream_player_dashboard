import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

enum AppTextStyleName { display, title, body, caption }

class AppText extends StatelessWidget {
  const AppText(
    this.text, {
    super.key,
    this.style = AppTextStyleName.body,
    this.color,
    this.maxLines,
    this.align = TextAlign.start,
  });

  final String text;
  final AppTextStyleName style;
  final Color? color;
  final int? maxLines;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final typography = AppTheme.of(context).typography;
    final base = switch (style) {
      AppTextStyleName.display => typography.display,
      AppTextStyleName.title => typography.title,
      AppTextStyleName.body => typography.body,
      AppTextStyleName.caption => typography.caption,
    };

    return Text(
      text,
      style: color == null ? base : base.copyWith(color: color),
      maxLines: maxLines,
      textAlign: align,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}
