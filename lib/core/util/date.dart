/// 获取当前DateTime对象
get dtn => DateTime.now();

/// 获取当前时间
get now => DateTime.now().millisecondsSinceEpoch;

/// 获取今天的开始时间
get todayStart => dayStart(DateTime.now());

/// 获取指定日期的开始时间
int dayStart(DateTime d) =>
    d != null ? DateTime(d.year, d.month, d.day).millisecondsSinceEpoch : 0;
