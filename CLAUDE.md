# Tempo Holidays — project guidance

## Locale identifiers are CLDR's

Tempo Holidays uses CLDR locale identifiers only, everywhere a language or a locale is named: in the compiled data, in the names a holiday carries, in the territory languages `Tempo.Holidays.Data.languages/1` gives, in the Gettext catalog's locale directories, and in every option and document.

`date-holidays` does not always write CLDR's codes, so its data is converted when it is built, never read as it is:

* **A non-CLDR language code is mapped to CLDR's** — `jp` → `ja` (Japanese), `cz` → `cs` (Czech), `ge` → `ka` (Georgian), `lat` → `la` (Latin), `no` → `nb` (Norwegian Bokmål). The map is `@language_codes` in `Tempo.Holidays.DateHolidays`, applied to holiday names and to each territory's `langs` alike.

* **Where the dataset writes a language under both codes** (`cs` and `cz`), the name under the CLDR code is kept.

* **A key of a name map that is no language is dropped** — `type`, which the dataset writes among a few holidays' names. The list is `@not_languages` in the same module.

When `date-holidays` is updated (`@pinned_version` in `Tempo.Holidays.Build`, or `mix tempo.holidays.update --version`), check the new bundle's language codes against CLDR before releasing: list every code its `name` maps, `names` table and `langs` lists use, and add any that is not CLDR's to `@language_codes` (or `@not_languages`). A code that is neither CLDR's nor mapped is kept as the dataset writes it, so a locale never finds it; on 3.38.0 that is `ls`, on one shared name of uncertain language.
