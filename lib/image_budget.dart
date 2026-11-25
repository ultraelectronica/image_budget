/// Display-sized image decoding with an explicit decoded-image cache budget.
library;

export 'src/budgeted_image.dart' show BudgetedImage;
export 'src/decode_target.dart' show DecodeTarget, computeDecodeTarget;
export 'src/image_budget.dart' show ImageBudget;
export 'src/image_budget_stats.dart' show ImageBudgetStats;
export 'src/image_bytes.dart' show decodedBytesFor;
