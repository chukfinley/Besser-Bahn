import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reisende.dart';
import '../models/split_ticket.dart';
import '../models/transfer_profile.dart';

class AppSettings {
  final BahnCardType bahnCard;
  final bool hasDeutschlandTicket;
  final int age;
  final int apiDelayMs;

  /// The "Reisende & Klasse" selection driving the connection search
  /// (passengers, ages, bike/dog, class, BahnCards, Schwerbehindertenausweis).
  /// Seeded from [bahnCard]/[hasDeutschlandTicket] on first run, then edited
  /// per trip from the search form and persisted.
  final SearchParty searchParty;

  /// True once the rider has explicitly edited the party (the advanced
  /// "Reisende" sheet). After that, nothing auto-re-seeds it — a DB-account
  /// restore or a BahnCard change must never wipe "1 Erwachsener + 1 Kind" back
  /// to a lone adult (#43).
  final bool partyCustomized;

  /// When true, the in-train Träwelling check-in button checks in immediately
  /// (origin → destination, [trwlVisibility]) without the confirm sheet.
  final bool trwlAutoCheckin;

  /// Default visibility for app check-ins (TrwlVisibility.value: 0=öffentlich,
  /// 1=nicht gelistet, 2=nur Follower, 3=privat, 4=angemeldete). Defaults to
  /// private — check-ins stay between you and Träwelling unless you opt out.
  final int trwlVisibility;

  /// Whether to schedule offline trip reminders ("In 30 Min fährt dein Zug",
  /// boarding & Umstieg pings) for saved upcoming trips.
  final bool remindersEnabled;

  /// Lead time in minutes for the "mach dich bereit" reminder before departure.
  final int reminderLeadMinutes;

  /// Whether to also ping shortly before each connecting train departs.
  final bool transferAlerts;

  /// "Ankunfts-Wecker": ping ~10 Min and ~5 Min before reaching the final
  /// destination so a dozing rider doesn't miss the stop. Scheduled offline
  /// from the saved arrival time, like the departure reminders.
  final bool arrivalAlertEnabled;

  /// Upgrade the 5-Min arrival ping to a loud, looping alarm (alarm volume,
  /// full-screen) that keeps ringing until stopped. Off by default — opt-in,
  /// since it's deliberately hard to sleep through.
  final bool arrivalAlarmSound;

  /// GPS journey companion: tracks a watched journey in the background, warns
  /// near the destination and can infer a likely not-yet-reported delay from
  /// timetable + position. [arrivalAlarmSound] separately decides whether the
  /// destination warning becomes a real ringing alarm.
  final bool exitAlarmEnabled;

  /// How fast this rider changes trains. Scales how tight a transfer is judged
  /// to be, everywhere the app judges one (#11, point 7). Local-only.
  final TransferProfile transferProfile;

  /// Rephrase DB's disruption/running notes into plainer German (#74). Off by
  /// default — the original wording stays unless the rider asks for simpler.
  final bool plainLanguage;

  /// The live status-bar / Now-Bar chip shows the number of stops to the exit
  /// instead of the minutes (#76). Off by default → minutes.
  final bool liveChipStops;

  const AppSettings({
    this.bahnCard = BahnCardType.none,
    this.hasDeutschlandTicket = false,
    this.age = 30,
    this.apiDelayMs = 400,
    this.trwlAutoCheckin = false,
    this.trwlVisibility = 3,
    this.remindersEnabled = true,
    this.reminderLeadMinutes = 30,
    this.transferAlerts = true,
    this.arrivalAlertEnabled = true,
    this.arrivalAlarmSound = false,
    this.exitAlarmEnabled = false,
    this.transferProfile = TransferProfile.normal,
    this.searchParty = const SearchParty(),
    this.partyCustomized = false,
    this.plainLanguage = false,
    this.liveChipStops = false,
  });

  AppSettings copyWith({
    BahnCardType? bahnCard,
    bool? hasDeutschlandTicket,
    int? age,
    int? apiDelayMs,
    bool? trwlAutoCheckin,
    int? trwlVisibility,
    bool? remindersEnabled,
    int? reminderLeadMinutes,
    bool? transferAlerts,
    bool? arrivalAlertEnabled,
    bool? arrivalAlarmSound,
    bool? exitAlarmEnabled,
    TransferProfile? transferProfile,
    SearchParty? searchParty,
    bool? partyCustomized,
    bool? plainLanguage,
    bool? liveChipStops,
  }) {
    return AppSettings(
      bahnCard: bahnCard ?? this.bahnCard,
      hasDeutschlandTicket: hasDeutschlandTicket ?? this.hasDeutschlandTicket,
      age: age ?? this.age,
      apiDelayMs: apiDelayMs ?? this.apiDelayMs,
      trwlAutoCheckin: trwlAutoCheckin ?? this.trwlAutoCheckin,
      trwlVisibility: trwlVisibility ?? this.trwlVisibility,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
      transferAlerts: transferAlerts ?? this.transferAlerts,
      arrivalAlertEnabled: arrivalAlertEnabled ?? this.arrivalAlertEnabled,
      arrivalAlarmSound: arrivalAlarmSound ?? this.arrivalAlarmSound,
      exitAlarmEnabled: exitAlarmEnabled ?? this.exitAlarmEnabled,
      transferProfile: transferProfile ?? this.transferProfile,
      searchParty: searchParty ?? this.searchParty,
      partyCustomized: partyCustomized ?? this.partyCustomized,
      plainLanguage: plainLanguage ?? this.plainLanguage,
      liveChipStops: liveChipStops ?? this.liveChipStops,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final bahnCard = BahnCardType.values[prefs.getInt('bahnCard') ?? 0];
    final dTicket = prefs.getBool('deutschlandTicket') ?? false;
    state = AppSettings(
      bahnCard: bahnCard,
      hasDeutschlandTicket: dTicket,
      age: prefs.getInt('age') ?? 30,
      apiDelayMs: prefs.getInt('apiDelayMs') ?? 400,
      trwlAutoCheckin: prefs.getBool('trwlAutoCheckin') ?? false,
      trwlVisibility: prefs.getInt('trwlVisibility') ?? 3,
      remindersEnabled: prefs.getBool('remindersEnabled') ?? true,
      reminderLeadMinutes: prefs.getInt('reminderLeadMinutes') ?? 30,
      transferAlerts: prefs.getBool('transferAlerts') ?? true,
      arrivalAlertEnabled: prefs.getBool('arrivalAlertEnabled') ?? true,
      arrivalAlarmSound: prefs.getBool('arrivalAlarmSound') ?? false,
      exitAlarmEnabled: prefs.getBool('exitAlarmEnabled') ?? false,
      transferProfile: TransferProfile.fromName(
        prefs.getString('transferProfile'),
      ),
      // First run (no stored party): seed from the single-card settings so the
      // search behaves exactly as before until the user customises the party.
      searchParty:
          SearchParty.tryDecode(prefs.getString('searchParty')) ??
          SearchParty.fromSettings(bahnCard, dTicket),
      partyCustomized: prefs.getBool('partyCustomized') ?? false,
      plainLanguage: prefs.getBool('plainLanguage') ?? false,
      liveChipStops: prefs.getBool('liveChipStops') ?? false,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bahnCard', state.bahnCard.index);
    await prefs.setBool('deutschlandTicket', state.hasDeutschlandTicket);
    await prefs.setInt('age', state.age);
    await prefs.setInt('apiDelayMs', state.apiDelayMs);
    await prefs.setBool('trwlAutoCheckin', state.trwlAutoCheckin);
    await prefs.setInt('trwlVisibility', state.trwlVisibility);
    await prefs.setBool('remindersEnabled', state.remindersEnabled);
    await prefs.setInt('reminderLeadMinutes', state.reminderLeadMinutes);
    await prefs.setBool('transferAlerts', state.transferAlerts);
    await prefs.setBool('arrivalAlertEnabled', state.arrivalAlertEnabled);
    await prefs.setBool('arrivalAlarmSound', state.arrivalAlarmSound);
    await prefs.setBool('exitAlarmEnabled', state.exitAlarmEnabled);
    await prefs.setString('transferProfile', state.transferProfile.name);
    await prefs.setString('searchParty', state.searchParty.encode());
    await prefs.setBool('partyCustomized', state.partyCustomized);
    await prefs.setBool('plainLanguage', state.plainLanguage);
    await prefs.setBool('liveChipStops', state.liveChipStops);
  }

  void setPlainLanguage(bool value) {
    state = state.copyWith(plainLanguage: value);
    _save();
  }

  void setLiveChipStops(bool value) {
    state = state.copyWith(liveChipStops: value);
    _save();
  }

  /// "My BahnCard" from the simple settings path: carried into the party
  /// in place (#75), so a Halbtax, an SBA or a second traveller set in the
  /// advanced sheet survives changing the card — re-seeding the whole party
  /// used to wipe them.
  void setBahnCard(BahnCardType card) {
    final cardReduction = Reduction.byKey(card.vendoErmaessigung);
    final travelers = state.searchParty.travelers.map((t) {
      if (t.typ.isPerson) {
        return t.copyWith(bahnCard: cardReduction);
      }
      return t;
    }).toList();

    state = state.copyWith(
      bahnCard: card,
      searchParty: state.searchParty.copyWith(
        // A 1st-class card implies 1st class; a 2nd-class one must NOT demote a
        // rider who deliberately chose 1st in the party sheet. Class is the
        // party's answer, and switching cards is not a statement about it.
        firstClass: card.isFirstClass || state.searchParty.firstClass,
        travelers: travelers,
      ),
    );
    _save();
  }

  void setDeutschlandTicket(bool value) {
    state = state.copyWith(
      hasDeutschlandTicket: value,
      searchParty: state.searchParty.copyWith(deutschlandTicket: value),
    );
    _save();
  }

  void setWeitereReduction(Reduction reduction) {
    final travelers = state.searchParty.travelers.map((t) {
      if (t.typ.isPerson) {
        return t.copyWith(weitere: reduction);
      }
      return t;
    }).toList();

    state = state.copyWith(
      searchParty: state.searchParty.copyWith(travelers: travelers),
    );
    _save();
  }

  void setSearchParty(SearchParty party) {
    // An explicit edit — from now on nothing auto-re-seeds the party (#43).
    state = state.copyWith(searchParty: party, partyCustomized: true);
    _save();
  }

  /// Seed search defaults from the signed-in DB account. Called from the auth
  /// notifier on successful profile load so the user doesn't have to re-enter
  /// what DB already knows (age, BahnCard, Deutschland-Ticket). Manual changes
  /// after this stick because the apply happens at most once per login.
  void applyFromDbAccount({
    int? age,
    BahnCardType? card,
    bool? hasDeutschlandTicket,
  }) {
    final newCard = card ?? state.bahnCard;
    final newDTicket = hasDeutschlandTicket ?? state.hasDeutschlandTicket;
    state = state.copyWith(
      age: age ?? state.age,
      bahnCard: newCard,
      hasDeutschlandTicket: newDTicket,
      // Seed the party from the account only if the rider hasn't set their own.
      // This runs on every DB restore, so clobbering here reset a customised
      // party on every app start (#43).
      searchParty: state.partyCustomized
          ? state.searchParty.copyWith(deutschlandTicket: newDTicket)
          : SearchParty.fromSettings(newCard, newDTicket),
    );
    _save();
  }

  void setAge(int age) {
    state = state.copyWith(age: age);
    _save();
  }

  void setApiDelay(int ms) {
    state = state.copyWith(apiDelayMs: ms);
    _save();
  }

  void setTrwlAutoCheckin(bool value) {
    state = state.copyWith(trwlAutoCheckin: value);
    _save();
  }

  void setTrwlVisibility(int value) {
    state = state.copyWith(trwlVisibility: value);
    _save();
  }

  void setRemindersEnabled(bool value) {
    state = state.copyWith(remindersEnabled: value);
    _save();
  }

  void setReminderLeadMinutes(int value) {
    state = state.copyWith(reminderLeadMinutes: value);
    _save();
  }

  void setTransferAlerts(bool value) {
    state = state.copyWith(transferAlerts: value);
    _save();
  }

  void setArrivalAlertEnabled(bool value) {
    state = state.copyWith(arrivalAlertEnabled: value);
    _save();
  }

  void setArrivalAlarmSound(bool value) {
    state = state.copyWith(arrivalAlarmSound: value);
    _save();
  }

  void setExitAlarmEnabled(bool value) {
    state = state.copyWith(exitAlarmEnabled: value);
    _save();
  }

  void setTransferProfile(TransferProfile profile) {
    state = state.copyWith(transferProfile: profile);
    _save();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
