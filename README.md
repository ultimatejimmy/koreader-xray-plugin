# X-Ray Plugin for KOReader

*Note: This is a fork of the original plugin by [0zd3m1r/koreader-xray-plugin](https://github.com/0zd3m1r/koreader-xray-plugin).*

![Platform](https://img.shields.io/badge/platform-KOReader-green.svg)
![License](https://img.shields.io/badge/license-MIT-yellow.svg)

This plugin brings Amazon Kindle's X-Ray functionality to KOReader. It uses AI (Google Gemini or ChatGPT) to analyze the book you're reading and extract character details, locations, and historical context. 

The prompts are designed to be spoiler-free based on your current reading progress, and all the generated data is cached locally so you only need an internet connection the first time you analyze a book.

## Features

- **Character Tracking:** Automatically extracts character names, roles, and descriptions. 
- **Context & Lore:** Generates a timeline of key events, identifies real historical figures mentioned in the text (along with brief biographies), and lists important locations.
- **Spoiler-Free:** The AI is instructed to avoid revealing major plot twists beyond your current reading progress.
- **Local Caching:** Data is fetched once and saved locally per book. It never expires and works completely offline after the initial setup.
- **Multiple AI Providers:** Supports Google Gemini (free tier works great) and OpenAI's ChatGPT.
- **Multilingual:** Supports interface and AI responses in English, Turkish, Portuguese, and Spanish.

## Setup

[Get Started](https://github.com/ultimatejimmy/koreader-xray-plugin/wiki/Get-Started)