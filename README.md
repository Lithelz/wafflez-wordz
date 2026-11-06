# 🧇 Wafflez Wordz

A writing assistant for your Mac, with a midnight theme that matches macOS dark mode. It checks your writing in other apps' text boxes, and comes with **Wafflez Studio**, its own window for AI writing, the AI Humanizer, the AI Detector and the plagiarism checker.

- **Everywhere:** colored underlines, a floating widget, suggestion cards, a rewrite bar on selected text, definitions, tone, and a side tab. It works in Mail, Messages, Notes, Pages, Word, Outlook, Slack and text boxes in Safari and Chrome.
- **Google Docs:** Google Docs draws its text on a canvas that no outside app can read, so underlines can't appear there. Select text and press **⌃⌥W**. Wafflez checks it in a Quick Check window and pastes the fixed text back. This also works in Pages, Notion, Figma or any other app.
- **Studio:** a full editor with live checking, an agents panel, AI chat, Authorship, Insights and team tools.

All checking runs on your Mac. AI features use Claude with **your own API key**, which is stored in the macOS Keychain. No key is in this repo.

---

## Build and run

You need macOS 14 (Sonoma) or newer and Xcode 16 or newer (or the Command Line Tools).

```bash
git clone <this repo>
cd wafflez-wordz
./scripts/build_app.sh --install
```

That builds `build/Wafflez Wordz.app`, copies it to `/Applications` and opens it. You can also download a ready-built app from the latest **Actions → Build** run (the `Wafflez-Wordz-app` artifact).

**Opening a downloaded build:** the app is signed ad hoc, not notarized. The first time, right-click it and choose **Open**, or allow it in **System Settings → Privacy & Security**.

### First launch

1. **Accessibility:** macOS asks you to allow Wafflez in **System Settings → Privacy & Security → Accessibility**. This lets it read and fix text in other apps. If you rebuild the app later, remove it from that list and add it again, because each ad-hoc build counts as a new app. To avoid this, sign with your own identity: `SIGN_IDENTITY="Apple Development: …" ./scripts/build_app.sh`.
2. **Claude API key (optional):** go to Studio → Settings → AI and paste a key from console.anthropic.com. Without a key, everything except the AI features still works.

### Develop in Xcode

Run `open Package.swift`, pick the **WafflezWordz** scheme and press Run. The core engine (`WafflezCore`) is plain Foundation code, so `swift test` runs on Linux too.

---

## Keyboard shortcuts (change them in Settings → Shortcuts)

| Shortcut | What it does |
| --- | --- |
| ⌃⌥W | Check the selected text in any app (the Google Docs path) |
| ⌃⌥Space | Write with AI (the lightbulb) |
| ⌃⌥R | Rewrite the selected text |
| ⌃⌥C | Open the Wafflez side panel |
| ⌃⌥S | Insert a snippet |
| ⌃⌥P | Pause or resume Wafflez |

---

## Feature map

| Feature | Where it is in Wafflez Wordz |
| --- | --- |
| Button in text boxes with a suggestion count | **Widget** at the lower right of the focused text box (drag it to any corner; the spot is saved per app). Small one-line boxes are skipped. |
| Colored underlines | Red = correctness, blue = clarity, green = engagement, purple = delivery, gray = style guide |
| Suggestion cards | Hover or click an underline. The card has the fix, Dismiss, Add to dictionary, Learn more, Turn off suggestions like this, Report, Next, and Review all. An Undo toast appears after you accept. |
| Tone detector | Emoji on the widget after 150 characters. Click it for the tone breakdown plus formality, confidence and warmth meters. |
| Definitions and synonyms | Double-click a word. The definition comes from the macOS Dictionary; synonyms replace the word when you're editing; "More synonyms with AI" asks Claude. |
| Settings inside text boxes | Menu bar menu: turn off for 1 hour, turn off in this app, side tab on/off. Everything else is in Studio → Settings. |
| Mac app floating widget and right-edge tab | Widget, plus the **Wafflez tab** that appears at the right edge of the screen (drag it up or down) |
| Go-style chat with screen context | **Side panel → Chat** uses the window in front. **Attach** points it at any open window. You can attach up to 5 files (images up to 7 MB, other files up to 30 MB). |
| Lightbulb prompt | Lightbulb next to the widget, or ⌃⌥Space, with suggested prompts. Results come with Insert, Retry and Copy. |
| Highlight to rewrite | A blue bar appears beside selected text. It offers Improve, Shorten, Professional, Friendly, Confident, Simplify, Fix grammar, Expand, Humanize, **Revise with AI** (your own instruction) and Accept. |
| Reply quickly | A **Reply** button on the widget in Mail, Outlook and Gmail. You get a summary plus 3 reply ideas, and a full reply with the right names. |
| Ask / Translate / Explain | In the same selection menu. Translate covers 19 languages. |
| Docs with an agent panel | **Wafflez Studio** documents. The right panel has Review, Agents, Chat and Stats. Slash commands include `/h1 /h2 /h3 /bullet /todo /quote /table /divider /date /snippet /ai`. |
| Agents | Proofreader, Paraphraser (including "My voice"), **Humanizer**, Expert Review, Reader Reactions, AI Grader (with rubric upload), Citation Finder (live web search), **AI Detector**, **Plagiarism Checker**, Authorship, AI Chat, Resume Builder |
| AI detector | Runs on your Mac. Shows "NN% appears AI-generated", flags sentences with reasons, and can ask Claude for a second opinion. It is clearly labeled as an estimate, not proof. |
| Plagiarism checker | Compares against your Studio library and any source files you add (on your Mac), and searches the web through Claude. Shows matches, highlights them, and offers to cite or rewrite. |
| Authorship | Fingerprint button. Labels text as typed, pasted, AI, Wafflez edits or already there; colors the document by origin; has a replay slider; exports a self-contained HTML report anyone can open |
| Citations | Auto-citations when you paste from the web, the Citation Finder, and a free citation generator for APA, MLA and Chicago with in-text citations |
| Pro writing features | Tone adjustments, full-sentence AI rewrites (on clarity cards), inclusive language, fluency, turning suggestion types off one by one, and goals (audience, formality, domain, intent). All of them are included. |
| Team features | Style guide (gray underlines), brand tones (shape AI output and flag words to avoid), snippets, Knowledge Share glossary, and Insights with an Effective Communication Score |
| AI prompt limits | You can set an optional monthly cap yourself. Confidential mode turns off every AI call. |
| Dialects | American, British, Canadian, Australian and Indian English |

### Not included

These parts of the guide don't apply to a personal Mac app: the iPhone/Android keyboard, browser extensions (the Mac app covers browsers through Accessibility), and enterprise admin features (SSO, SCIM, audit logs and so on).

---

## Project layout

```
Sources/WafflezCore/      Writing engine (Foundation only, tested on Linux and macOS)
  Rules/                  Correctness, clarity, engagement, delivery, dialect and style guide rules
  ToneDetector, AIDetector, Humanizer, OriginalityChecker, Authorship, Citations
  AI/                     Claude Messages API client (raw HTTPS) and every AI feature's prompt
Sources/WafflezWordz/     macOS app
  App/                    Entry point, menu bar, settings, Keychain, hot keys, theme
  Everywhere/             Accessibility layer, underline overlay, widget, cards, side panel, Quick Check
  Studio/                 Studio window, editor, agents, chat, team tools, insights, settings
Tests/WafflezCoreTests/   Unit tests for the engine
scripts/                  build_app.sh (makes the .app) and make_icon.py (draws the icon)
```

## Privacy

- On-device checks never send text anywhere.
- AI requests go only to `api.anthropic.com`, only when you use an AI feature, and only with your key.
- Password fields are never read.
- No analytics, accounts or tracking.
