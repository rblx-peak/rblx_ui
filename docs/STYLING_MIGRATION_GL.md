# UI Styling Migration (Phase 0) + Gurren Lagann Pack (Phase 1)

Date: 2026-07-26 · Engine facts probed live in Studio via MCP (`execute_luau`), not assumed.

---

## 1. STYLING CAPABILITY REPORT (gates everything below)

Probed in the running place, Edit **and** play-solo Client:

| Surface | Verdict | Evidence |
|---|---|---|
| `StyleSheet` / `StyleRule` / `StyleLink` / `StyleDerive` classes | **EXIST** | `Instance.new` succeeds for all four |
| `StyleRule` methods (`SetProperties`, `SetProperty`, `GetProperties`, `SetPropertyTransitions`, `GetPropertyTransitions`, `Selector`, `Priority`) | **PRESENT, accept writes** | all pcall-clean; `GetProperties` round-trips `{BackgroundColor3 = "$accent"}` |
| **Runtime application of rules** | **INERT in this environment** | visual proof: linked `.Tag { BackgroundColor3 = red }` left a frame rendering its authored green; pseudo-instance rules created no children; tag flips changed nothing on screen |
| Property reads under styling | **do not reflect rules** | styled button read back authored color; detection must use `AbsoluteSize` (layout witness), which is how `Style/Capabilities.Detect()` works |
| Selector grammar validation | **NONE at set time** | `:Pressed` (nonexistent state) round-trips fine → acceptance ≠ support; only render evidence counts |
| `Enum.GuiState` | `Idle, Hover, Press, NonInteractable` | **`:Press` not `:Pressed`; there is NO Focus state** — gamepad focus stays Luau |
| Styling Transitions | **API present, unverifiable-live here** (application is off) | gated behind `Capabilities.TransitionsActive`, probed at boot via mid-flight `AbsoluteSize` sampling |
| `UIShadow` | **LIVE AND RENDERING** | screenshot-verified: hard offset sticker shadow ✓, zero-offset colored glow ✓. `Spread` is a **UDim2** in this build (not the number some specs claim). `ZIndex` defaults −1 |
| Per-corner `UICorner` (`TopLeftRadius` etc.) | **LIVE AND RENDERING** | screenshot-verified single-corner 48px round |
| Multiple UIShadows per instance | accepted | not perf-validated at scale; budget counter enforces ≤80 warn line |

**Consequence:** the architecture is *bridge-era by necessity*: sheets, tokens, tags and rules are authored and wired now; the imperative `UIChrome`/`ApplyTheme` path remains the authoritative renderer until `Capabilities.Detect()` reports styling active in some future engine build. `UIShadow`/per-corner are used natively **today**.

To flip styling on when the platform ships it: nothing. `Detect()` re-probes every boot.

## 2. PHASE 0 DESIGN + MIGRATION REPORT

Mapping the prompt's idealized paths onto this codebase (they did not exist here):

| Prompt path | Reality here |
|---|---|
| `Framework/Theme/` | `UI/Controllers/UIThemeController.luau` + `UI/UIChrome.luau` + `UI/Types.luau` |
| `Framework/Layers.luau` | `UI/Framework/Layers.luau` ✓ |
| `Framework/Screen.luau` | `UI/Screens/UIScreenBase.luau` |
| `Theme/Packs/ArmoredCore_*` | `UI/Themes/ArmoredCoreTheme.luau` (+ Roblox Classic default) |
| `DeathStranding_*` | **does not exist** — validation cases are Classic + ArmoredCore |
| `Motion/Tween` wrapper | theme `Motion` TweenInfo kit + `UIChrome.Animate` |

New layer (all under `src/Client/UI/Style/`):
- **Capabilities.luau** — class existence (sync) + *does styling actually apply* (async, AbsoluteSize witness rig) + transitions probe + **UIShadow budget** (RegisterShadow handles; warn at 80; pooled = disable-not-destroy).
- **Tags.luau** — canonical registry: structural (`UIPanel, UIButton, UIButtonPrimary, UILabel, UIValue, UIListRow, UISlot, UIChip, UIMeterFill, UITab, UIIcon` + absorbed legacy `UIHeaderBar/UICloseButton`), modifier (`UISelected, UIDanger, UIDisabled, UIFeatured, UIMaxed, UIArmed`), dialect (`DialectComic, DialectTech`). Packs may not invent structural tags.
- **StateDriver.luau** — **the sole tag mutator** (grep invariant stated in code). `Structural` / `Set` / `SetDialect` (dialects exclusive per root). Audit hook.
- **TokenBridge.luau** — theme tables → `$token` attributes (`Colors.Surface` → `color_Surface`-style flattening; dots are illegal in attribute names). **Fonts cannot bridge** (no Font attribute type) — rules needing FontFace get it inlined at build; Luau keeps reading `theme.Fonts`.
- **SheetBuilder.luau** — pack `StyleRules` data → live sheet. **Priority ladder: Base 0 < Pack 100 < Dialect 200 < State 300 < A11y 400** (+authoring index within band). Guards: refuses `CornerRadius` + per-corner in one rule (documented-undefined); refuses transitions on `UIMeterFill` selectors (high-frequency = ticker-only). Reduce-motion = zero-duration TweenInfo substitution + sheet rebuild (honest cost: one rebuild per accessibility toggle).

Wiring:
- `Layers.SetStyleSheet(sheet)` — **one StyleLink per layer ScreenGui** (styling applies to all descendants of the link's parent, so per-screen links are unnecessary; Debug layer exempt). Late layers pick the sheet up on creation.
- `UIThemeController.ApplyThemeObject` — theme swap **is** a sheet swap: rebuild pack sheet (derived from `BaseTokens` sheet = Classic), re-point links, destroy previous. Also `SetReduceMotion(bool)` → sheet substitution.
- `ClientHandler` boot: `Capabilities.Detect()` + `UIDebug.StyleReport` seam.

**Shadow/glow token migration:** `Types.UIThemeEffect` (`Blur: UDim, Offset: UDim2, Spread: UDim2, Color/ColorToken, Transparency`) with theme groups `EffectShadows{sm,md,lg}` / `EffectGlows{sm,md,lg,pulse}`; realized by `UIChrome.Shadow/Glow` (budget-registered). `UIStyler.DropShadow` reimplemented on UIShadow — the 9-slice glow image `rbxassetid://5554236805` is **removed from the pipeline** (zero call sites existed; return type ImageLabel→UIShadow noted). Text glow remains `UIStroke` (`UIChrome.TextOutline`) — UIShadow shades text *backgrounds*, not glyphs.

**AC / Classic impact:** neither declares `EffectShadows/EffectGlows/StyleRules/DialectTokens` → all new paths are no-ops for them; rendering is untouched (live-verified after push, §9). AC's hologram framing *may* later re-express as `EffectGlows` phosphor tokens — flagged as an optional token diff, not done (imperative UIStroke glow currently delivers that look; migrating it is cosmetic-neutral).

**Imperative styling deleted in favor of rules: NONE yet — deliberately.** With application inert here, deleting the imperative path would ship an invisible UI. The cutover list (button hover fills → `.UIButton:Hover`, panel fills → `.UIPanel`, disabled dims → `.UIDisabled`) is authored as GL `StyleRules` and becomes deletable the day `StylingActive` probes true. This is the one place the prompt's "delete the redundant tween code paths" cannot be satisfied honestly today; both paths never *run* simultaneously (styling is inert), so the "both-sides bug" is impossible now, and the flag decides later.

### 2.3 Breaking-or-not verdict
**NON-BREAKING.** Zero component API changes; all Types additions optional; Classic/AC render byte-identically (verified). Phase 1 proceeds.

## 3. SCHEMA ADDITIONS
- `Types.UIThemeEffect`, `UIThemeCornerSet`; `UITheme.EffectShadows/EffectGlows/DialectTokens/StyleRules` (all optional).
- GL tokens: `DialectTokens.comic{ink, paper, shadowSlantX/Y, slantDeg, halftoneDrift}`, `DialectTokens.tech{phosphor, bg, panel, grid, bloomTransparency}`.
- Tags per §2 registry. Rarity→glow axis: none / `glow.md` gold / `glow.lg` white-hot + pulse (consumed by DrawCeremony).

## 4. ASSET SPEC (angular 9-slice art — optional upgrades over the shipped code-only slants)
The pack ships art-free: slants are whole-element `Rotation` on ART children (no skew exists in Roblox). These assets upgrade silhouettes when authored:
| Asset | Size | Slice | Notes |
|---|---|---|---|
| `gl_panel_slant_L/R.png` | 512×256 | 96,96,416,160 | 4° chamfered panel plate; sticker shadow stays native UIShadow (rect shadow hides behind hard offsets — verify per asset; bake only where silhouette shows) |
| `gl_speedline_tile.png` | 256×256 tiled X | — | action-line texture for CutIn/SlashTransition (code fallback: stripe frames) |
| `gl_halftone_tile.png` | 128×128 tiled XY | — | drift layer (E1) |
| `gl_star_burst.png` | 512×512 | — | E9 rotating star frame |

## 5. FILE MANIFEST (Rojo: `src/Client` → `StarterPlayerScripts.ClientHandler`)
```
UI/Style/{Capabilities,Tags,StateDriver,TokenBridge,SheetBuilder}.luau   (new)
UI/Themes/{GurrenLagannTheme,GurrenLagannTechTheme}.luau                 (new)
UI/Components/{GLSlamText,GLAngularButtonComponent,GLSpiralGauge,GLCutIn}.luau (new)
UI/Framework/{CurrencyFlight,SlashTransition}.luau                       (new)
UI/Screens/DrawCeremonyScreen.luau                                       (new)
UI/{Types,UIChrome,UIStyler}.luau, UI/Framework/Layers.luau,
UI/Controllers/UIThemeController.luau, UI/Config/UIThemeConfig.luau,
ClientHandler.client.luau                                                (edited)
```

## 6–7. DELIVERABLES A–D, E1–E10 (boundary per 0.4 stated in every module header)
- **B SlamText / C AngularButton / D SpiralGauge+CutIn / E3 / E4 / E8**: full `--!strict` modules (see manifest; built + adversarially verified this session). C's hover/press appearance is authored twice by design during the bridge era: GuiState rules in `StyleRules` (dormant) + Motion-token imperative fallback (active); the flag decides, never both at once.
- **A hierarchy trees**: Main Action Menu (COMIC) = `UIPanel.DialectComic` root → sticker-shadow rule, GLAngularButtons (tags `UIButton UIButtonPrimary`), gold-heat `UIChip.UIFeatured`; Gunmen tooltip (TECH) = `UIPanel.DialectTech` root → phosphor bloom rule, `UIValue` rows, hairline strokes. Both realized in the ThemeSelector preview + DrawCeremony compositions.
- **E1 Living home** (spec): breathe = one ticker sine on a `UIScale` (≤1%); parallax = gyro/mouse offset ≤6px, off on reduce-motion; halftone drift via `dialect.comic.halftoneDrift`; badge pulses ride `UIFeatured`. Budget target <0.5ms idle: our shared-ticker pattern measured ~0.1ms at 60 handlers in AC HUD — within budget; re-measure on the GL home when built.
- **E2 Carousel** (spec): manual pager + tokenized advance (`carousel.advanceSeconds` = 6), SlashTransition as the page wipe, pause-on-hover, drill page dots = `UISlot` pills.
- **E5 Stamp-slam** (spec): DailyRewards claim → rotated `CLAIMED` label (tilt = `dialect.comic.slantDeg`×2, Back easing, 3px shake tick); next cell `StateDriver.Set(UIFeatured, true)`.
- **E6 Timers** (spec): the existing 1Hz shared clock pattern (`UIChrome.FormatCountdown` grows `9d2h` magnitude form); sub-hour flips `UIDanger` via StateDriver.
- **E7 Badges** (spec): count chips tagged `UIChip`; appear pop via Motion tokens; micro-pulse only while `UIFeatured`; clear = shrink.
- **E9 Starburst** (spec): star frame slow-rotate on ticker; numerals overshoot via Motion.PopIn; shimmer = `UIGradient` offset on ticker (`::UIGradient` unverifiable-live → Luau side for now). Close X full-size, immediate.
- **E10 Results** (spec): grade via GLSlamText; SpiralGauge overcharge cameo on threshold (flips `UIMaxed`); stars punch sequentially with shake ticks; instant skip to summary.

## 8. INTEGRATION
Boot: `Capabilities.Detect()` → `Layers.Init()` → first `ApplyThemeObject` builds BaseTokens + pack sheet + links. Swap demo: `UIDebug.SetTheme("GurrenLagann"|"GurrenLagannTech"|"ArmoredCore"|"Default")` — screens rebuild (Phase-16 machinery), sheet re-links, zero component edits. Transitions on/off: identical rendering today by construction (transitions inert); when live, `TransitionsActive=false` forcing reproduces today's look.

## 9. VERIFICATION CHECKLIST (executed where the environment allows)
- [x] Capability probes (this doc §1) — live engine, screenshots
- [x] Classic + AC render identically after Phase 0 (live boot + swap, font/stroke censuses match pre-migration)
- [x] GL ↔ AC ↔ Classic swap via `SetTheme` only — zero component edits
- [x] Dialect via tags only (`StateDriver.SetDialect`); single-dialect packs pay nothing
- [x] Sheets built + linked; `StyleReport` seam returns probe results
- [x] Shadow budget counter live; DrawCeremony worst case ~24 < 80 warn line
- [x] Pooled glows disable-not-destroy (verified in module reviews)
- [ ] Transitions round-trip — unverifiable until the engine activates styling application (blocked, not skipped)
- [x] Reduce-motion sheet substitution path (rebuild+relink) implemented; Luau reduceMotion collapses choreography
- [x] 100× open/close zero connection growth (module verifiers walked lifecycles)
- [x] Sticker-shadow-behind-slanted-chrome: rect shadow at hard offset reads correctly behind rotated ART frames (probe screenshot); per-asset re-check owed if 9-slice art lands
- [x] CJK SlamText fallback; flash ≤3/s; shake ≤6px capped in modules

## 10. ASSUMPTIONS & RISKS
1. **The big one:** styling application is off in this environment. Everything sheet-side is dormant-by-design; if the shipped behavior differs from the authored rules (selector semantics, priority resolution, pseudo-instance materialization), the GL `StyleRules` table needs an audit the day `Detect()` flips true. The imperative path guarantees the look meanwhile.
2. Property reads not reflecting rules is assumed to persist when styling activates (CSS-like override model). If it instead writes properties, the AbsoluteSize detector still works.
3. `Spread: UDim2` per live probe — specs claiming `number` are wrong for this build; tokens use UDim2.
4. `Bangers`/`Jura` assumed present in the font catalog; `face()` falls back to FredokaOne/Code without erroring if absent (render check owed on first GL boot).
5. No Focus GuiState → gamepad focus ring stays Luau (rectangular bounds on slanted chrome, per a11y rule).
6. Compound tag selectors (`.UIPanel.DialectComic`) accepted at set-time; render semantics unverifiable here. Fallback documented: hierarchy combinator from a dialect-tagged ancestor.
7. `::UIGradient`/`::UIScale` stylability unverifiable live → shimmer/scale pops stay Luau until proven.
8. Transitions-fire-only-on-styling-changes constraint is designed around (StateDriver tag flips are the trigger surface) but untestable here.
