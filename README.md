# FSRTracker - Five Second Rule Tracker for Project-Epoch 3.3.5

Download the .rar in the release and unzip it to your addons folder, or add the two files above to a folder named FSRTracker in your addons...

The first tick will always have to be estimated, usually 0.1-0.5 ish seconds after the 5 second blue bar fills.
All the ticks after that should be 100% on time with your mana regen since it uses the first mana regen tick as the base for the timer...

Enjoy finally drink walking without having to guess mana ticks again! I've been looking for an addon or weakaura that does this for 3.3.5 for a long ass time...

Using it for other 3.3.5 servers will require you to add the missing Wrath spells for your class to the FSRTracker.lua file since I had to hard code them and only added the Project-Epoch spells. Keep in mind that some of them are named differently on Project-Epoch as well.

You can add the missing spells under your class in the same way as explained below, just make sure its the same structure with a ";" in between them, except for at the end of a line.

                  | 
  -- Mage         v add a ; 
  
  add("Frostbolt"); add("Fireball"); add("Arcane Explosion"); add("Arcane Missiles"); add("Fire Blast"); add("Frost Nova") <--- No ;
  
  add("Amplify Magic"); add("Arcane Barrage"); add("Arcane Blast"); add("Arcane Brilliance"); add("Arcane Intellect"); add("Blink")
  
Commands:

/fsr scale <0.5–3.0> — Sets the total scale of FSRTracker, Default: 1.0.

/fsr scalex <0.5–3.0> — Sets the horizontal stretch (width) of FSRTracker, Default: 1.0 (or whatever your total scale is set to).

/fsr scaley <0.5–3.0> — Sets the vertical stretch (height) of FSRTracker, Default: 1.0 (or whatever your total scale is set to).

/fsr unlock — (Unlocks FSRTracker)

/fsr lock — (Locks FSRTracker)

/fsr center — (Centers FSRTracker horizontally)

/fsr hidebg — (Toggles the bar background on/off, only show the spark/line)

/fsr front — (Changes FSRTracker's priority it has over other UI Elements to MAX, so you can display it over your Unit Frame for example.)

/fsr reset — (Resets FSRTracker completely, back to factory settings xd)
