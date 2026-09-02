/// Legacy location for the application theme.
///
/// The design system lives in `lib/theme/`. This file only re-exports it so the
/// old import path (`themes/app_theme.dart`) keeps compiling; it will be
/// removed once every call site imports `theme/app_theme.dart`.
library;

export '../theme/app_theme.dart';
