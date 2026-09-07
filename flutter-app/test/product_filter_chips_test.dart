import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:besser_bahn/providers/journey_search_provider.dart';

/// The product chips above the search results.
///
/// They all start selected, so a plain toggle could only ever take one away —
/// "only Fernverkehr" meant tapping five other chips off. The first tap now
/// isolates instead.
void main() {
  late ProviderContainer container;
  JourneySearchNotifier notifier() =>
      container.read(journeySearchProvider.notifier);
  Set<ProductCategory> products() =>
      container.read(journeySearchProvider).products;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('everything is on to start with', () {
    expect(products(), ProductCategory.values.toSet());
  });

  test('the first tap shows only that category', () {
    notifier().toggleProduct(ProductCategory.fern);
    expect(products(), {ProductCategory.fern});
  });

  test('a second category joins the selection', () {
    notifier().toggleProduct(ProductCategory.fern);
    notifier().toggleProduct(ProductCategory.sbahn);
    expect(products(), {ProductCategory.fern, ProductCategory.sbahn});
  });

  test('tapping a selected one of several removes just that one', () {
    notifier().toggleProduct(ProductCategory.fern);
    notifier().toggleProduct(ProductCategory.sbahn);
    notifier().toggleProduct(ProductCategory.fern);
    expect(products(), {ProductCategory.sbahn});
  });

  test('tapping the last remaining category restores all', () {
    notifier().toggleProduct(ProductCategory.regional);
    expect(products(), {ProductCategory.regional});
    notifier().toggleProduct(ProductCategory.regional);
    expect(products(), ProductCategory.values.toSet());
  });

  test('Alle resets the filter', () {
    notifier().toggleProduct(ProductCategory.bus);
    notifier().setAllProducts();
    expect(products(), ProductCategory.values.toSet());
  });

  test('a full selection asks the backend for ALL, a subset for its codes', () {
    expect(ProductCategory.codesFor(ProductCategory.values.toSet()), ['ALL']);
    expect(
      ProductCategory.codesFor({ProductCategory.sbahn}),
      ProductCategory.sbahn.vendoCodes,
    );
  });
}
