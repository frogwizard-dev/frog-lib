# FrogLib

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
