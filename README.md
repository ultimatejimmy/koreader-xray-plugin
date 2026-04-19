# X-Ray Plugin for KOReader

*Note: This is a fork of the original plugin by [0zd3m1r/koreader-xray-plugin](https://github.com/0zd3m1r/koreader-xray-plugin).*

![Platform](https://img.shields.io/badge/platform-KOReader-green.svg)
![License](https://img.shields.io/badge/license-MIT-yellow.svg)

This plugin brings Amazon Kindle's X-Ray functionality to KOReader. It uses AI (Google Gemini or ChatGPT) to analyze the book you're reading and extract character details, locations, and historical context. 

The prompts are designed to be spoiler-free based on your current reading progress, and all the generated data is cached locally so you only need an internet connection the first time you analyze a book.

## Features

- **X-Ray Selection Mode:** Adds an "X-Ray" button to the dictionary and text selection menus. Highlight a name or location on the page to instantly see its description without leaving your book.
- **Character Tracking:** Automatically extracts character names, roles, and descriptions. 
- **Sequential Timelines:** Generates a strictly chronological timeline of key events (one per chapter), making it easy to catch up on the plot.
- **Context & Lore:** Identifies real historical figures mentioned in the text (along with brief biographies) and lists important locations.
- **Robust AI Fetching:** Automatically retries failed requests using secondary and lighter models (Flash -> Pro -> 8b) to ensure you always get your data.
- **Kindle Optimized:** UI designed specifically for stability and performance on older e-ink hardware like the Kindle Paperwhite 1.
- **Spoiler-Free:** The AI is instructed to avoid revealing major plot twists beyond your current reading progress.
- **Local Caching:** Data is fetched once and saved locally per book. It works completely offline after the initial setup.
- **Multilingual:** Supports interface and AI responses in English, Turkish, Portuguese, and Spanish.
- **Updater:** Built-in updater for the plugin itself. Just click on "Check for Updates" in the menu to update the plugin.

## Setup

[Get Started](https://github.com/ultimatejimmy/koreader-xray-plugin/wiki/Get-Started)