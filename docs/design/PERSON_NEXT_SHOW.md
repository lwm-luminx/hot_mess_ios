# Person page: next show in the hero

Design sketch (2026-10-24, mockup only, not built yet): https://claude.ai/artifact/HzY6gL4cyfMMgacQ39ybyZ

Rick: "for a person view the next show isn't large enough, we need two views, one for where there are events (shows more event details in the hero) and one like the view without. next show should always show in the list as well."

Builds on [HERO_HEADER.md](HERO_HEADER.md) and the taller hero (`HeroMetrics.detailHeight`, `heroGlass`, `HeroActionRow` in `DesignSystem/HeroActions.swift`).

## Today

- iOS (`Features/People/PersonScreen.swift`): 104pt avatar, name, role, one glass chip "Next: Fri · Neighbours", Tip. The Events list drops the first event and is titled "More Events".
- Android (`ui/screens/PeopleScreens.kt`): 76pt avatar beside the name, no next show in the hero; the Events list shows every event.

## Hero with a next show

The hero grows to 560pt. Text sits on the dark scrim, controls are dark glass.

- **Identity row**: avatar drops to 56pt and sits beside the name and role. Tip becomes a 44pt round glass button at the end of the row (a menu when there are several tip apps).
- **Next show panel** (dark glass, 24pt radius, 12pt padding), tapping it opens the event:
  - Event picture, 92 x 116pt, 14pt radius.
  - Kicker: "Next show · Tonight" (or the weekday / date); "On now" with a green dot while it is running.
  - Start to end time: "Fri Oct 24 · 9 PM to 2 AM".
  - Event title, 21pt heavy.
  - Venue name and distance.
  - Their part: Hosting, Performing, DJ. Hidden when unknown.
  - Friends going faces line, hidden until the API sends it.
  - Actions: **Get there** (white, opens directions to the venue), **Going** (event RSVP), and a chevron to open the event.
- The hero photo stays the person's banner; the event picture lives in the panel.

## Hero with nothing booked

Same as today: 440pt, 104pt avatar above the name, role, Tip. No Next chip.

## Events list

- Always titled "Events" and always starts with the next show.
- The next show is a featured 180pt `PhotoCard` with a **Next** pill and an accent ring; the rest are 132pt cards.
- Empty: "No upcoming events" with "Follow {name} to hear when they book a show." and a Follow row once Follow exists.

## Copy rules

- Non-friends show as "First L."; friends see full names.
- No drinking copy.

## Open points

- Role at the show needs the person's lineup or host role on the event; host-only falls back to "Hosting".
- Friends going is not in the API yet (same gap as the event hero).
- Android needs both heroes and the featured first card.
