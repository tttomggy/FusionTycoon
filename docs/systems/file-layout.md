# Where everything lives (src/ tree)

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.


```
src/ReplicatedStorage/Shared/
    Config/      shared config tables (PlotLayout, StreetLayout — the street
                 and speed belts, TycoonConfig, FusionConfig, RebirthConfig —
                 rebirth requirement/income/luck, MutationConfig — Golden/
                 Diamond/Rainbow, IndexConfig — the collection book,
                 OfflineConfig — offline earnings rate/cap,
                 FriendConfig — the friend boost (+15% per friend, max 4),
                 EventConfig — the event clock, effects and info-card copy,
                 SoundConfig — every sound slot,
                 MusicConfig — the background playlist and its fades, AdminConfig —
                 admins and the Admin Abuse panel,
                 HeistConfig — stealing and the lab shield,
                 RivalConfig — rival (NPC) labs: count, orb weights per
                 Rebirth band, respawn, guard, StealsPerHour,
                 GoalConfig — the ordered onboarding goals,
                 SettingsConfig — the player's reveal-card rules,
                 ShopConfig — every pass / product and shop number,
                 RewardConfig — free reward kinds and their labels,
                 DailyConfig — the 7-day daily reward and streak,
                 GiftConfig — the playtime gifts,
                 TrailerConfig — the /trailer shots and camera,
                 DealConfig — the rotating deals,
                 TutorialConfig — the tutorial steps and "?" help,
                 CombatConfig — weapons, ragdoll and hit rules, the melee box,
                 GachaConfig — Auto ×10 card/pacing timing and remote-pull reach,
                 QuestConfig — daily quests, the lab chain, power-ups, …)
    Modules/     shared runtime modules: UITheme (every UI colour/font token
                 and the World part colours), BillboardKit (world labels and
                 SurfaceGuis), PartKit (part/cylinder helpers, FT_Hover
                 tagging), PlotKit (plot shell + sign gate), StationKit
                 (station pads + holograms), GeneratorKit (the five factory-line generators + their
                 states), FactoryKit (factory belt + collector, and the
                 ball path), PortalKit (the Rebirth Portal), FloorKit (the 2nd
                 floor), PedestalVisuals,
                 SoundKit (every sound, by SoundConfig slot),
                 WeaponKit (the five weapon models: Tool, viewport model,
                 placed peel, selftest validation),
                 ShopPrices (live Robux prices), ShopState (Server
                 Overclock, real sale windows), DealState (the current
                 deal on the UTC clock),
                 NumberFormat
    Network/     RemoteEvents.lua — single source of truth for remotes
    VFX/         SparkleEmitter, ImportedEffects, imported *.rbxm VFX assets
src/ServerScriptService/
    Bootstrap.server.lua   entry point; hands Services/ to ServiceManager
    ServiceManager.lua     loading + Init/Start lifecycle
    Packages/ProfileStore.lua  vendored MadStudioRoblox/ProfileStore (commit
                           45c9847, Apache 2.0, unmodified, `--!nocheck`);
                           only PlayerDataService requires it
    Modules/AnalyticsKit.lua   the one AnalyticsService wrapper (not a
                           service; required directly)
    Modules/RemoteGuard.lua    remote arg checks (`Int`: finite whole numbers
                           in range) and the per-player rate limit (`Allow`)
    Services/              one ModuleScript per service (GoalService pays
                           and advances goals from PlayerDataService.OnSync;
                           WorldService builds ground, street, Event Boards
                           and FREE LAB placeholders; EventService runs the
                           event clock; AdminService runs Admin Abuse;
                           TutorialService the first-time tutorial;
                           QuestService quests and power-ups;
                           CombatService weapons, hits and ragdoll;
                           RivalService the rival (NPC) labs in empty slots,
                           their orbs and guards (the steal is HeistService's);
                           RewardService the daily reward and playtime
                           gifts; LeaderboardService the street boards;
                           FriendService the friend boost's friend count;
                           NotifyService the Open Cloud notifications)
src/StarterPlayer/StarterPlayerScripts/
    Controllers/  client controllers (one per domain): HudController,
                  ToastController (error/neutral toasts), ResultController
                  (fusion/gacha result cards), AnnouncementController
                  (banners), WorldLabelController (hides owner-only labels,
                  and any label within 7 studs of the camera),
                  WorldAnimationController (FT_Hover spin/bob, client-only),
                  GoalMarkerController (points at the current goal, or
                  a heist override), HeistController (steal prompt, carried
                  orbs, heist banners, shield fences),
                  BeltController (client-only belt chevrons),
                  GeneratorController (world Buy/Upgrade prompts, upgrade
                  toast + bump), FactoryController (client-only cash balls
                  on every nearby factory line, collector pops),
                  JumpPadController (the 2nd floor's jump pads),
                  MusicController (the background playlist),
                  EventController (event banners, sky, FX, HUD chip, Event
                  Boards), AdminController (admin panel + broadcasts),
                  ShopController, DailyController (when the daily card
                  opens, ClaimDaily), NotifyOptInController (the Roblox
                  notification opt-in ask after the daily reveal)…
    Effects/      RevealEffects, WeaponPose, WeaponFx (weapon feel)
    UI/           WeaponViewport (turning weapon model in a ViewportFrame),
                  UIKit (Panel/Button/Pill/Badge/TierOrb/ProgressBar/
                  Shadow/PopIn/PopOut/Modal/MutationPill), UpgradesPanel,
                  ItemPickerUI, RebirthPanel, IndexPanel, FusePanel (2–6
                  orb fusion chamber + picker, opened by the machine prompt),
                  AdminPanel (built only on the server's AdminOpen),
                  SettingsPanel (the ⚙ button: reveal-card rules, sound and music volume),
                  ShopPanel + ShopCards (the shop, the offer / Starter /
                  deal side cards), DealParts (part tiles + YOU GET list),
                  EffectsTray (active effects as cartoon badges + tooltips, with the always-on Friends chip; bottom-right row on desktop and tablet, top-right on a phone),
                  PurchaseCelebration (the reveal after a purchase),
                  DailyCard (the daily reward card), GiftsPanel (the GIFTS
                  button's panel),
                  HowToHeistPanel + HeistScenes (the 3D heist clips),
                  EventInfoCard (what the HUD event chip opens),
                  TutorialCards (the "?" slideshows + weapon unlock card),
                  TutorialBanner (the instruction banner + welcome splash),
                  TopStack (the top-centre slots + the announcement queue),
                  TutorialHand (the pointing hand + the big contextual
                  button), HudGate (the progressive HUD),
                  QuestsPanel (the 📜 QUESTS panel)
```
