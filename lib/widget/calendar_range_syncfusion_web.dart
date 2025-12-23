import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

class CalendarRangeSyncfusionWeb extends StatelessWidget {
  final void Function(DateTime start, DateTime end) onSelected;

  const CalendarRangeSyncfusionWeb({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      child: SfDateRangePicker(
        view: DateRangePickerView.month,
        selectionMode: DateRangePickerSelectionMode.range,
        enableMultiView: true, // ✅ 두 달 표시
        showActionButtons: false,
        onSelectionChanged: (DateRangePickerSelectionChangedArgs args) {
          if (args.value is PickerDateRange) {
            final start = args.value.startDate;
            final end = args.value.endDate;

            if (start != null && end != null) {
              onSelected(start, end); // ✅ 두 날짜가 모두 선택된 경우만 적용
            }
          }
        },
      )
    );
  }
}
