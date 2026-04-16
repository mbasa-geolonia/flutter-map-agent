# Flutter Map Agent

<img width="1215" height="781" alt="Screenshot 2026-04-14 at 11 45 49" src="https://github.com/user-attachments/assets/24467cea-8174-4245-bbd8-162d9b78ee76" />


This is a Flutter Application that tries to mimic the Claude Desktop with its Map Artifact Window. All geographic
requests to the LLM will be displayed in the Map Area of the application. Since this is a Flutter application, it can
be deloyed as a Web, MacOS/Win Native, or Mobile Device app. 

### Requirements

The follwing API KEYS will be needed: 
* Mapfan API Key to display Maps
* Anthropic API Key to connect to Claude
* OpenAPI API Key to connect to ChatGPT

### To Build

Create a `lib/config/app_config.dart` based on the app_config.dart.sample and place the required
API KEYS.

