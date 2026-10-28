# Playtest (wave 5)

One sitting of about 45 minutes with the game on Turku, to decide what to tune and what comes next.
Write down anything that feels wrong, too slow, too easy, ugly or confusing. A one-line note is enough;
the numbers below are where most fixes will go.

## Before you start

- Desktop: `cargo run --release`, then pick Turku in the menu (or `MAP=turku cargo run --release`).
  Browser: https://olivermikkola.github.io/3D-auto/.
- Useful keys: **N** skips 3 hours of the day, **F3** shows frame time and entity counts, **Tab** shows
  progress (cash, missions, businesses), **R** uses a shop or business, **H** is the horn.
- A fresh start: Tab, then hold Backspace.

## The route

1. **Kauppatori by day** (noon). Stalls and shoppers; honk and watch them run and come back. The bus
   stops around the square: people waiting, buses stopping, people getting on.
2. **Along the Aurajoki** (afternoon). Terraces with people at the tables (Olkku, Samppalinna,
   Tårget...). Gulls by the water; the cathedral bells on the hour.
3. **The cycle paths** (anywhere). Riders, and what happens when you clip one.
4. **Your first business.** Earn $3,000 (a few fares, or the first missions) and buy the kebab grill
   near the start. Is the money worth it? Do you come back to empty the till?
5. **The story.** Play 01 Joyride, 02 Street Race and 04 Getaway. Do the calls from Rauha, Jonne
   and Setä make you want the next one? Are they readable while driving?
6. **The four jobs**, five minutes each: taxi (any cab), ambulance, police car (vigilante), fire engine.
7. **Night out** (N until 23:00). Crowds outside the bars around Kauppatori, lit windows, the
   lamps.
8. **Ylioppilaskylä and the postcard spots** (Kakolanmäki, Logomo, Puolalanmäki, Kupittaa). Ylioppilaskylä
   is still plain boxes: which of its buildings matter most, and what's wrong with them?

## Questions to answer

- Which job is the most fun, and which is a chore? Too much or too little money?
- Prices: is a $15,000 taxi firm something to save for?
- Are the cyclists, shoppers, bus queues and night crowds enough people, or too many?
- Frame time with F3 at the busiest spot (Kauppatori at noon): smooth?
- LOD2 roofs beyond the old town: worth a download of 182 tiles? Most Turku roofs are flat.
- What does Ylioppilaskylä need first?

## Where the numbers are

| What | File | Numbers |
|---|---|---|
| Taxi fares | `game/systems/fares.lua` | `BASE`, `PER_KM`, `TIP`, `EVERY` (seconds between fares) |
| Ambulance | `game/systems/ambulance.lua` | `BASE`, `PER_SECOND`, `SPARE` (spare seconds), `BONUS` |
| Police car (vigilante) | `game/systems/vigilante.lua` | `PAY` (a level), `CLOCK`, `CRUISE` and `SMART` (how hard suspects are) |
| Fire engine | `game/systems/fire.lua` | `BASE`, `PER_SECOND`, `PUT_OUT`, `GROW` |
| Businesses | `game/systems/businesses.lua` | `price`, `hourly` (an hour of game time is two minutes), `TILL_HOURS` |
| Mission rewards | `game/missions/*.lua` | `reward` |
| How many people | `game/lib/quality.lua`, `game/systems/kauppatori.lua`, `cyclists.lua`, `nightlife.lua` | `PEDS`, `SHOPPERS`, `MOST` |
| Story lines | `game/story/arc.lua`, `game/story/radio.lua` | the text |
