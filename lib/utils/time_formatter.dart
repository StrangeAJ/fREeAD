import 'package:intl/intl.dart';

class TimeFormatter {
  static String formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    // Same day - show relative time
    if (difference.inDays == 0) {
      if (difference.inHours > 0) {
        return difference.inHours == 1
            ? '1 hr. ago'
            : '${difference.inHours} hrs. ago';
      } else if (difference.inMinutes > 0) {
        return difference.inMinutes == 1
            ? '1 min. ago'
            : '${difference.inMinutes} mins. ago';
      } else {
        return 'Just now';
      }
    }

    // Yesterday
    if (difference.inDays == 1) {
      return 'yesterday';
    }

    // Same year - show day and month
    if (dateTime.year == now.year) {
      return DateFormat('d MMMM').format(dateTime);
    }

    // Different year - show day, month and year
    return DateFormat('d MMMM, yyyy').format(dateTime);
  }
}
