# Sounds

Every sound in Fusion Tycoon goes through one slot in
`src/ReplicatedStorage/Shared/Config/SoundConfig.lua`, played with
`SoundKit.Play(slot, parent?)`. To change a sound, put a Creator Store id
(`rbxassetid://123…`) in that slot's `Id` and tune `Volume`. Nothing else
needs to change.

- **An empty Id is silent** and raises no error. Leave a slot empty rather
  than copying one sound into every slot.
- **A bad Id warns once** at startup (`SoundKit: <slot> failed to load
  <id>`), then that slot stays silent.
- Only `rbxasset://sounds/electronicpingshort.wav` is known to load right
  now. It fills the slots that already used it; the new slots are empty.
- **There is no looping ambient sound.** The Mythic/Secret pedestal bell
  loop was removed.

| Slot | Should sound like | Plays when / where | Now |
|---|---|---|---|
| `EventStart` | Rising 3-note "something's coming" sting, < 1 s | Event start banner: each 3-2-1 tick (pitched up) and the reveal (EventController) | ping |
| `EventEnd` | Soft descending "wind-down" chime, < 1 s | "<Event> is over" toast | empty |
| `CoinPickup` | Short bright coin blip, < 0.5 s | You collect a Golden Rain coin, lab or street (EventController) | empty |
| `BigCoin` | Fuller coin "ka-ching" with sparkle, < 1 s | You collect a BIG coin | empty |
| `Thunder` | Close lightning crack + rumble, 1–2 s | A Power Surge bolt, at the struck pedestal (EventController) | empty |
| `MeteorImpact` | Heavy thud / crash, < 1.5 s | A meteor lands on the street (EventController) | empty |
| `EventReveal` | Big magical reveal swell, 1–2 s | The event-only mutation reveal card: Charged / Void / Celestial (ResultController) | empty |
| `Grab` | Quick whoosh / snatch, < 0.5 s | You grab an item off an enemy pedestal (HeistController) | ping ×1.6 |
| `Alarm` | Urgent alarm beep (played 3×), < 0.4 s | Your item is being stolen (HeistController) | ping ×0.7 |
| `RevealMajor` | Triumphant reveal hit, ~1 s | Epic+ / Diamond+ fusion reveal at the machine (RevealEffects) | ping |
| `RevealMinor` | Light pop / ding, < 0.5 s | Other fusion reveals (RevealEffects) | ping |
| `Toast` | Short UI notification blip, < 0.4 s | Top announcement banners (AnnouncementController) | ping |
| `Station` | Purchase "cha-ching", < 0.6 s | A station purchase: Multiplier Pad, gacha (TycoonService, at the pad) | ping |
