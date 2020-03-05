// To parse this JSON data, do
//
//     final swap = swapFromJson(jsonString);

import 'dart:convert';

import 'package:komodo_dex/model/order.dart';
import 'package:komodo_dex/model/recent_swaps.dart';

enum Status {
  ORDER_MATCHING,
  ORDER_MATCHED,
  SWAP_ONGOING,
  SWAP_SUCCESSFUL,
  SWAP_FAILED,
  TIME_OUT
}

Swap swapFromJson(String str) {
  final dynamic jsonData = json.decode(str);
  return Swap.fromJson(jsonData);
}

String swapToJson(Swap data) {
  final Map<String, dynamic> dyn = data.toJson();
  return json.encode(dyn);
}

class Swap {
  Swap({this.result, this.status});

  factory Swap.fromJson(Map<String, dynamic> json) => Swap(
        result: ResultSwap.fromJson(json['result']) ?? ResultSwap(),
      );

  ResultSwap result;
  Status status;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'result': result.toJson() ?? ResultSwap().toJson(),
      };

  int compareToSwap(Swap other) {
    int order = 0;
    if (other.result.myInfo != null && result.myInfo != null) {
      order = other.result.myInfo.startedAt.compareTo(result.myInfo.startedAt);
      if (order == 0)
        order =
            result.myInfo.startedAt.compareTo(other.result.myInfo.startedAt);
    }
    return order;
  }

  int compareToOrder(Order other) {
    int order = 0;
    if (result.myInfo != null) {
      order = other.createdAt.compareTo(result.myInfo.startedAt);
      if (order == 0)
        order = result.myInfo.startedAt.compareTo(other.createdAt);
    }

    return order;
  }

  /// Total number of successful steps in the swaps.
  int get steps => result?.successEvents?.length ?? 3;

  /// Current swap step.
  int get step => result?.events?.length ?? 0;
}
