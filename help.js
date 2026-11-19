// Content for the in-app help panel (F1 or Ctrl+/). Plain data so it can be tested
// and edited without touching layout. Keep it in step with README.md's Keys table.

var shortcuts = [
  { title: "Basics", items: [
    ["Your shortcut", "Open or close the clipboard (bind it in bindings.lua, see the README)"],
    ["Your second shortcut", "Pin whatever you just copied, without opening (pinCurrent)"],
    ["Type", "Search"],
    ["Up / Down", "Move through the list"],
    ["PgUp / PgDn", "Jump a page (Home / End: top / bottom)"],
    ["Enter", "Paste the selected entry"],
    ["Shift+Enter", "Copy only, without pasting"],
    ["Alt+Enter", "Open a link or file"],
    ["Alt+1..9", "Paste row 1 to 9 straight away"],
    ["Esc", "Clear the search, then the selection, then close"],
    ["F1 or Ctrl+/", "This help"]
  ]},
  { title: "Views and groups", items: [
    ["Tab / Shift+Tab", "Next or previous view in the side rail"],
    ["Ctrl+1..9", "Jump to a view: 1 Recent, 2 All pinned, 3 Frequent, 4+ your groups"],
    ["Ctrl+Left / Right", "Switch tab: Clipboard, Links, Screenshots"],
    ["Alt+Left / Right", "Switch the All, Favorites and tag tabs inside All pinned"],
    ["Ctrl+F", "Search this view only, or everywhere"],
    ["Ctrl+N", "New group"],
    ["F2", "Rename the current group"],
    ["Ctrl+Delete", "Delete the current group (its pins are kept, ungrouped)"]
  ]},
  { title: "Pins", items: [
    ["Ctrl+P", "Pin or unpin (into the group you used last)"],
    ["Ctrl+M", "Move a pin to another group"],
    ["Ctrl+E", "Give a pin a label"],
    ["Ctrl+D", "Favorite (pins it first if needed)"],
    ["Ctrl+Shift+E", "Add tags, comma separated"]
  ]},
  { title: "Select and delete", items: [
    ["Delete", "Delete the selected entry, or everything ticked"],
    ["Ctrl+Space", "Tick the entry and move down"],
    ["Shift+Up / Down", "Tick rows as you move"],
    ["Shift+click", "Tick a row; Shift+click another to tick everything between"],
    ["Ctrl+click", "Tick or untick one row"],
    ["Ctrl+A", "Tick everything the search matches (again to untick)"],
    ["Ctrl+K", "Clean up: unused for 30 days, secrets, very large"],
    ["Shift+Delete", "Clear the whole history (pins are kept)"],
    ["Ctrl+Z", "Undo the last change"]
  ]},
  { title: "Paste tools", items: [
    ["Ctrl+Enter", "Paste every ticked entry, Tab between each"],
    ["Ctrl+Shift+Enter", "Paste every ticked entry, one per line"],
    ["Click the text, or F4", "Edit the text in the preview. It saves by itself. Esc leaves the box, Ctrl+Enter pastes your edit"],
    ["Ctrl+T", "Paste as: plain, one line, case, JSON, Base64, URL"],
    ["Ctrl+R", "Show hidden secrets"],
    ["Ctrl+O", "Copy the text found in an image"]
  ]},
  { title: "Window", items: [
    ["Ctrl+= / Ctrl+-", "Bigger or smaller window: Compact, Normal, Full"],
    ["Ctrl+Shift+Up / Down", "Make everything larger or smaller"],
    ["Ctrl+,", "Settings"],
    ["Ctrl+Shift+P", "Private mode: stop recording copies"]
  ]},
  { title: "Screenshots tab", items: [
    ["Arrows", "Move through the grid"],
    ["1..9", "Put the shot in a category"],
    ["0", "Take it out of its category"],
    ["F", "Favorite"],
    ["Delete", "Move to Trash (R restores)"],
    ["Z", "Undo"],
    ["T", "Triage: sort the inbox one shot at a time (Space skips)"],
    ["/ or Ctrl+F", "Search, including text inside the images"],
    ["Enter / Shift+Enter", "Paste the image / copy it"],
    ["Alt+Enter", "Annotate it"],
    ["Ctrl+O", "Copy the text in it"],
    ["Tab", "Next view: Inbox, All, Favorites, categories, Trash"],
    ["Ctrl+N / F2 / Ctrl+Delete", "New, rename, delete category"]
  ]}
]

var guide = [
  { title: "What it is", body: [
    "A clipboard history with pins. Everything you copy is kept here, newest first. Open it with your shortcut, find the entry, press Enter and it is pasted into the app you were in.",
    "Omarchy's own clipboard keeps recording in the background; this app reads that history and keeps a longer archive of its own (2,000 entries by default, up to 10,000)."
  ]},
  { title: "Finding things", body: [
    "Just type. Every word has to match, in any order, and the best matches come first: titles that start with your word, then whole words, then partial ones. A typo-tolerant match kicks in when nothing else fits.",
    "Narrow a search with filters: is:url, is:image, is:code, is:secret, is:pinned, is:fav, app:firefox, in:dev (a group) or tag:work. Mix them with words, for example \"is:url github\".",
    "Search looks in the current view. When matches exist elsewhere, a line under the results says how many; Ctrl+F searches everywhere."
  ]},
  { title: "Pins and groups", body: [
    "Pin anything you will need again with Ctrl+P. Pins never expire and survive clearing the history. They live in groups shown in the side rail: Dev, Writing, Links and any you add with Ctrl+N.",
    "Give a pin a label (Ctrl+E) so it reads well in the list, star it (Ctrl+D), or tag it (Ctrl+Shift+E). Inside All pinned, the strip of tabs above the list jumps to Favorites or a tag.",
    "A pin can be a template: {{date}}, {{time}}, {{weekday}}, {{clip}}, {{uuid}} and {{ask:Name}} are filled in when you paste it."
  ]},
  { title: "Pasting several things", body: [
    "Tick entries with Ctrl+Space in the order you want them, then press Ctrl+Enter to paste them all with Tab in between (good for forms), or Ctrl+Shift+Enter for one per line.",
    "Ctrl+T pastes the selected entry transformed: plain text, a single line, upper or lower case, pretty or minified JSON, Base64, URL encoded."
  ]},
  { title: "Deleting in bulk", body: [
    "Shift+click the first entry, then Shift+click the last: everything between is ticked. Ctrl+click ticks single rows, and the checkbox button in the header turns on tick boxes for plain clicks. Keyboard: Ctrl+Space and Shift+Up/Down. Ctrl+A ticks everything a search matches. Ctrl+K offers ready-made sets: unused for 30 days, secrets, very large.",
    "Press Delete. Over 10 entries asks first, and Undo on the notice brings everything back."
  ]},
  { title: "Secrets and privacy", body: [
    "API keys, tokens, private keys, passwords and card numbers are hidden in the list (Ctrl+R shows them) and deleted after a time you choose unless pinned.",
    "Private mode (Ctrl+Shift+P) stops recording until you turn it off; the header says Private. In settings you can list apps whose copies are never kept, such as a password manager."
  ]},
  { title: "Screenshots", body: [
    "The Screenshots tab turns ~/Pictures into an inbox. New shots appear within a second. Sort them with the number keys into categories, star the keepers with F, and send the rest to the system Trash with Delete; nothing is ever deleted for good.",
    "Press T for triage: one shot at a time, full size, one key each. Search finds words inside the images."
  ]},
  { title: "Make it yours", body: [
    "Ctrl+, opens settings: theme (or follow Omarchy's), accent colour, interface size, corners, font, preview position, how long history is kept, paste method, excluded apps.",
    "Drag any edge or corner to resize; Compact, Normal and Full each remember their own size."
  ]},
  { title: "Backup and sync", body: [
    "Settings can export your pins and groups to a file and import one back. Folder sync keeps two machines in step through a folder that Google Drive, Syncthing or Dropbox already syncs; deletions carry over too."
  ]}
]

if (typeof module !== "undefined") module.exports = { shortcuts: shortcuts, guide: guide }
