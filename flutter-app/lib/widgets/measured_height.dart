import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Reports its own laid-out height to [onHeight] whenever it changes.
///
/// Used by every screen whose header floats on glass over the content: the
/// scrollable pads itself by this number, so the header covers nothing the
/// rider needs to reach while the content still slides *under* the glass.
///
/// **Why measuring is safe here, when `AppNavBar.insetOf` may not.** The nav
/// bar deliberately reserves a *constant* footprint: its pill shrinks while the
/// rider scrolls, so a measured footprint would shorten every list, which moves
/// `maxScrollExtent`, which moves the scroll position, which decides whether
/// the pill shrinks — a layout driving its own input, and at the margin a
/// twitch. Nothing closes that loop here: a header's height depends on the
/// fold state, the mode toggle, the filter chips and the text scale, and the
/// content's padding cannot reach any of them. So the measure is strictly
/// one-way — it settles one frame after the header changes size and stays
/// settled — and in exchange no height has to be hardcoded and kept in sync,
/// which is what a fixed number would eventually fail to be.
class MeasuredHeight extends SingleChildRenderObjectWidget {
  const MeasuredHeight({super.key, required this.onHeight, required Widget super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasuredHeight).onHeight = onHeight;
  }
}

class _RenderMeasuredHeight extends RenderProxyBox {
  _RenderMeasuredHeight(this.onHeight);

  ValueChanged<double> onHeight;

  /// The last height handed out — so a relayout that changes nothing (every
  /// scroll frame, for one) doesn't schedule a rebuild of the whole screen.
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size.height) return;
    _reported = size.height;
    // setState during layout is illegal; hand the number to the next frame.
    // That one frame of lag is invisible — while the form folds, the list's
    // padding trails the glass by 16 ms — and it is what keeps this a
    // measurement rather than a layout that rewrites itself mid-pass.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(size.height));
  }
}
