# FrogLib

## 1.4.0

- Plates: the machinery for restyling enemy nameplates, out of FrogPlates so XIVPlates can share it. It takes the plates over (Blizzard's made see-through, its cast bar and auras kept), follows casts you can't interrupt and the time left on them, works out execute range, quest targets, threat colours and text, and tells the addon's skin when to build, lay out and fill in each plate. One addon drives the plates at a time.

## 1.3.0

- Debuff borders in their dispel type's colour on every add-on's aura rows (FrogFrames, FrogTarget, XIVTarget, XIVPlayer, Personal Resource Tweaks): magic blue, curse purple, disease brown, poison green, the game's own colours, worked out by the game so they show even when the type is hidden from add-ons. Debuffs with no type keep the row's own border colour.
- Every tabbed settings window has a search box under its tabs: the words with your text on them are marked on every page, closed sections with a match open while you search (and close again after), tabs with nothing are dimmed, and the window moves to a page with a match (scrolled to the first) when the open one has none.
- Hiding a frame can leave it where it is and only make it invisible, for frames whose own code needs their parent (Blizzard's experience bar, which broke Edit Mode with a Lua warning when moved).
- Settings windows can have a sidebar instead of tabs: the pages listed under headings, with a search box that keeps only the pages with your words on them and marks the words.
- Settings pages in columns of headed groups (a gold heading with a faint rule under it), so every add-on's settings can be laid out the same tidy way.
- Combo points drawn as art: one point's opacity from your count, worked out by the game when the count is hidden (FrogFrames' vanilla combo points).
- A "SHADOW" font outline ("Drop shadow" in every add-on's outline choices): no outline, a soft black shadow under the text instead, set by FrogLib's font setter (at least a whole screen pixel, so small text such as nameplates' still shows it) and taken off again when another outline is chosen.
- A fourth shared border: Classic's action bar frame, the carved stone round each button of the old bar (Blizzard's own art), at a whole number of screen pixels per texel so it stays crisp. FrogFrames' Stone look uses it.
- The stat list for your pet too: the game's own pet stats, its damage per second and attack speed, a hunter's pet's happiness, loyalty, training points, experience and the food it eats, and its resistances.
- Your pet's happiness, loyalty, training points and food read through Forever's own pet functions (C_PetInfo), so they show.
- Fading when idle can leave the power out, for a pet: its focus can be hidden from add-ons and ticks on even when full, so it never seemed to settle.
- Game settings several add-ons change, in layers (FrogInteract's all the time, FrogFish's on top while fishing), with your own put back once none of them wants a change, at every logout, and after a crash.

## 1.2.0

- The character sheet's stats as one long list, filled by the game's own stat functions (FrogUI's stats pane and StatSheet's List tab).

## 1.1.0

- Settings controls: the checkboxes, steppers, sliders, dropdowns, colour swatches, text boxes, sections that open and close, and tabbed settings windows every add-on's settings are built from, in one place instead of a copy in each. Dropdowns show the current choice afresh when their page opens, and shift-clicking + or - moves ten steps, in every add-on.
- Saved settings filled in from their defaults, and each add-on's chat messages, from one place.
- FFXIV gauges (the XIV add-ons' and EnmityList's bars, with absorb shields), from one place; FrogTarget's bars share the shields.
- One layout grid for every add-on that's unlocked (FrogTarget, FrogFrames): locking one no longer hides the grid while the other is still unlocked.
- The character window's width when both FrogUI and StatSheet widen it: it grows by both.
- The building blocks of the buff and debuff rows (FrogTarget, XIVTarget, FrogFrames, XIVPlayer, Personal Resource Tweaks), from one place.
- Combo points, the spell lists and aura picker in the settings, showing one of the three border styles, and dragging frames to move them (kept in the add-on's settings only, never also in the game's layout file), each from one place.
- A row of combo point pips any add-on can draw in its own look (XIVTarget's and FrogTarget's new combo points).
- A raid mark that can't be shown now clears instead of leaving the last mark; hidden power types and threat are checked for before anything else is done with them.

## 1.0.0

- First version, on its own: the code Frog Wizard's add-ons share (their "Frog Wizard" options page, texture and font lists, pixel, classic stone and Forever borders, and the threat lead). Each add-on still carries its own copy, added when it's built, so nothing extra needs installing; with several loaded, the newest copy is the one used.
- Hiding Blizzard's frames, for the add-ons that replace them: hidden at once, even in combat, and kept hidden through combat, Edit Mode and loading screens, with what hangs off them (your pet frame, totems, a cast bar locked under the player frame) left on screen. Several add-ons can hide the same frame: it stays hidden while any of them wants it hidden.
- Curves: the game reads a health or power it keeps secret through a step curve, so it can still decide what's shown (an execute range, an empty power bar fading, a fade only at full health).
- Fading when idle: out of combat, at full health, with your power at rest and (if you like) nothing targeted. When the game hides your health, the fade only happens at full health instead of whenever your health stops changing.
- Swing timers: each hand's timer from the game's swings (the weapon's speed standing in when the game hides a swing's length), restarted when you change weapons, when to show them, range, and fading Blizzard's own swing bars, shared by every add-on that hides them.
- Cast bars: reading a cast or channel even when the game hides the spell's name or icon, and when the bar shows: the cast, an interrupt held in red for a moment, a sample while unlocked.
- The five-second rule: when it starts after you spend mana, including casts whose spell the game hides (from the drop in your mana).
- Text templates: the words you type for a bar's text ("value / max  percent"), filled in by the game even when it hides the numbers, with any number of words (more than six used to stop the text updating).
- Unit colours: class colours (a class colour add-on's first), tapped and offline grey, hostile / neutral / friendly, FFXIV's engaged / passive / friend, and power colours, skipping whatever the game hides.
- Unit names, levels (coloured by difficulty, a skull when too high), health and power percentages, class or creature type, and the template words for a unit, safe when the game hides any of them.
- Raid marks that stay visible when the game hides which mark it is, and the leader, role, PvP, quest and class icons by a name.
- Click-to-target buttons with the unit menu on right-click, which still opens on this client.
