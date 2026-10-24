# Hot Mess on iPad

> Exported on 2026-10-24 from the design canvas https://claude.ai/artifact/MjSMh9bZxjV6aoHCE3FLmP (the interactive mockups are omitted). Mockups only: nothing here is built yet. Tokens and components come from the AudienceKit design system (https://claude.ai/artifact/F1mB4QrCQSwi7ZahwgPWgd), Hot Mess preset.

## Where the app is today

Hot Mess is already a universal app (`TARGETED_DEVICE_FAMILY = "1,2"`, iOS 18), but nothing in it reacts to iPad. `MainTabView` is the phone tab bar with one `NavigationStack` per tab, every screen is a single `ScrollView` column stretched to the full width, and no view reads `horizontalSizeClass`. On a 13-inch iPad that means 1,366pt-wide photo strips, chat bubbles pinned to the far edges, and live chat one push away from the page it belongs to.

`Info.plist` also sets `UIRequiresFullScreen`, so the app can't share the screen in Split View or Slide Over, and Stage Manager can't resize it.

## The idea

Two moves carry most of the improvement:

1. **A sidebar instead of the tab bar.** The same five tabs, plus the rooms you're in and friends out tonight, in a 300pt sidebar that collapses to the floating tab bar in portrait and narrow windows.
2. **Chat beside the page.** When you're at a venue, its live chat sits in a 400pt column next to Now and the venue page, so you can read the lineup and keep up with the room at the same time.

Everything else is giving lists more than one column and stopping content at a readable width.

## Screens

### Now (landscape, 13-inch)

- **Sidebar:** Hot Mess wordmark with the spectrum bar, a locale button (Seattle), the five tabs, then **Chats** (the venue room you're in with its unread count, the city room, Pings), **Friends out tonight** (faces with presence dots, friends ringed in the accent), and Me at the bottom.
- **Middle column (666pt, the 680pt content max):** the hero for where you are, with Ping and Safety on glass. Below it, On now and Quickie side by side, then photos from tonight in a four-across grid, then Where your friends are.
- **Chat column (400pt):** room banner with the live dot and head count, the Here now strip (friends first), the pinned venue announcement, the thread and the composer. The expand button opens the room on its own.
- **Get help** stays in the toolbar on every screen.

### Venues

- **Three columns:** sidebar (with neighborhoods and their venue counts under the tabs), the venue list (420pt: search, Nearby / On tonight / Friends there, 104pt photo strips), and a live map filling the rest.
- Picking a strip highlights its pin and shows a venue card at the bottom of the map (Open venue, Directions). The map is always visible, so the full-screen map cover isn't needed on iPad.

### Venue with chat docked (shown in dark)

- The sidebar is hidden to give the page room; its button sits on the hero next to Back.
- **Page:** the 440pt hero with details and glass actions (Ping, Safety, Directions, Call), then Tonight's lineup and Coming up side by side, then About with a small map.
- **Chat column (420pt):** live chat with In this room, the Here now strip, a trivia round card, a rich event message from the venue, and the composer.

### Events

- A NightCalendar card (320pt) on the left: the month with today selected and days shaded where friends are going.
- To its right a card grid: tonight's featured event across two columns (date badge, RSVP pill, friends going), then two columns, then this weekend three across, ending with a See all tile.
- The sidebar adds **Your plans**: Going, Interested and Passes.

### People

- City / Everyone switch in the toolbar, then Playing this week and Based here as two-column grids of 84pt person cards.
- Picking a person opens them in a 400pt inspector column (hero, next gig chip, Tip, About, Coming up, Photos) instead of pushing a new screen, so you can browse performers without losing your place.
- The sidebar lists friends with presence dots.

### Portrait (11-inch)

- The sidebar collapses to the floating tab bar at the top, with the sidebar button on the left and Get help on the right.
- Now becomes two columns under the hero: On now, Quickie and friends on the left, a ChatPeek card (last three lines, Open chat) and photos on the right. Tapping the peek opens the chat full screen, as on iPhone.

## Layout rules

| Width | Navigation | Chat at a venue | Lists |
| --- | --- | --- | --- |
| Compact (iPhone, Slide Over, narrow windows) | Tab bar, as today | Pushed screen, ChatPeek on the page | One column |
| Regular, under ~1,100pt (portrait, half-screen) | Floating tab bar, sidebar on demand | ChatPeek card in the second column | Two columns |
| Regular, ~1,100pt and wider (landscape) | Sidebar | Docked column (400–420pt) | Two or three columns, inspector for people |

- Decide by size class and available width, never by device idiom, so Split View and Stage Manager windows get the right layout (same rule as the staff apps' iPad work).
- Page content stops at 680pt (`size-content-max`); extra width goes to columns, not to stretched rows.
- Photo cards keep their phone heights (104pt venue strips, 132/180pt event cards, 84pt person cards) and add columns.
- Chat bubbles keep `size-bubble-max` (280pt), so a docked chat reads like the phone.
- Touch targets stay 44pt; sidebar rows are 44pt (52pt with a subtitle).

## How it would be built

- **Shell:** `TabView` with `.tabViewStyle(.sidebarAdaptable)` (iOS 18) in `MainTabView`. The tabs become `Tab`s as today; the Chats and Friends groups are `TabSection`s that only show in the sidebar. iPhone keeps its tab bar for free.
- **Chat column:** a container that, when the width is regular and wide, puts `VenueChatScreen` beside the page instead of `LiveChatPeek`. One room connection is shared, so opening the column doesn't open a second socket.
- **Venues:** a `NavigationSplitView` (list + map detail) when regular; the current `VenuesScreen` when compact.
- **Grids:** `LazyVGrid` with adaptive columns in Events, People, photos and Now, sized from the existing `PhotoCard` metrics.
- **People inspector:** `.inspector` showing `PersonScreen` for the selection on regular width.
- **Multitasking:** drop `UIRequiresFullScreen` so the app can run in Split View, Slide Over and resizable Stage Manager windows.
- **Testing:** iPad screenshots in `HotMessScreenshots` for 13-inch landscape and 11-inch portrait, plus a pass at the Split View widths.

## Open questions

- Should the docked chat be on by default at a venue, or opened from the hero's Chat button?
- Does the sidebar's Chats group list every room you've posted in tonight, or only the venue you're at and your city?
- Should Venues on iPad open the venue page in place of the map (two columns) or over it (three)? The mock keeps the map and shows a card.
