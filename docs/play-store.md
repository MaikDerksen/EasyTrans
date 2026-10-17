# Play Store release

Upload file: `android/app/build/outputs/bundle/release/app-release.aab` (built with `./gradlew bundleRelease`, signed with your local keystore).

**Back up `easytrans-release.jks` and `keystore.properties` somewhere safe.** If you enroll in Play
App Signing (default), this key is only the upload key and Google can reset it; without them you
cannot publish updates otherwise.

## Steps (in your Google account)

1. Create a developer account at <https://play.google.com/console/signup> (one-time 25 USD, ID
   verification).
2. New personal accounts must run a **closed test with at least 12 testers for 14 days** before the
   app can go to production. Create the app, upload the AAB to *Testing → Closed testing*, add
   testers by email.
3. Fill in the store listing (texts below), content rating questionnaire, target audience, and the
   data safety form (no data collected or shared; audio is processed on the device).
4. A **privacy policy URL** is required because the app uses the microphone.

## Listing texts

**App name:** EasyTrans – Live-Dolmetscher

**Short description (≤ 80):** Gespräche live übersetzen – einfach losreden, das Handy erkennt, wer spricht.

**Full description:**

EasyTrans macht dein Handy zum Dolmetscher auf dem Tisch. Leg es zwischen dich und dein Gegenüber
und redet einfach drauflos. Die App erkennt automatisch, welche Sprache gerade gesprochen wird, und
zeigt jeder Seite nur die Übersetzung dessen, was die andere Person gesagt hat. Die obere Hälfte
steht auf dem Kopf, damit dein Gegenüber mitlesen kann.

- Kein Umschalten, kein Knopfdrücken: die Sprache wird automatisch erkannt
- Übersetzung erscheint schon während des Sprechens
- Übersetzung läuft auf dem Gerät, nach dem ersten Laden auch offline
- Deutsch, Englisch, Spanisch, Französisch, Italienisch, Portugiesisch, Japanisch, Koreanisch,
  Chinesisch
- Kein Konto, keine Werbung

**Category:** Travel & Local · **Requires:** Android 14+

## Data safety answers

- The app's own code collects and shares nothing.
- The bundled Google ML Kit SDK may collect device, app and performance information. Declare
  exactly what Google lists in its ML Kit Data safety guidance:
  <https://developers.google.com/ml-kit/android-data-disclosure>
- Audio is processed by the system speech recognizer; on-device when the language pack is
  installed, otherwise by Google's speech service. Translation runs on the device.
- Privacy policy: the published `docs/privacy-policy.html` (share its link publicly first).
