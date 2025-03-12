# GHL-Preview
A ReaScript made to preview custom Guitar Hero Live Charts

# Version 1.0
This new version includes:
- Buttons to switch between difficulties
- Button to increase/decrease highway speed
- Button to increase/decrease offset
- Lyrics visualizer: Button to toggle the lyrics display on/off
- Vocal HUD: Button to toggle the vocal HUD (GHL style)
- Visual indicator when hitting a note in the Vocal HUD
- Future notes are now drawn behind, not above, the first, giving a sense of depth
- Shortcuts to toggle the lyrics display and vocal HUD on/offs

  Note:
  In the lyrics display, to avoid using spaces or hyphens (which you missed when charting), the following will not be displayed:
  - The syllable-connecting hyphen **"-"**
  - The plus sign **"+"** that connects notes
  - the toneless letter/note marker **"#"**
  - The equal sign **"="**, which acts as a hyphen **"-"** in some cases, will be displayed as a hyphen in the display.
  
  Lyrics marked as pitchless **"#"** will be displayed in white.  
  Notes **26** and **29**, as well as notes marked as pitchless **"#"**, will be vertically centered in the vocal HUD (as in GHL).

![image](https://github.com/user-attachments/assets/27ec277e-dcd1-45b4-abe1-7d49f43435f4)

## Installation instructions:
1. Download .zip of repository
2. Extract .lua **and** assets folder to **%appdata%/REAPER/Scripts**
3. In REAPER, go to **Actions > Show action list...**
4. Click **New action...** and then **Load ReaScript...**
5. Navigate to **%appdata%/REAPER/Scripts**
6. Select **GHL_Preview.lua** and click **Open**
7. Optionally, add a keybind, or use the Menu Editor to add the action to a menu

## Additional notes:
For a better experience, use the included color map and note names!  
Guitar events (106 to 114 and 118) are exclusive for Guitar Hero Live (sfx preview included).  
Requires **Genshin Impact** font (SDK_JP_WEB 85W), extract it yourself.

## Modified by GHCripto:
Defaults to Expert Guitar GHL  
Based on Marie's clean art style

##
Credits to _NarrikSynthfox_ for the original codebase and _Marie_ for her modification I based it on to adapt it to GHL and add the new features mentioned above.
