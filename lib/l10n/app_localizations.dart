import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_cs.dart';
import 'app_localizations_da.dart';
import 'app_localizations_de.dart';
import 'app_localizations_el.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fi.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hu.dart';
import 'app_localizations_it.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_no.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ro.dart';
import 'app_localizations_sv.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('cs'),
    Locale('da'),
    Locale('de'),
    Locale('el'),
    Locale('en'),
    Locale('es'),
    Locale('fi'),
    Locale('fr'),
    Locale('hu'),
    Locale('it'),
    Locale('nl'),
    Locale('no'),
    Locale('pl'),
    Locale('pt'),
    Locale('ro'),
    Locale('sv'),
    Locale('tr'),
    Locale('uk')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'EcoNav'**
  String get appName;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose a language'**
  String get chooseLanguage;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @leaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get leaderboard;

  /// No description provided for @challenges.
  ///
  /// In en, this message translates to:
  /// **'Challenges'**
  String get challenges;

  /// No description provided for @stores.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get stores;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get login;

  /// No description provided for @signup.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signup;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @startNavigation.
  ///
  /// In en, this message translates to:
  /// **'Start Trip'**
  String get startNavigation;

  /// No description provided for @stopNavigation.
  ///
  /// In en, this message translates to:
  /// **'Stop Navigation'**
  String get stopNavigation;

  /// No description provided for @lamePoints.
  ///
  /// In en, this message translates to:
  /// **'Lame Points'**
  String get lamePoints;

  /// No description provided for @vipMember.
  ///
  /// In en, this message translates to:
  /// **'VIP Member'**
  String get vipMember;

  /// No description provided for @getPremium.
  ///
  /// In en, this message translates to:
  /// **'Get Premium'**
  String get getPremium;

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Walk, Ride, Earn'**
  String get onboardingTitle1;

  /// No description provided for @onboardingDesc1.
  ///
  /// In en, this message translates to:
  /// **'Use eco-friendly transport and accumulate Lames for every kilometer traveled.'**
  String get onboardingDesc1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'Challenges & Cashbacks'**
  String get onboardingTitle2;

  /// No description provided for @onboardingDesc2.
  ///
  /// In en, this message translates to:
  /// **'Visit our partner stores, validate your purchases and earn cashback.'**
  String get onboardingDesc2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Protect the Planet'**
  String get onboardingTitle3;

  /// No description provided for @onboardingDesc3.
  ///
  /// In en, this message translates to:
  /// **'Plant trees, make donations or redeem gift cards with your earnings.'**
  String get onboardingDesc3;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back!'**
  String get welcomeBack;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAccount;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @acceptTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'I accept the '**
  String get acceptTermsPrefix;

  /// No description provided for @cguAndEula.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service & EULA'**
  String get cguAndEula;

  /// No description provided for @andThe.
  ///
  /// In en, this message translates to:
  /// **' and the '**
  String get andThe;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @mustAcceptTerms.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms of Service and Privacy Policy to create an account.'**
  String get mustAcceptTerms;

  /// No description provided for @enterUsername.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username.'**
  String get enterUsername;

  /// No description provided for @fillEmailAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Please fill in email and password.'**
  String get fillEmailAndPassword;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters.'**
  String get passwordMinLength;

  /// No description provided for @noAccountYet.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get noAccountYet;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get alreadyHaveAccount;

  /// No description provided for @signupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registration successful!'**
  String get signupSuccess;

  /// No description provided for @authError.
  ///
  /// In en, this message translates to:
  /// **'Authentication error.'**
  String get authError;

  /// No description provided for @weakPassword.
  ///
  /// In en, this message translates to:
  /// **'The password provided is too weak.'**
  String get weakPassword;

  /// No description provided for @emailAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'An account already exists for this email.'**
  String get emailAlreadyInUse;

  /// No description provided for @wrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect credentials.'**
  String get wrongCredentials;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'The email address is invalid.'**
  String get invalidEmail;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email required'**
  String get emailRequired;

  /// No description provided for @enterEmailForReset.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email address in the field above.'**
  String get enterEmailForReset;

  /// No description provided for @emailSent.
  ///
  /// In en, this message translates to:
  /// **'Email sent'**
  String get emailSent;

  /// No description provided for @resetEmailSentTo.
  ///
  /// In en, this message translates to:
  /// **'A reset email has been sent to'**
  String get resetEmailSentTo;

  /// No description provided for @noAccountWithEmail.
  ///
  /// In en, this message translates to:
  /// **'No account associated with this email.'**
  String get noAccountWithEmail;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @whereToGo.
  ///
  /// In en, this message translates to:
  /// **'Where do you want to go?'**
  String get whereToGo;

  /// No description provided for @startingPoint.
  ///
  /// In en, this message translates to:
  /// **'Starting point'**
  String get startingPoint;

  /// No description provided for @currentLocation.
  ///
  /// In en, this message translates to:
  /// **'My current location'**
  String get currentLocation;

  /// No description provided for @walk.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get walk;

  /// No description provided for @bike.
  ///
  /// In en, this message translates to:
  /// **'Bicycle'**
  String get bike;

  /// No description provided for @transit.
  ///
  /// In en, this message translates to:
  /// **'Transit'**
  String get transit;

  /// No description provided for @car.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get car;

  /// No description provided for @startTrip.
  ///
  /// In en, this message translates to:
  /// **'Start Trip'**
  String get startTrip;

  /// No description provided for @stopTrip.
  ///
  /// In en, this message translates to:
  /// **'Stop Trip'**
  String get stopTrip;

  /// No description provided for @cancelTrip.
  ///
  /// In en, this message translates to:
  /// **'Cancel Trip'**
  String get cancelTrip;

  /// No description provided for @finishTrip.
  ///
  /// In en, this message translates to:
  /// **'Finish Trip'**
  String get finishTrip;

  /// No description provided for @tripCompleted.
  ///
  /// In en, this message translates to:
  /// **'Trip completed!'**
  String get tripCompleted;

  /// No description provided for @tripSummary.
  ///
  /// In en, this message translates to:
  /// **'Trip Summary'**
  String get tripSummary;

  /// No description provided for @speedTooHigh.
  ///
  /// In en, this message translates to:
  /// **'Speed too high for this mode!'**
  String get speedTooHigh;

  /// No description provided for @lamesEarned.
  ///
  /// In en, this message translates to:
  /// **'Lames earned'**
  String get lamesEarned;

  /// No description provided for @distanceTraveled.
  ///
  /// In en, this message translates to:
  /// **'Distance traveled'**
  String get distanceTraveled;

  /// No description provided for @timeElapsed.
  ///
  /// In en, this message translates to:
  /// **'Time elapsed'**
  String get timeElapsed;

  /// No description provided for @averageSpeed.
  ///
  /// In en, this message translates to:
  /// **'Average speed'**
  String get averageSpeed;

  /// No description provided for @co2Saved.
  ///
  /// In en, this message translates to:
  /// **'CO₂ saved'**
  String get co2Saved;

  /// No description provided for @noGpsSignal.
  ///
  /// In en, this message translates to:
  /// **'GPS signal not found'**
  String get noGpsSignal;

  /// No description provided for @enableGps.
  ///
  /// In en, this message translates to:
  /// **'Please enable GPS'**
  String get enableGps;

  /// No description provided for @modifyHomeAddress.
  ///
  /// In en, this message translates to:
  /// **'Edit home address'**
  String get modifyHomeAddress;

  /// No description provided for @setHomeAddress.
  ///
  /// In en, this message translates to:
  /// **'Set home address'**
  String get setHomeAddress;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @lameHistory.
  ///
  /// In en, this message translates to:
  /// **'Lame History'**
  String get lameHistory;

  /// No description provided for @vipSubscription.
  ///
  /// In en, this message translates to:
  /// **'VIP Subscription'**
  String get vipSubscription;

  /// No description provided for @becomeVip.
  ///
  /// In en, this message translates to:
  /// **'Become VIP'**
  String get becomeVip;

  /// No description provided for @vipActive.
  ///
  /// In en, this message translates to:
  /// **'VIP Active'**
  String get vipActive;

  /// No description provided for @level.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get level;

  /// No description provided for @totalDistance.
  ///
  /// In en, this message translates to:
  /// **'Total distance'**
  String get totalDistance;

  /// No description provided for @totalTrips.
  ///
  /// In en, this message translates to:
  /// **'Total trips'**
  String get totalTrips;

  /// No description provided for @caloriesBurned.
  ///
  /// In en, this message translates to:
  /// **'Calories burned'**
  String get caloriesBurned;

  /// No description provided for @partnerStores.
  ///
  /// In en, this message translates to:
  /// **'Partner Stores'**
  String get partnerStores;

  /// No description provided for @scanReceipt.
  ///
  /// In en, this message translates to:
  /// **'Scan Receipt'**
  String get scanReceipt;

  /// No description provided for @validatePurchase.
  ///
  /// In en, this message translates to:
  /// **'Validate Purchase'**
  String get validatePurchase;

  /// No description provided for @pendingValidation.
  ///
  /// In en, this message translates to:
  /// **'Pending validation'**
  String get pendingValidation;

  /// No description provided for @receiptApproved.
  ///
  /// In en, this message translates to:
  /// **'Receipt successfully validated!'**
  String get receiptApproved;

  /// No description provided for @receiptRejected.
  ///
  /// In en, this message translates to:
  /// **'Receipt rejected'**
  String get receiptRejected;

  /// No description provided for @cashbackEarned.
  ///
  /// In en, this message translates to:
  /// **'Cashback earned'**
  String get cashbackEarned;

  /// No description provided for @noStoresNearby.
  ///
  /// In en, this message translates to:
  /// **'No stores nearby'**
  String get noStoresNearby;

  /// No description provided for @distanceToStore.
  ///
  /// In en, this message translates to:
  /// **'Distance to store'**
  String get distanceToStore;

  /// No description provided for @dailyChallenges.
  ///
  /// In en, this message translates to:
  /// **'Daily Challenges'**
  String get dailyChallenges;

  /// No description provided for @weeklyChallenges.
  ///
  /// In en, this message translates to:
  /// **'Weekly Challenges'**
  String get weeklyChallenges;

  /// No description provided for @claimReward.
  ///
  /// In en, this message translates to:
  /// **'Claim reward'**
  String get claimReward;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgress;

  /// No description provided for @raffleTickets.
  ///
  /// In en, this message translates to:
  /// **'Raffle tickets'**
  String get raffleTickets;

  /// No description provided for @buyTickets.
  ///
  /// In en, this message translates to:
  /// **'Buy tickets'**
  String get buyTickets;

  /// No description provided for @notEnoughLames.
  ///
  /// In en, this message translates to:
  /// **'Not enough Lame Points'**
  String get notEnoughLames;

  /// No description provided for @comeBackTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Come back tomorrow!'**
  String get comeBackTomorrow;

  /// No description provided for @leaderboardGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global Leaderboard'**
  String get leaderboardGlobal;

  /// No description provided for @leaderboardNational.
  ///
  /// In en, this message translates to:
  /// **'National Leaderboard'**
  String get leaderboardNational;

  /// No description provided for @rank.
  ///
  /// In en, this message translates to:
  /// **'Rank'**
  String get rank;

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get points;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @userNotLoggedInChallenges.
  ///
  /// In en, this message translates to:
  /// **'Log in to view challenges.'**
  String get userNotLoggedInChallenges;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'cs',
        'da',
        'de',
        'el',
        'en',
        'es',
        'fi',
        'fr',
        'hu',
        'it',
        'nl',
        'no',
        'pl',
        'pt',
        'ro',
        'sv',
        'tr',
        'uk'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'cs':
      return AppLocalizationsCs();
    case 'da':
      return AppLocalizationsDa();
    case 'de':
      return AppLocalizationsDe();
    case 'el':
      return AppLocalizationsEl();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fi':
      return AppLocalizationsFi();
    case 'fr':
      return AppLocalizationsFr();
    case 'hu':
      return AppLocalizationsHu();
    case 'it':
      return AppLocalizationsIt();
    case 'nl':
      return AppLocalizationsNl();
    case 'no':
      return AppLocalizationsNo();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ro':
      return AppLocalizationsRo();
    case 'sv':
      return AppLocalizationsSv();
    case 'tr':
      return AppLocalizationsTr();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
