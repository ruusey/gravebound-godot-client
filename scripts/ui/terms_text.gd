class_name TermsText
extends RefCounted

## The Terms of Use and Privacy Policy as the gate shows them: the web
## client's terms-gate body (index.html), word for word, as BBCode for a
## RichTextLabel. That copy ships inside the data service that records the
## acceptance, so it is the version the acceptance is of. When the service
## bumps CURRENT_TERMS_VERSION, this is the text to bring across with it.

const TITLE := "Terms of Use & Privacy Policy"
const SUBTITLE := "Please read the terms below. The I Agree button unlocks once you've scrolled to the end."
const SCROLL_HINT := "Scroll down to read all terms"

const BODY := """[color=#8a8078]Copyright © 2024–2026 Robert Usey <ruusey@gmail.com>. All Rights Reserved.[/color]

[font_size=15][b][color=#ffd96b]License & Prohibited Conduct[/color][/b][/font_size]
GraveBound and its client, artwork, audio, data files, and the network protocol used to communicate with GraveBound servers (the “Software”) are the exclusive property of Robert Usey (the “Owner”) and are protected by copyright law and international treaties. The Software is licensed, not sold.

Subject to your compliance with these Terms, you are granted a personal, limited, non-exclusive, non-transferable, revocable license to use the official GraveBound client solely to play GraveBound. All rights not expressly granted are reserved. You may [b]NOT[/b]:
[ul]
copy, modify, distribute, sublicense, or create derivative works of the Software;
reverse engineer, decompile, or disassemble the Software — which expressly includes intercepting, capturing, recording, injecting, replaying, or modifying network traffic between the client and our servers, and emulating, spoofing, or reimplementing the network protocol;
extract, rip, or redistribute the game’s assets or data files;
use, create, or distribute bots, cheats, memory editors, packet tools, or modified / unofficial clients;
circumvent, disable, or interfere with any security, authentication, or access-control measure; or
remove or alter any proprietary notices.
[/ul]
Any unauthorized use is a material breach of these Terms and may result in civil and criminal penalties, and/or violate anti-circumvention (e.g., 17 U.S.C. § 1201) and computer-misuse laws. We may suspend or terminate your account at any time for any violation. The Software is provided “AS IS”, without warranty of any kind.

[font_size=15][b][color=#ffd96b]Privacy[/color][/b][/font_size]
The only personal information we collect is the email address you use to create your account. We do [b]not[/b] use cookies, analytics, advertising, or third-party trackers, and we do not sell or share your information. Your email is used only to identify your account and for essential messages (e.g., password resets); your in-game progress and characters are saved to your account.

To run the game and protect it from abuse, our servers necessarily process your device’s IP address during your session for connection, security, and anti-cheat. We do not use it to track you and retain it only briefly for security and debugging. You may request access to or deletion of your account and email at any time by contacting ruusey@gmail.com.

[color=#8a8078]The full Terms of Use and Privacy Policy are on the GraveBound web client (terms.html, privacy.html). By clicking “I Agree” you confirm you have read and accept these Terms and the Privacy Policy.[/color]"""
