# App4Crawl — User Guide

## System Requirements

- macOS 14 (Sonoma) or later
- Python 3.10 or newer (the app will help you install it if missing)
- Roughly 1 GB of free disk space for the Crawl4AI environment and Chromium

## Installation

1. Download `App4Crawl.dmg` from the releases page.
2. Open the disk image and drag **App4Crawl** into your Applications folder.
3. Launch App4Crawl from Applications (or Spotlight).

## First Launch

On first launch, App4Crawl checks your system for Python and Crawl4AI. If they
are not present, an onboarding screen guides you through a one-time setup:

1. **Environment check** — shows the Python version found (or not found).
2. **Install** — sets up an isolated environment and installs Crawl4AI plus a
   managed copy of Chromium.
3. **Progress** — live output is shown so you can see exactly what is happening.
4. **Verification** — runs a health check and reports the result.
5. **Done** — you are taken to the main app.

If everything is already installed, you go straight to the main screen.

## How to crawl a URL

1. Click **New Crawl**.
2. Paste or type a URL.
3. Click **Run**.
4. View the result in the Markdown / JSON / HTML tabs.

## How to run a deep crawl

1. Start a new crawl and open the **Advanced** section.
2. Choose a strategy (**BFS** or **DFS**).
3. Set the **depth** and **page limit**.
4. Click **Run** and watch progress stream in live.

## Using LLM extraction

1. In a crawl's advanced options, enable **LLM extraction**.
2. Pick a provider and model.
3. Choose schema-based or instruction-based extraction and fill in the details.
4. Run the crawl; extracted data appears in the JSON tab.

## Managing API keys

Open **Settings** (⌘,) → **API Keys**. Add a key per provider. Keys are stored
securely in the macOS Keychain and are never written to disk or sent anywhere
except to the provider you choose, per crawl.

## Exporting results

From the result viewer, use **Export** to save output as `.md`, `.json`, or
`.html`.

## Troubleshooting

- **Python not found:** install Python 3.10+ from python.org or via Homebrew
  (`brew install python`), then relaunch.
- **Install failed:** check the onboarding log view for the error and retry.
- **Crawls hang or fail:** open Settings → Environment and try reinstalling or
  updating the Crawl4AI environment.

## FAQ

**Do I need to know Python?** No. The app manages its own environment.

**Where is my data stored?** Crawl logs and settings live in `~/.app4crawl/`.
API keys live only in the macOS Keychain.

**Is my data sent to the cloud?** Only when you explicitly use LLM extraction
with a cloud provider. Crawling itself runs locally.
